// 两宽重命名站：RAT 改名 + 空闲表分配 + 旧映射送 ROB 回收
module rename #(
    parameter LOGIC_W   = 5,
    parameter PHYS_W    = 6,
    parameter NUM_LOGIC = 32,
    parameter FREE_DEPTH = 32,
    parameter PTR_W     = 6
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire [1:0]           wen_i,
    input  wire [LOGIC_W-1:0]   rd_idx_i0,
    input  wire [LOGIC_W-1:0]   rd_idx_i1,
    input  wire [LOGIC_W-1:0]   rs1_idx_i0,
    input  wire [LOGIC_W-1:0]   rs2_idx_i0,
    input  wire [LOGIC_W-1:0]   rs1_idx_i1,
    input  wire [LOGIC_W-1:0]   rs2_idx_i1,
    input  wire [1:0]           free_en_i,   // 来自 ROB 的提交回收
    input  wire [PHYS_W-1:0]    free_i0,
    input  wire [PHYS_W-1:0]    free_i1,
    output wire [PHYS_W-1:0]    pd_o0,
    output wire [PHYS_W-1:0]    pd_o1,
    output wire [PHYS_W-1:0]    ps1_o0,
    output wire [PHYS_W-1:0]    ps2_o0,
    output wire [PHYS_W-1:0]    ps1_o1,
    output wire [PHYS_W-1:0]    ps2_o1,
    output wire [PHYS_W-1:0]    old_pd_o0,
    output wire [PHYS_W-1:0]    old_pd_o1,
    output wire [PTR_W-1:0]     free_cnt_o,  // 供观察与背压
    output wire                 stall_o
);
    wire [1:0] alloc;
    assign alloc = {1'b0, wen_i[0]} + {1'b0, wen_i[1]};

    wire fl_empty, fl_full;

    free_list #(
        .PHYS_W(PHYS_W), .NUM_LOGIC(NUM_LOGIC),
        .DEPTH(FREE_DEPTH), .PTR_W(PTR_W)
    ) u_free (
        .clk(clk), .rst_n(rst_n),
        .alloc_i(alloc), .free_en_i(free_en_i),
        .free_i0(free_i0), .free_i1(free_i1),
        .pd_o0(pd_o0), .pd_o1(pd_o1),
        .empty_o(fl_empty), .full_o(fl_full), .count_o(free_cnt_o)
    );

    rat #(
        .LOGIC_W(LOGIC_W), .PHYS_W(PHYS_W), .NUM_LOGIC(NUM_LOGIC)
    ) u_rat (
        .clk(clk), .rst_n(rst_n), .wen_i(wen_i),
        .rd_idx_i0(rd_idx_i0), .rd_idx_i1(rd_idx_i1),
        .new_pd_i0(pd_o0), .new_pd_i1(pd_o1),
        .rs1_idx_i0(rs1_idx_i0), .rs2_idx_i0(rs2_idx_i0),
        .rs1_idx_i1(rs1_idx_i1), .rs2_idx_i1(rs2_idx_i1),
        .ps1_o0(ps1_o0), .ps2_o0(ps2_o0),
        .ps1_o1(ps1_o1), .ps2_o1(ps2_o1),
        .old_pd_o0(old_pd_o0), .old_pd_o1(old_pd_o1)
    );

    wire [6:0] avail;
    assign avail = {1'b0, free_cnt_o} + {6'b0, free_en_i[0]} + {6'b0, free_en_i[1]};
    assign stall_o = (avail < {5'b0, alloc});
endmodule
