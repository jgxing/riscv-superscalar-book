// ============================================================
// 第 7 章 简化译码器
// 把几条代表性 RISC-V 指令翻译成后端用的 uop(48 位打包总线)
// 体现三个思想: 直译 / 拆分 / 融合
// 纯组合逻辑, 无时钟——融合要的"上一条指令"由外部寄存器提供
// ============================================================

module decoder (
    input         prev_valid,
    input  [31:0] prev_inst,
    input  [31:0] inst,
    output [47:0] uop1,
    output [47:0] uop2,
    output        uop2_valid,
    output        fused
);
    // ---------- uop 字段布局(共 48 位) ----------
    localparam OP_HI = 47, OP_LO = 44;    // 4 位操作码
    localparam RD_HI = 43, RD_LO = 39;    // 5 位目的寄存器
    localparam R1_HI = 38, R1_LO = 34;    // 5 位源寄存器 1
    localparam R2_HI = 33, R2_LO = 29;    // 5 位源寄存器 2
    localparam IM_HI = 28, IM_LO = 0;     // 29 位立即数

    // ---------- 操作码 ----------
    localparam [3:0] OP_NOP = 4'd0;
    localparam [3:0] OP_ADD = 4'd1;
    localparam [3:0] OP_SUB = 4'd2;
    localparam [3:0] OP_LD  = 4'd3;
    localparam [3:0] OP_ST  = 4'd4;
    localparam [3:0] OP_LUI = 4'd5;

    // ---------- 打包函数 ----------
    // 每次拼 uop 都移位太啰嗦, 写个函数统一处理
    function [47:0] pack_uop;
        input [3:0]  op;
        input [4:0]  rd, rs1, rs2;
        input [28:0] imm;
        begin
            pack_uop = {op, rd, rs1, rs2, imm};
        end
    endfunction

    reg [47:0] d_uop1, d_uop2;
    reg        d_uop2_valid, d_fused;

    always @* begin
        // 默认: 空操作, 无第二条, 未融合
        d_uop1       = pack_uop(OP_NOP, 5'd0, 5'd0, 5'd0, 29'd0);
        d_uop2       = {48{1'b0}};
        d_uop2_valid = 1'b0;
        d_fused      = 1'b0;

        case (inst[6:0])
            // ---- 直译: ADDI ----
            7'b0010011: begin
                d_uop1 = pack_uop(OP_ADD, inst[11:7], inst[19:15], 5'd0,
                                  {17'd0, inst[31:20]});
            end
            // ---- 直译: ADD / SUB ----
            7'b0110011: begin
                if (inst[30] == 1'b0)
                    d_uop1 = pack_uop(OP_ADD, inst[11:7], inst[19:15], inst[24:20], 29'd0);
                else
                    d_uop1 = pack_uop(OP_SUB, inst[11:7], inst[19:15], inst[24:20], 29'd0);
            end
            // ---- 直译: LUI(立即数左移 12 位) ----
            7'b0110111: begin
                d_uop1 = pack_uop(OP_LUI, inst[11:7], 5'd0, 5'd0,
                                  {inst[31:12], 12'd0} & 29'h1FFF_FFFF);
            end
            // ---- 直译: LD ----
            7'b0000011: begin
                if (inst[14:12] == 3'b011)
                    d_uop1 = pack_uop(OP_LD, inst[11:7], inst[19:15], 5'd0,
                                      {17'd0, inst[31:20]});
            end
            // ---- 拆分: SD(双字存储)拆成两条 32 位存储 ----
            7'b0100011: begin
                if (inst[14:12] == 3'b011) begin
                    d_uop1 = pack_uop(OP_ST, 5'd0, inst[19:15], inst[24:20],
                                      {17'd0, inst[31:25], inst[11:7]});
                    d_uop2 = pack_uop(OP_ST, 5'd0, inst[19:15], inst[24:20],
                                      {17'd0, inst[31:25], inst[11:7]} + 29'd4);
                    d_uop2_valid = 1'b1;
                end
            end
        endcase

        // ---- 融合: 上一条 LUI + 当前 ADDI, 且目的寄存器一致 ----
        // 合成为一条带 32 位立即数的 ADD
        if (prev_valid && (prev_inst[6:0] == 7'b0110111) &&   // LUI
            (inst[6:0] == 7'b0010011) &&                       // ADDI
            (prev_inst[11:7] == inst[19:15]) &&                // rd(lui) == rs1(addi)
            (prev_inst[11:7] == inst[11:7])) begin             // rd 一致
            // LUI 的高 20 位 + ADDI 的低 12 位 = 完整 32 位立即数
            // uop 立即数字段只有 29 位, 高位截断(教学模型够用, 见正文说明)
            d_uop1       = pack_uop(OP_ADD, inst[11:7], 5'd0, 5'd0,
                                    {prev_inst[31:12], inst[31:20]} & 29'h1FFF_FFFF);
            d_fused      = 1'b1;
            d_uop2_valid = 1'b0;
        end
    end

    assign uop1       = d_uop1;
    assign uop2       = d_uop2;
    assign uop2_valid = d_uop2_valid;
    assign fused      = d_fused;

endmodule
