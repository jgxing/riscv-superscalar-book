`timescale 1ns/1ps
module tb_execute;
    reg                 clk;
    reg                 rst_n;
    reg                 valid_i;
    reg  [3:0]          op_i;
    reg  [5:0]          ps1_i, ps2_i, dest_i;
    reg  [31:0]         rdata1_i, rdata2_i;
    reg  [1:0]          byp_en_i;
    reg  [5:0]          byp_dest_i0, byp_dest_i1;
    reg  [31:0]         byp_data_i0, byp_data_i1;

    wire [31:0]         result_o;
    wire [5:0]          dest_o;
    wire                out_valid_o;
    wire [31:0]         src1_dbg, src2_dbg;

    exec_unit uut (
        .clk(clk), .rst_n(rst_n),
        .valid_i(valid_i), .op_i(op_i),
        .ps1_i(ps1_i), .ps2_i(ps2_i), .dest_i(dest_i),
        .rdata1_i(rdata1_i), .rdata2_i(rdata2_i),
        .byp_en_i(byp_en_i),
        .byp_dest_i0(byp_dest_i0), .byp_data_i0(byp_data_i0),
        .byp_dest_i1(byp_dest_i1), .byp_data_i1(byp_data_i1),
        .result_o(result_o), .dest_o(dest_o), .out_valid_o(out_valid_o)
    );

    // 单独再看一眼旁路选择器的输出，便于对照
    bypass u_byp_dbg (
        .ps1_i(ps1_i), .ps2_i(ps2_i),
        .rdata1_i(rdata1_i), .rdata2_i(rdata2_i),
        .byp_en_i(byp_en_i),
        .byp_dest_i0(byp_dest_i0), .byp_data_i0(byp_data_i0),
        .byp_dest_i1(byp_dest_i1), .byp_data_i1(byp_data_i1),
        .src1_o(src1_dbg), .src2_o(src2_dbg)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer total = 0, pass = 0;

    task chk;
        input [1023:0] m;
        input cond;
        begin
            total = total + 1;
            if (cond) begin
                pass = pass + 1;
                $display("PASS %0d: %0s", total, m);
            end else begin
                $display("FAIL %0d: %0s", total, m);
            end
        end
    endtask

    task drive;
        input v;
        input [3:0] op;
        input [5:0] s1, s2, d;
        input [31:0] rd1, rd2;
        input [1:0] ben;
        input [5:0] bd0;
        input [31:0] bv0;
        input [5:0] bd1;
        input [31:0] bv1;
        begin
            @(negedge clk);
            valid_i = v;     op_i    = op;
            ps1_i   = s1;    ps2_i   = s2;    dest_i = d;
            rdata1_i = rd1;  rdata2_i = rd2;
            byp_en_i = ben;
            byp_dest_i0 = bd0; byp_data_i0 = bv0;
            byp_dest_i1 = bd1; byp_data_i1 = bv1;
        end
    endtask

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        rst_n = 0;
        valid_i = 1'b0; op_i = 4'd0;
        ps1_i = 6'd0; ps2_i = 6'd0; dest_i = 6'd0;
        rdata1_i = 32'd0; rdata2_i = 32'd0;
        byp_en_i = 2'b0;
        byp_dest_i0 = 6'd0; byp_data_i0 = 32'd0;
        byp_dest_i1 = 6'd0; byp_data_i1 = 32'd0;

        repeat (2) @(posedge clk);
        #1;
        chk("reset: output invalid", out_valid_o === 1'b0);
        rst_n = 1;

        // 源1 命中旁路：寄存器里是旧值 0x11，旁路送来 0x2a
        drive(1'b1, 4'd0, 6'd10, 6'd2, 6'd10,
              32'h11, 32'h05, 2'b01, 6'd10, 32'h2a, 6'd0, 32'h0);
        tick;
        chk("bypass hit on src1 picks 0x2a", src1_dbg === 32'h2a);
        chk("bypass hit on src1: 0x2a + 5 = 0x2f",
            (result_o === 32'h2f) && (dest_o === 6'd10) && out_valid_o);

        // 目的号对不上，旁路不生效，用寄存器值 0x11
        drive(1'b1, 4'd0, 6'd10, 6'd2, 6'd10,
              32'h11, 32'h05, 2'b01, 6'd11, 32'h2a, 6'd0, 32'h0);
        tick;
        chk("dest mismatch: fall back to reg value",
            (src1_dbg === 32'h11) && (result_o === 32'h16));

        // 两路旁路都无效时，同样用寄存器值
        drive(1'b1, 4'd0, 6'd10, 6'd2, 6'd10,
              32'h11, 32'h05, 2'b00, 6'd10, 32'h2a, 6'd10, 32'h30);
        tick;
        chk("bypass disabled: fall back to reg value",
            (src1_dbg === 32'h11) && (result_o === 32'h16));

        // 源2 命中旁路
        drive(1'b1, 4'd0, 6'd10, 6'd2, 6'd10,
              32'h11, 32'h05, 2'b01, 6'd2, 32'h08, 6'd0, 32'h0);
        tick;
        chk("bypass hit on src2 picks 0x08", src2_dbg === 32'h08);
        chk("bypass hit on src2: 0x11 + 8 = 0x19",
            (result_o === 32'h19) && (dest_o === 6'd10));

        // 两路结果分别命中两个源
        drive(1'b1, 4'd0, 6'd10, 6'd2, 6'd10,
              32'h11, 32'h05, 2'b11, 6'd10, 32'h2a, 6'd2, 32'h08);
        tick;
        chk("two bypass hits: 0x2a + 8 = 0x32",
            (src1_dbg === 32'h2a) && (src2_dbg === 32'h08) && (result_o === 32'h32));

        // 两路结果目的号相同，第1路更新，优先
        drive(1'b1, 4'd0, 6'd10, 6'd2, 6'd10,
              32'h11, 32'h05, 2'b11, 6'd10, 32'h2a, 6'd10, 32'h30);
        tick;
        chk("newer bypass wins: 0x30 + 5 = 0x35",
            (src1_dbg === 32'h30) && (result_o === 32'h35));

        // 只有第1路有效
        drive(1'b1, 4'd0, 6'd10, 6'd2, 6'd10,
              32'h11, 32'h05, 2'b10, 6'd10, 32'h2a, 6'd10, 32'h30);
        tick;
        chk("only bypass 1 enabled: 0x30 + 5 = 0x35",
            (src1_dbg === 32'h30) && (result_o === 32'h35));

        // 减法、逻辑运算同样走旁路后的操作数
        drive(1'b1, 4'd1, 6'd10, 6'd2, 6'd11,
              32'h11, 32'h05, 2'b01, 6'd10, 32'h2a, 6'd0, 32'h0);
        tick;
        chk("SUB: 0x2a - 5 = 0x25", result_o === 32'h25);

        drive(1'b1, 4'd2, 6'd10, 6'd2, 6'd12,
              32'h11, 32'h0f, 2'b01, 6'd10, 32'h2a, 6'd0, 32'h0);
        tick;
        chk("AND: 0x2a & 0x0f = 0x0a", result_o === 32'h0a);

        drive(1'b1, 4'd3, 6'd10, 6'd2, 6'd13,
              32'h11, 32'h0f, 2'b01, 6'd10, 32'h2a, 6'd0, 32'h0);
        tick;
        chk("OR: 0x2a | 0x0f = 0x2f", result_o === 32'h2f);

        drive(1'b1, 4'd4, 6'd10, 6'd2, 6'd14,
              32'h11, 32'h0f, 2'b01, 6'd10, 32'h2a, 6'd0, 32'h0);
        tick;
        chk("XOR: 0x2a ^ 0x0f = 0x25", result_o === 32'h25);

        // 不命中旁路时的左移与比较
        drive(1'b1, 4'd5, 6'd7, 6'd2, 6'd15,
              32'h01, 32'h04, 2'b00, 6'd0, 32'h0, 6'd0, 32'h0);
        tick;
        chk("SLL: 1 << 4 = 0x10", result_o === 32'h10);

        drive(1'b1, 4'd6, 6'd7, 6'd2, 6'd16,
              32'h01, 32'h02, 2'b00, 6'd0, 32'h0, 6'd0, 32'h0);
        tick;
        chk("SLT: 1 < 2 = 1", result_o === 32'd1);

        // 目的号透传与空泡
        drive(1'b1, 4'd0, 6'd10, 6'd2, 6'd42,
              32'h11, 32'h05, 2'b00, 6'd0, 32'h0, 6'd0, 32'h0);
        tick;
        chk("dest passthrough: P42", dest_o === 6'd42);

        drive(1'b0, 4'd0, 6'd10, 6'd2, 6'd43,
              32'h11, 32'h05, 2'b00, 6'd0, 32'h0, 6'd0, 32'h0);
        tick;
        chk("bubble: output invalid", out_valid_o === 1'b0);

        $display("---- %0d / %0d passed ----", pass, total);
        if (pass == total) $display("ALL TESTS PASSED");
        else               $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
