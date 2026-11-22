`timescale 1ns/1ps
module tb_rob;
    reg clk, rst_n;

    reg                 alloc_en_i;
    reg  [31:0]         alloc_pc_i;
    reg  [5:0]          alloc_dest_i;
    reg  [5:0]          alloc_old_pd_i;

    reg                 complete_en_i;
    reg  [2:0]          complete_idx_i;
    reg                 complete_except_i;

    wire [1:0]          commit_cnt_o;
    wire [31:0]         commit_pc_o;
    wire [5:0]          commit_free0_o;
    wire [5:0]          commit_free1_o;
    wire                redirect_en_o;
    wire [31:0]         redirect_pc_o;
    wire                full_o;
    wire                empty_o;

    rob uut (
        .clk(clk), .rst_n(rst_n),
        .alloc_en_i(alloc_en_i), .alloc_pc_i(alloc_pc_i),
        .alloc_dest_i(alloc_dest_i), .alloc_old_pd_i(alloc_old_pd_i),
        .complete_en_i(complete_en_i), .complete_idx_i(complete_idx_i),
        .complete_except_i(complete_except_i),
        .commit_cnt_o(commit_cnt_o), .commit_pc_o(commit_pc_o),
        .commit_free0_o(commit_free0_o), .commit_free1_o(commit_free1_o),
        .redirect_en_o(redirect_en_o), .redirect_pc_o(redirect_pc_o),
        .full_o(full_o), .empty_o(empty_o)
    );

    always #5 clk = ~clk;

    reg [1023:0] msg;
    integer err = 0;
    task chk;
        input cond;
        input [1023:0] m;
        begin
            if (!cond) begin
                err = err + 1;
                msg = m;
                $display("FAIL [%0d]: %0s", err, msg);
            end else begin
                $display("PASS: %0s", m);
            end
        end
    endtask

    task tick;
        begin @(posedge clk); #1; end
    endtask

    task alloc;
        input [31:0] pc;
        input [5:0]  dest;
        input [5:0]  old;
        begin
            alloc_en_i = 1'b1;
            alloc_pc_i = pc;
            alloc_dest_i = dest;
            alloc_old_pd_i = old;
            tick;
            alloc_en_i = 1'b0;
        end
    endtask

    task cmpl;
        input [2:0] idx;
        input       exc;
        begin
            complete_en_i = 1'b1;
            complete_idx_i = idx;
            complete_except_i = exc;
            tick;
            complete_en_i = 1'b0;
        end
    endtask

    integer k;
    integer total;
    initial begin
        clk = 0; rst_n = 1;
        alloc_en_i = 0; alloc_pc_i = 0; alloc_dest_i = 0; alloc_old_pd_i = 0;
        complete_en_i = 0; complete_idx_i = 0; complete_except_i = 0;

        // 复位
        #1 rst_n = 1'b0;
        tick;
        #1 rst_n = 1'b1;
        tick;
        chk(empty_o && !full_o, "reset: rob empty");

        // 顺序分配三条 U1/U2/U3
        alloc(32'h100, 6'd10, 6'd32);
        alloc(32'h104, 6'd11, 6'd33);
        alloc(32'h108, 6'd12, 6'd34);
        chk(!empty_o && !full_o, "alloc 3: not empty and not full");

        // 乱序写回 U3、U2，队头 U1 还没完成
        cmpl(3'd2, 1'b0);
        cmpl(3'd1, 1'b0);
        tick;
        chk(commit_cnt_o == 2'd0, "head not done: no commit");

        // U1 写回，下一拍队头连续三项就绪，一次提交两条
        cmpl(3'd0, 1'b0);
        tick;
        chk(commit_cnt_o == 2'd2, "U1 done: commit width 2");
        chk(commit_pc_o == 32'h100, "commit pc = U1");
        chk(commit_free0_o == 6'd32 && commit_free1_o == 6'd33,
            "release old_pd 32 and 33");

        // 剩下的 U3 下一拍提交
        tick;
        chk(commit_cnt_o == 2'd1, "remaining U3: commit 1");
        chk(commit_pc_o == 32'h108 && commit_free0_o == 6'd34,
            "commit pc = U3 and release old_pd 34");
        tick;
        chk(empty_o, "all committed: rob empty again");

        // 异常场景：新三条落在索引 3/4/5，U5 带异常
        alloc(32'h200, 6'd20, 6'd40);   // U4 -> 索引 3
        alloc(32'h204, 6'd21, 6'd41);   // U5 -> 索引 4
        alloc(32'h208, 6'd22, 6'd42);   // U6 -> 索引 5
        cmpl(3'd3, 1'b0);   // U4 写回，无异常
        cmpl(3'd5, 1'b0);   // U6 写回；U4 作为异常之前的正常项先提交
        chk(commit_cnt_o == 2'd1, "exception: U4 commits before exception");
        cmpl(3'd4, 1'b1);   // U5 写回，带异常
        tick;               // U5 到队头，触发精确重定向
        chk(redirect_en_o, "exception: redirect asserted");
        chk(redirect_pc_o == 32'h204, "exception: redirect pc = U5");
        chk(empty_o, "exception: rob flushed empty");

        // 装满 8 项，再写一项应被拒绝
        for (k = 0; k < 8; k = k + 1)
            alloc(32'h300 + k, 6'd50 + k[4:0], 6'd60 + k[4:0]);
        chk(full_o && !empty_o, "alloc 8: full and not empty");
        alloc(32'h400, 6'd63, 6'd63);
        chk(full_o, "alloc when full: rejected, still full");

        // 让 8 条全部完成并提交，累计提交数应为 8
        total = 0;
        for (k = 0; k < 10; k = k + 1) begin
            if (k < 8) cmpl(k[2:0], 1'b0);
            else tick;
            total = total + commit_cnt_o;
        end
        chk(total == 8, "committed exactly 8, no 9th written");
        tick;
        chk(empty_o, "all 8 committed: rob empty");

        $display("----------------------------------------");
        if (err == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", err);
        $display("----------------------------------------");
        $finish;
    end
endmodule
