// 附录 B 五个模板模块的自测程序
`timescale 1ns/1ps
module tb_appendix_b;
    reg clk, rst_n;
    integer pass_cnt, fail_cnt;

    // ---------- FIFO 信号 ----------
    reg  f_push, f_pop;
    reg  [7:0] f_pd;
    wire [7:0] f_out;
    wire f_full, f_empty;
    fifo #(.DEPTH(4), .DATA_W(8)) u_fifo (
        .clk(clk), .rst_n(rst_n),
        .push_i(f_push), .push_data_i(f_pd), .pop_i(f_pop),
        .pop_data_o(f_out), .full_o(f_full), .empty_o(f_empty)
    );

    // ---------- CAM 信号 ----------
    reg  [5:0] c_key;
    reg  [47:0] c_table;   // 8 项 × 6 位
    reg  [7:0] c_valid;
    wire [7:0] c_match;
    wire c_hit;
    wire [2:0] c_idx;
    cam #(.N(8), .KEY_W(6)) u_cam (
        .key_i(c_key), .table_i(c_table), .valid_i(c_valid),
        .match_o(c_match), .hit_o(c_hit), .index_o(c_idx)
    );

    // ---------- 优先编码器信号 ----------
    reg  [7:0] pe_req;
    wire pe_valid;
    wire [2:0] pe_code;
    priority_encoder #(.N(8)) u_pe (
        .req_i(pe_req), .valid_o(pe_valid), .code_o(pe_code)
    );

    // ---------- 仲裁器信号 ----------
    reg  [3:0] a_req;
    reg  [31:0] a_age;    // 4 项 × 8 位
    reg  [1:0] a_limit;
    wire [3:0] a_g0, a_g1, a_g;
    arbiter #(.N(4), .AGE_W(8)) u_arb (
        .req_i(a_req), .age_i(a_age), .limit_i(a_limit),
        .grant0_o(a_g0), .grant1_o(a_g1), .grant_o(a_g)
    );

    // ---------- crossbar 信号 ----------
    reg  [3:0] x_req;
    reg  [7:0] x_dst;     // 4 路 × 2 位
    reg  [127:0] x_data;  // 4 路 × 32 位
    wire [127:0] x_out;
    wire [3:0] x_valid;
    crossbar #(.N(4), .DATA_W(32)) u_xbar (
        .req_i(x_req), .dst_i(x_dst), .data_i(x_data),
        .data_o(x_out), .valid_o(x_valid)
    );

    task chk;
        input cond;
        input [1023:0] msg;
        begin
            if (cond) begin
                pass_cnt = pass_cnt + 1;
                $display("PASS %0d  %0s", pass_cnt, msg);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("FAIL %0d  %0s", fail_cnt, msg);
            end
        end
    endtask

    task tick;
        begin
            #5 clk = 1'b0;
            #5 clk = 1'b1;
        end
    endtask

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        clk = 1'b0;
        // 明确给出复位下降沿，避免 x->0 不触发 negedge
        rst_n = 1'b1;
        #2 rst_n = 1'b0;
        #5 rst_n = 1'b1;
        #1;

        // ==================== FIFO ====================
        f_push = 0; f_pop = 0; f_pd = 0;
        #1;
        chk(f_empty && !f_full, "fifo: empty after reset");

        // 写满四个。每次改数据后留一拍建立时间再打时钟
        f_push = 1; f_pd = 8'd11; #1; tick; #1;
        f_pd = 8'd22; #1; tick; #1;
        f_pd = 8'd33; #1; tick; #1;
        f_pd = 8'd44; #1; tick; #1;
        f_push = 0;
        #1;
        chk(f_full && !f_empty, "fifo: full after four pushes");

        // 满时拒写：状态不变
        f_push = 1; f_pd = 8'd99; #1; tick; #1;
        f_push = 0;
        #1;
        chk(f_full, "fifo: still full when push rejected");

        // 读一个
        f_pop = 1;
        #1; tick; #1;
        f_pop = 0;
        #1;
        chk(f_out == 8'd11 && !f_full, "fifo: first pop gives 11, not full");

        // 读写同拍：读出一个的同时写入新数据
        f_pop = 1; f_push = 1; f_pd = 8'd55;
        #1; tick; #1;
        f_pop = 0; f_push = 0;
        #1;
        chk(f_out == 8'd22, "fifo: pop 22 while pushing");
        f_pop = 1; #1; tick; #1; f_pop = 0; #1;
        chk(f_out == 8'd33, "fifo: pop 33");
        f_pop = 1; #1; tick; #1; f_pop = 0; #1;
        chk(f_out == 8'd44, "fifo: pop 44");
        f_pop = 1; #1; tick; #1; f_pop = 0; #1;
        chk(f_out == 8'd55 && f_empty, "fifo: pop 55, empty again");

        // ==================== CAM ====================
        // 表项 0=10, 1=21, 2=32, 3=43, 4..7 无效
        c_table = {6'd0, 6'd0, 6'd0, 6'd0, 6'd43, 6'd32, 6'd21, 6'd10};
        c_valid = 8'b00001111;
        c_key = 6'd32;
        #1;
        chk(c_hit && c_idx == 3'd2, "cam: key 32 hits index 2");
        chk(c_match == 8'b00000100, "cam: match bits point to index 2");
        c_key = 6'd43;
        #1;
        chk(c_hit && c_idx == 3'd3, "cam: key 43 hits index 3");
        c_key = 6'd21;
        #1;
        chk(c_hit && c_idx == 3'd1, "cam: key 21 hits index 1");
        c_key = 6'd63;
        #1;
        chk(!c_hit && c_match == 8'b0, "cam: key 63 misses");
        // 无效表项即使内容相等也不算命中
        c_valid = 8'b11111111;
        c_table[47:42] = 6'd32;   // 表项 7 也写成 32
        c_key = 6'd32;
        #1;
        chk(c_hit && c_idx == 3'd2, "cam: two matches, smallest index wins");

        // ==================== 优先编码器 ====================
        pe_req = 8'b0;
        #1;
        chk(!pe_valid && pe_code == 3'd0, "encoder: no request");
        pe_req = 8'b00000100;
        #1;
        chk(pe_valid && pe_code == 3'd2, "encoder: single request at bit2");
        pe_req = 8'b10110000;
        #1;
        chk(pe_valid && pe_code == 3'd4, "encoder: lowest of multiple is bit4");
        pe_req = 8'b10000000;
        #1;
        chk(pe_valid && pe_code == 3'd7, "encoder: highest bit alone");

        // ==================== 仲裁器 ====================
        // 打包最右端是第 0 项：age[0]=9, age[1]=3, age[2]=7, age[3]=5
        // 最老是编号 1（3），其次编号 3（5）
        a_age = {8'd5, 8'd7, 8'd3, 8'd9};
        a_req = 4'b1111;
        a_limit = 2'd2;
        #1;
        chk(a_g0 == 4'b0010 && a_g1 == 4'b1000,
            "arbiter: two tickets by age, not index");
        chk(a_g == 4'b1010, "arbiter: grant union");
        a_limit = 2'd1;
        #1;
        chk(a_g0 == 4'b0010 && a_g1 == 4'b0000,
            "arbiter: limit one suppresses second ticket");
        a_limit = 2'd0;
        #1;
        chk(a_g == 4'b0000, "arbiter: limit zero grants nothing");
        a_limit = 2'd2;
        a_req = 4'b0100;
        #1;
        chk(a_g0 == 4'b0100 && a_g1 == 4'b0000,
            "arbiter: single request gets first ticket");

        // ==================== crossbar ====================
        // 打包最右端是第 0 路。第0路->输出2, 第1路->输出0,
        // 第2路->输出2(与第0路冲突), 第3路无请求
        x_req = 4'b0111;
        x_dst = {2'd0, 2'd2, 2'd0, 2'd2};
        x_data = {32'd400, 32'd300, 32'd200, 32'd100};
        #1;
        chk(x_valid == 4'b0101, "crossbar: outputs 0 and 2 valid");
        chk(x_out[95:64] == 32'd100,
            "crossbar: output 2 takes input0, smaller index wins");
        chk(x_out[31:0] == 32'd200,
            "crossbar: output 0 takes input1");
        chk(x_out[127:96] == 32'd0 && x_out[63:32] == 32'd0,
            "crossbar: undriven outputs are zero");
        x_req = 4'b0000;
        #1;
        chk(x_valid == 4'b0000, "crossbar: no request, no valid output");

        $display("----- %0d passed, %0d failed -----", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
