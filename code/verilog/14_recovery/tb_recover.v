`timescale 1ns/1ps
module tb_recover;
    reg clk, rst_n;

    reg                 br_mispred_i;
    reg  [31:0]         br_pc_i;
    reg  [7:0]          br_seq_i;
    reg  [1:0]          br_cp_i;

    reg                 exc_i;
    reg  [31:0]         exc_pc_i;
    reg  [7:0]          exc_seq_i;
    reg  [1:0]          exc_cp_i;

    reg                 save_en_i;
    reg  [191:0]        save_rat_i;
    reg  [5:0]          save_fl_head_i;
    reg  [5:0]          save_fl_tail_i;
    reg  [7:0]          save_seq_i;
    wire [1:0]          save_id_o;
    wire                save_full_o;

    reg                 release_en_i;
    reg  [1:0]          release_id_i;

    reg  [63:0]         uop_seq_i;

    wire                front_redirect_o;
    wire [31:0]         front_pc_o;
    wire                back_flush_o;
    wire [7:0]          kill_from_o;
    wire                restore_en_o;
    wire [191:0]        restore_rat_o;
    wire [5:0]          restore_fl_head_o;
    wire [5:0]          restore_fl_tail_o;
    wire [7:0]          kill_mask_o;

    recover uut (
        .clk(clk), .rst_n(rst_n),
        .br_mispred_i(br_mispred_i), .br_pc_i(br_pc_i),
        .br_seq_i(br_seq_i), .br_cp_i(br_cp_i),
        .exc_i(exc_i), .exc_pc_i(exc_pc_i),
        .exc_seq_i(exc_seq_i), .exc_cp_i(exc_cp_i),
        .save_en_i(save_en_i), .save_rat_i(save_rat_i),
        .save_fl_head_i(save_fl_head_i), .save_fl_tail_i(save_fl_tail_i),
        .save_seq_i(save_seq_i),
        .save_id_o(save_id_o), .save_full_o(save_full_o),
        .release_en_i(release_en_i), .release_id_i(release_id_i),
        .uop_seq_i(uop_seq_i),
        .front_redirect_o(front_redirect_o), .front_pc_o(front_pc_o),
        .back_flush_o(back_flush_o), .kill_from_o(kill_from_o),
        .restore_en_o(restore_en_o), .restore_rat_o(restore_rat_o),
        .restore_fl_head_o(restore_fl_head_o), .restore_fl_tail_o(restore_fl_tail_o),
        .kill_mask_o(kill_mask_o)
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

    integer i;
    reg [191:0] snap0, snap1;
    initial begin
        clk = 0; rst_n = 1;
        br_mispred_i = 0; br_pc_i = 0; br_seq_i = 0; br_cp_i = 0;
        exc_i = 0; exc_pc_i = 0; exc_seq_i = 0; exc_cp_i = 0;
        save_en_i = 0; save_rat_i = 0; save_fl_head_i = 0; save_fl_tail_i = 0;
        save_seq_i = 0; release_en_i = 0; release_id_i = 0; uop_seq_i = 0;

        // 复位
        #1 rst_n = 1'b0;
        tick;
        #1 rst_n = 1'b1;
        tick;
        chk(!save_full_o, "reset: checkpoint buffer not full");

        // 构造两份可辨认的 RAT 快照
        snap0 = {32{6'd10}};
        snap1 = {32{6'd20}};

        // 拍第一份快照。save_id_o 是组合信号，要在时钟沿之前读
        save_en_i = 1'b1;
        save_rat_i = snap0;
        save_fl_head_i = 6'd8;
        save_fl_tail_i = 6'd20;
        save_seq_i = 8'd5;
        #1;
        chk(save_id_o == 2'd0, "first save gets slot 0");
        tick;
        save_en_i = 1'b0;

        // 拍第二份快照
        save_en_i = 1'b1;
        save_rat_i = snap1;
        save_fl_head_i = 6'd12;
        save_fl_tail_i = 6'd24;
        save_seq_i = 8'd9;
        #1;
        chk(save_id_o == 2'd1, "second save gets slot 1");
        tick;
        save_en_i = 1'b0;

        // 分支预测错误：正确目标 0x300，分支序号 9，用槽 1 的快照
        br_cp_i     = 2'd1;
        br_pc_i     = 32'h300;
        br_seq_i    = 8'd9;
        // 向量最右端是 uop0，依次到 uop7；序号 6..13
        uop_seq_i   = {8'd13, 8'd12, 8'd11, 8'd10, 8'd9, 8'd8, 8'd7, 8'd6};
        br_mispred_i = 1'b1;
        #1;
        chk(front_redirect_o && front_pc_o == 32'h300,
            "branch mispredict: redirect to correct PC");
        chk(back_flush_o && kill_from_o == 8'd9,
            "branch mispredict: back flush from seq 9");
        chk(restore_en_o, "branch mispredict: restore asserted");
        chk(restore_rat_o == snap1, "branch mispredict: restore RAT from slot 1");
        chk(restore_fl_head_o == 6'd12 && restore_fl_tail_o == 6'd24,
            "branch mispredict: restore free-list pointers from slot 1");
        // 序号 6/7/8 比分支老，保留；出错的 9 本身及以后都要冲掉
        chk(kill_mask_o == 8'b11111000, "kill mask: older kept, seq>=9 killed");

        // 换成槽 0 再读一次，验证按编号选择
        br_cp_i = 2'd0;
        #1;
        chk(restore_rat_o == snap0, "redirect with slot 0 restores snapshot 0");
        chk(restore_fl_head_o == 6'd8 && restore_fl_tail_o == 6'd20,
            "redirect with slot 0 restores its free-list pointers");
        br_cp_i = 2'd1;
        br_mispred_i = 1'b0;
        #1;
        chk(!front_redirect_o && !back_flush_o && !restore_en_o,
            "no redirect: all flush signals low");
        chk(kill_mask_o == 8'b00000000, "no redirect: kill mask cleared");

        // 异常与分支同时来，异常优先
        br_mispred_i = 1'b1;
        br_pc_i      = 32'h300;
        br_seq_i     = 8'd9;
        br_cp_i      = 2'd1;
        exc_i        = 1'b1;
        exc_pc_i     = 32'h800;
        exc_seq_i    = 8'd3;
        exc_cp_i     = 2'd0;
        #1;
        chk(front_pc_o == 32'h800, "exception wins over branch mispredict");
        chk(kill_from_o == 8'd3 && restore_rat_o == snap0,
            "exception uses its own seq and checkpoint");
        exc_i = 0;
        br_mispred_i = 0;

        // 释放槽 1，再存一份应复用它
        release_en_i = 1'b1;
        release_id_i = 2'd1;
        tick;
        release_en_i = 1'b0;
        save_en_i = 1'b1;
        save_rat_i = {32{6'd33}};
        save_fl_head_i = 6'd1;
        save_fl_tail_i = 6'd2;
        save_seq_i = 8'd20;
        #1;
        chk(save_id_o == 2'd1, "released slot reused by next save");
        tick;
        save_en_i = 1'b0;

        // 存满四个槽
        for (i = 0; i < 4; i = i + 1) begin
            save_en_i = 1'b1;
            save_rat_i = {32{6'd1}} + i;
            save_fl_head_i = 6'd0;
            save_fl_tail_i = 6'd0;
            save_seq_i = 8'd30 + i[7:0];
            tick;
        end
        save_en_i = 1'b0;
        #1;
        chk(save_full_o, "four checkpoints full");

        $display("----------------------------------------");
        if (err == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", err);
        $display("----------------------------------------");
        $finish;
    end
endmodule
