// 一个整数执行口：旁路选源，ALU 运算，结果连同目的号寄存下来供广播
module exec_unit #(
    parameter PS_W   = 6,
    parameter DATA_W = 32
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   valid_i,      // 本拍发射口是否送来一条 uop
    input  wire [3:0]             op_i,
    input  wire [PS_W-1:0]        ps1_i,
    input  wire [PS_W-1:0]        ps2_i,
    input  wire [PS_W-1:0]        dest_i,       // 目的物理号，随结果一起广播
    input  wire [DATA_W-1:0]      rdata1_i,     // 寄存器堆读出的两个源值
    input  wire [DATA_W-1:0]      rdata2_i,
    input  wire [1:0]             byp_en_i,
    input  wire [PS_W-1:0]        byp_dest_i0,
    input  wire [DATA_W-1:0]      byp_data_i0,
    input  wire [PS_W-1:0]        byp_dest_i1,
    input  wire [DATA_W-1:0]      byp_data_i1,
    output reg  [DATA_W-1:0]      result_o,
    output reg  [PS_W-1:0]        dest_o,
    output reg                    out_valid_o
);
    wire [DATA_W-1:0] src1, src2;

    bypass #(.PS_W(PS_W), .DATA_W(DATA_W)) u_byp (
        .ps1_i(ps1_i), .ps2_i(ps2_i),
        .rdata1_i(rdata1_i), .rdata2_i(rdata2_i),
        .byp_en_i(byp_en_i),
        .byp_dest_i0(byp_dest_i0), .byp_data_i0(byp_data_i0),
        .byp_dest_i1(byp_dest_i1), .byp_data_i1(byp_data_i1),
        .src1_o(src1), .src2_o(src2)
    );

    wire [DATA_W-1:0] alu_result;
    alu #(.DATA_W(DATA_W)) u_alu (
        .op_i(op_i), .a_i(src1), .b_i(src2), .result_o(alu_result)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_o    <= {DATA_W{1'b0}};
            dest_o      <= {PS_W{1'b0}};
            out_valid_o <= 1'b0;
        end else begin
            out_valid_o <= valid_i;
            dest_o      <= dest_i;
            result_o    <= alu_result;
        end
    end
endmodule
