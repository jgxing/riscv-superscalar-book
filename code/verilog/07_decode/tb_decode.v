// ============================================================
// 第 7 章 译码器自测
// 覆盖: ADDI 直译 / ADD 直译 / SD 拆分 / LUI+ADDI 融合 / 融合条件不成立
// uop 字段布局: [47:44]op [43:39]rd [38:34]rs1 [33:29]rs2 [28:0]imm
// ============================================================
`timescale 1ns/1ps

module tb_decode;
    reg         prev_valid;
    reg  [31:0] prev_inst;
    reg  [31:0] inst;
    wire [47:0] uop1, uop2;
    wire        uop2_valid, fused;

    decoder dut (
        .prev_valid(prev_valid), .prev_inst(prev_inst), .inst(inst),
        .uop1(uop1), .uop2(uop2), .uop2_valid(uop2_valid), .fused(fused)
    );

    integer errors = 0;

    // 从 uop 里取字段的辅助函数
    function [3:0]  get_op;  input [47:0] u; begin get_op  = u[47:44]; end endfunction
    function [4:0]  get_rd;  input [47:0] u; begin get_rd  = u[43:39]; end endfunction
    function [4:0]  get_r1;  input [47:0] u; begin get_r1  = u[38:34]; end endfunction
    function [4:0]  get_r2;  input [47:0] u; begin get_r2  = u[33:29]; end endfunction
    function [28:0] get_imm; input [47:0] u; begin get_imm = u[28:0];  end endfunction

    task chk;
        input [1023:0] msg;
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

    // 操作码常量(与 decoder.v 一致)
    localparam [3:0] OP_ADD = 4'd1;
    localparam [3:0] OP_SUB = 4'd2;
    localparam [3:0] OP_ST  = 4'd4;
    localparam [3:0] OP_LUI = 4'd5;

    initial begin
        // ---- T1 ADDI x5, x6, 0x2A 直译 ----
        // imm=0x2A, rs1=6, funct3=000, rd=5, opcode=0010011
        prev_valid = 0; prev_inst = 0;
        inst = {12'h02A, 5'd6, 3'b000, 5'd5, 7'b0010011};
        #1;
        $display("-- T1 ADDI direct --");
        chk("ADDI op=ADD",       get_op(uop1)  === OP_ADD);
        chk("ADDI rd=5",         get_rd(uop1)  === 5'd5);
        chk("ADDI rs1=6",        get_r1(uop1)  === 5'd6);
        chk("ADDI imm=0x2A",     get_imm(uop1) === 29'h2A);
        chk("ADDI no second uop", uop2_valid === 1'b0);
        chk("ADDI not fused",    fused === 1'b0);

        // ---- T2 SUB x7, x8, x9 直译 ----
        // funct7=0100000, rs2=9, rs1=8, funct3=000, rd=7, opcode=0110011
        inst = {7'b0100000, 5'd9, 5'd8, 3'b000, 5'd7, 7'b0110011};
        #1;
        $display("-- T2 SUB direct --");
        chk("SUB op=SUB",        get_op(uop1)  === OP_SUB);
        chk("SUB rd=7",          get_rd(uop1)  === 5'd7);
        chk("SUB rs1=8",         get_r1(uop1)  === 5'd8);
        chk("SUB rs2=9",         get_r2(uop1)  === 5'd9);

        // ---- T3 LUI x10, 0x1 直译(立即数左移12位 = 0x1000) ----
        // imm[31:12]=0x00001, rd=10, opcode=0110111
        inst = {20'h00001, 5'd10, 7'b0110111};
        #1;
        $display("-- T3 LUI direct --");
        chk("LUI op=LUI",        get_op(uop1)  === OP_LUI);
        chk("LUI rd=10",         get_rd(uop1)  === 5'd10);
        chk("LUI imm=0x1000",    get_imm(uop1) === 29'h1000);

        // ---- T4 SD x13, 0(x14) 拆成两条 ----
        // imm[11:5]=0, rs2=13, rs1=14, funct3=011, imm[4:0]=0, opcode=0100011
        inst = {7'b0000000, 5'd13, 5'd14, 3'b011, 5'd0, 7'b0100011};
        #1;
        $display("-- T4 SD split --");
        chk("SD first op=ST",       get_op(uop1)   === OP_ST);
        chk("SD first rs1=14",      get_r1(uop1)   === 5'd14);
        chk("SD first rs2=13",      get_r2(uop1)   === 5'd13);
        chk("SD first imm=0",       get_imm(uop1)  === 29'd0);
        chk("SD second valid",      uop2_valid === 1'b1);
        chk("SD second op=ST",      get_op(uop2)   === OP_ST);
        chk("SD second imm=4",      get_imm(uop2)  === 29'd4);
        chk("SD not fused",         fused === 1'b0);

        // ---- T5 LUI + ADDI 融合 ----
        // prev = LUI x10,0x1 (立即数 0x1)
        // curr = ADDI x10,x10,0x20  →  合成 ADD x10, x0, 0x1020
        prev_valid = 1;
        prev_inst = {20'h00001, 5'd10, 7'b0110111};
        inst      = {12'h020, 5'd10, 3'b000, 5'd10, 7'b0010011};
        #1;
        $display("-- T5 LUI+ADDI fusion --");
        chk("fuse fused=1",      fused === 1'b1);
        chk("fuse op=ADD",       get_op(uop1)  === OP_ADD);
        chk("fuse rd=10",        get_rd(uop1)  === 5'd10);
        chk("fuse imm=0x1020",   get_imm(uop1) === 29'h1020);
        chk("fuse no second uop", uop2_valid === 1'b0);

        // ---- T6 融合条件不成立(rd 不同) ----
        // prev = LUI x10,0x1; curr = ADDI x11,x10,0x20 → 目的寄存器不同, 不融合
        prev_inst = {20'h00001, 5'd10, 7'b0110111};
        inst      = {12'h020, 5'd10, 3'b000, 5'd11, 7'b0010011};
        #1;
        $display("-- T6 fusion condition fails --");
        chk("no-fuse fused=0",   fused === 1'b0);
        chk("no-fuse op=ADD",    get_op(uop1)  === OP_ADD);
        chk("no-fuse rd=11",     get_rd(uop1)  === 5'd11);
        chk("no-fuse imm=0x20",  get_imm(uop1) === 29'h20);

        $display("==== Result: %0d errors ====", errors);
        if (errors == 0)
            $display("ALL TESTS PASSED");
        $finish;
    end
endmodule
