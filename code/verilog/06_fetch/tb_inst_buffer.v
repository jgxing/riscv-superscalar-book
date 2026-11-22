// ============================================================
// 第 6 章 指令缓冲队列自测
// 重点验证: 1) 指令字与预译码位成对存取  2) 深度确为 8
//           3) 满时拒写  4) 读写同拍
// ============================================================
`timescale 1ns/1ps

module tb_inst_buffer;
    localparam DEPTH    = 8;
    localparam DATA_W   = 32;
    localparam PREDEC_W = 4;

    reg                    clk, rst_n;
    reg                    push, pop;
    reg  [DATA_W-1:0]      push_inst;
    reg  [PREDEC_W-1:0]    push_predec;
    wire [DATA_W-1:0]      pop_inst;
    wire [PREDEC_W-1:0]    pop_predec;
    wire                   full, empty;

    inst_buffer #(
        .DEPTH(DEPTH), .DATA_W(DATA_W), .PREDEC_W(PREDEC_W)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .push(push), .push_inst(push_inst), .push_predec(push_predec),
        .pop(pop), .pop_inst(pop_inst), .pop_predec(pop_predec),
        .full(full), .empty(empty)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    integer k;
    reg [1023:0] msgbuf;

    task chk;
        input [1023:0] msg;   // 位宽够大, 否则长串被截断
        input cond;
        begin
            if (cond)
                $display("PASS: %0s", msg);
            else begin
                $display("FAIL: %0s", msg);
                errors = errors + 1;
            end
        end
    endtask

    // 推入一个包裹: 指令字和预译码位同一拍写入
    task push_pkg;
        input [DATA_W-1:0]   d;
        input [PREDEC_W-1:0] p;
        begin
            push_inst = d; push_predec = p;
            push = 1; pop = 0;
            @(posedge clk); #1;
            push = 0;
        end
    endtask

    initial begin
        clk = 0; rst_n = 1;
        push = 0; pop = 0; push_inst = 0; push_predec = 0;

        // ---- 复位 ----
        rst_n = 0; @(posedge clk); #1;
        rst_n = 1; @(posedge clk); #1;
        chk("after reset: empty=1", empty === 1'b1);
        chk("after reset: full=0",  full  === 1'b0);

        // ---- T1 写满 8 个包裹 ----
        // 指令字用 0x1000+4k, 预译码位用 k, 一一配对
        for (k = 0; k < DEPTH; k = k + 1)
            push_pkg(32'h1000 + k*4, k[PREDEC_W-1:0]);
        #1;
        chk("8 pushes: full=1 (depth is exactly 8)", full  === 1'b1);
        chk("8 pushes: empty=0", empty === 1'b0);

        // ---- T2 满时拒写 ----
        push_inst = 32'hDEADBEEF; push_predec = 4'hF;
        push = 1; pop = 0;
        @(posedge clk); #1;
        push = 0;
        chk("push when full: still full", full === 1'b1);

        // ---- T3 读出全部 8 个, 逐项检查配对 ----
        for (k = 0; k < DEPTH; k = k + 1) begin
            $display("-- checking pop #%0d --", k);
            chk("pop inst matches", pop_inst === (32'h1000 + k*4));
            chk("pop predec matches", pop_predec === k[PREDEC_W-1:0]);
            pop = 1; push = 0;
            @(posedge clk); #1;
            pop = 0;
        end
        chk("8 pops: empty=1", empty === 1'b1);
        chk("8 pops: full=0",  full  === 1'b0);

        // ---- T4 读写同拍 ----
        // 先放两个包裹进去
        push_pkg(32'h2000, 4'b0001);
        push_pkg(32'h2004, 4'b0010);
        // 同一拍: 写第三个, 同时读第一个
        push_inst = 32'h2008; push_predec = 4'b0011;
        push = 1; pop = 1;
        @(posedge clk); #1;
        push = 0; pop = 0;
        // 读指针已前进, 现在队头应是第二个包裹
        chk("same-cycle: head now 0x2004", pop_inst  === 32'h2004);
        chk("same-cycle: head predec 0010", pop_predec === 4'b0010);
        // 再读出第二个, 第三个应紧随其后, 配对不乱
        pop = 1; @(posedge clk); #1; pop = 0;
        chk("same-cycle: next 0x2008", pop_inst  === 32'h2008);
        chk("same-cycle: next predec 0011", pop_predec === 4'b0011);

        $display("==== Result: %0d errors ====", errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        $finish;
    end
endmodule
