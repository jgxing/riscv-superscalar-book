// ==============================================================
// Testbench for BHT and BTB —— 教材第5章
// 覆盖：2 位计数器加一/减一/两端饱和、复位默认值、方向预测；
//       BTB 复位、写入后命中、标签不匹配不误报命中。
// 输出用英文，避免 Windows 终端的中文编码问题。
// ==============================================================
`timescale 1ns/1ps
module tb_branch;

    reg         clk = 0;
    reg         rst_n = 0;
    integer     err_cnt = 0;
    integer     pass_cnt = 0;

    // ---------- BHT 信号 ----------
    reg  [31:0] bht_q_pc;
    wire        bht_predict;
    wire [1:0]  bht_cnt;
    reg         bht_upd_en;
    reg  [31:0] bht_upd_pc;
    reg         bht_taken;

    bht u_bht (
        .clk      (clk),
        .rst_n    (rst_n),
        .pc       (bht_q_pc),
        .predict  (bht_predict),
        .cnt_out  (bht_cnt),
        .update_en(bht_upd_en),
        .update_pc(bht_upd_pc),
        .taken    (bht_taken)
    );

    // ---------- BTB 信号 ----------
    reg  [31:0] btb_q_pc;
    wire        btb_hit;
    wire [31:0] btb_target;
    reg         btb_upd_en;
    reg  [31:0] btb_upd_pc;
    reg  [31:0] btb_upd_target;

    btb u_btb (
        .clk         (clk),
        .rst_n       (rst_n),
        .pc          (btb_q_pc),
        .hit         (btb_hit),
        .target      (btb_target),
        .update_en   (btb_upd_en),
        .update_pc   (btb_upd_pc),
        .update_target(btb_upd_target)
    );

    always #5 clk = ~clk;

    // ---------- 辅助任务 ----------
    task chk;
        input [1023:0] msg;
        input cond;
        begin
            if (cond) begin
                $display("PASS: %0s", msg);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL: %0s", msg);
                err_cnt = err_cnt + 1;
            end
        end
    endtask

    task bht_update;
        input [31:0] upc;
        input tk;
        begin
            bht_upd_en = 1'b1;
            bht_upd_pc = upc;
            bht_taken  = tk;
            @(posedge clk);
            #1;
            bht_upd_en = 1'b0;
        end
    endtask

    task btb_update;
        input [31:0] upc;
        input [31:0] utarget;
        begin
            btb_upd_en    = 1'b1;
            btb_upd_pc    = upc;
            btb_upd_target= utarget;
            @(posedge clk);
            #1;
            btb_upd_en    = 1'b0;
        end
    endtask

    integer k;

    initial begin
        // 初始
        bht_q_pc = 32'h1000; bht_upd_en = 0; bht_upd_pc = 0; bht_taken = 0;
        btb_q_pc = 32'h1000; btb_upd_en = 0; btb_upd_pc = 0; btb_upd_target = 0;

        #20;
        rst_n = 1'b1;
        #10;

        $display("==== Chapter 5 BHT / BTB tests ====");

        // ---------- T1 BHT 复位默认值 ----------
        $display("-- T1 BHT reset default --");
        chk("reset: cnt = 01 (weak not taken)", bht_cnt === 2'b01);
        chk("reset: predict = 0", bht_predict === 1'b0);

        // ---------- T2 taken 加一到饱和 ----------
        $display("-- T2 BHT count up and saturate --");
        bht_update(32'h1000, 1'b1);   // 01 -> 10
        chk("after 1st taken: cnt = 10", bht_cnt === 2'b10);
        chk("after 1st taken: predict = 1 (top bit of 10 is 1)", bht_predict === 1'b1);
        bht_update(32'h1000, 1'b1);   // 10 -> 11
        chk("after 2nd taken: cnt = 11", bht_cnt === 2'b11);
        chk("after 2nd taken: predict = 1", bht_predict === 1'b1);
        for (k = 0; k < 3; k = k + 1)
            bht_update(32'h1000, 1'b1);   // 停在 11
        chk("saturate high: cnt stays 11", bht_cnt === 2'b11);

        // ---------- T3 not taken 减一到饱和 ----------
        $display("-- T3 BHT count down and saturate --");
        bht_update(32'h1000, 1'b0);   // 11 -> 10
        chk("after 1st not-taken: cnt = 10", bht_cnt === 2'b10);
        bht_update(32'h1000, 1'b0);   // 10 -> 01
        chk("after 2nd not-taken: cnt = 01", bht_cnt === 2'b01);
        chk("after 2nd not-taken: predict = 0", bht_predict === 1'b0);
        bht_update(32'h1000, 1'b0);   // 01 -> 00
        chk("after 3rd not-taken: cnt = 00", bht_cnt === 2'b00);
        for (k = 0; k < 3; k = k + 1)
            bht_update(32'h1000, 1'b0);   // 停在 00
        chk("saturate low: cnt stays 00", bht_cnt === 2'b00);

        // ---------- T4 BTB 复位 ----------
        $display("-- T4 BTB reset --");
        chk("reset: btb hit = 0", btb_hit === 1'b0);

        // ---------- T5 BTB 写入与命中 ----------
        $display("-- T5 BTB write and hit --");
        btb_update(32'h0000_1000, 32'h0000_2000);
        btb_q_pc = 32'h0000_1000;
        #1;
        chk("same PC: hit = 1", btb_hit === 1'b1);
        chk("same PC: target = 0x2000", btb_target === 32'h0000_2000);

        // 同索引（低 6 位相同）但高位 tag 不同 -> 不应命中
        btb_q_pc = 32'h0400_1000;
        #1;
        chk("different tag: hit = 0 (no false hit)", btb_hit === 1'b0);

        // ---------- 汇总 ----------
        $display("==== Result: %0d passed, %0d errors ====", pass_cnt, err_cnt);
        if (err_cnt == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
