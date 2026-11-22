// 两宽 RAT：把 32 个逻辑寄存器映射到 6 位物理寄存器编号
module rat #(
    parameter LOGIC_W  = 5,
    parameter PHYS_W   = 6,
    parameter NUM_LOGIC = 32,
    parameter RENAME_W = 2
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [RENAME_W-1:0]     wen_i,       // 本拍几条 uop 要改映射
    input  wire [LOGIC_W-1:0]      rd_idx_i0,   // 第一条的目的逻辑寄存器
    input  wire [LOGIC_W-1:0]      rd_idx_i1,   // 第二条的目的逻辑寄存器
    input  wire [PHYS_W-1:0]       new_pd_i0,   // 第一条拿到的物理寄存器
    input  wire [PHYS_W-1:0]       new_pd_i1,
    input  wire [LOGIC_W-1:0]      rs1_idx_i0,  // 第一条的源逻辑寄存器
    input  wire [LOGIC_W-1:0]      rs2_idx_i0,
    input  wire [LOGIC_W-1:0]      rs1_idx_i1,
    input  wire [LOGIC_W-1:0]      rs2_idx_i1,
    output wire [PHYS_W-1:0]       ps1_o0,      // 改名后的源物理寄存器
    output wire [PHYS_W-1:0]       ps2_o0,
    output wire [PHYS_W-1:0]       ps1_o1,
    output wire [PHYS_W-1:0]       ps2_o1,
    output wire [PHYS_W-1:0]       old_pd_o0,   // 被覆盖前的旧映射，交给 ROB
    output wire [PHYS_W-1:0]       old_pd_o1
);
    reg [PHYS_W-1:0] rat_ram [0:NUM_LOGIC-1];
    integer i;

    // x0 永远是 0，不能被改名
    wire we0 = wen_i[0] && (|rd_idx_i0);
    wire we1 = wen_i[1] && (|rd_idx_i1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_LOGIC; i = i + 1)
                rat_ram[i] <= i;
        end else begin
            if (we0) rat_ram[rd_idx_i0] <= new_pd_i0;
            // 同一组两条都写同一逻辑寄存器时，后一条的赋值写在后面，最终生效
            if (we1) rat_ram[rd_idx_i1] <= new_pd_i1;
        end
    end

    // 组内旁路：第二条读到的若是第一条刚写的目的寄存器，要立刻看到新映射
    function [PHYS_W-1:0] lookup;
        input [LOGIC_W-1:0] src_idx;
        input [LOGIC_W-1:0] prev_rd;
        input [PHYS_W-1:0] prev_pd;
        input              prev_en;
        begin
            if (prev_en && (src_idx == prev_rd))
                lookup = prev_pd;
            else
                lookup = rat_ram[src_idx];
        end
    endfunction

    assign ps1_o0    = rat_ram[rs1_idx_i0];
    assign ps2_o0    = rat_ram[rs2_idx_i0];
    assign old_pd_o0 = rat_ram[rd_idx_i0];

    assign ps1_o1    = lookup(rs1_idx_i1, rd_idx_i0, new_pd_i0, we0);
    assign ps2_o1    = lookup(rs2_idx_i1, rd_idx_i0, new_pd_i0, we0);
    assign old_pd_o1 = lookup(rd_idx_i1,  rd_idx_i0, new_pd_i0, we0);
endmodule
