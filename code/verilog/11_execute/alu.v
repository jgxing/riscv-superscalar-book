// 单周期整数 ALU：加、减、与、或、异或、左移、小于置一
module alu #(
    parameter DATA_W = 32
)(
    input  wire [3:0]            op_i,      // 操作码
    input  wire [DATA_W-1:0]     a_i,       // 第一个操作数
    input  wire [DATA_W-1:0]     b_i,       // 第二个操作数
    output reg  [DATA_W-1:0]     result_o
);
    localparam ALU_ADD = 4'd0;
    localparam ALU_SUB = 4'd1;
    localparam ALU_AND = 4'd2;
    localparam ALU_OR  = 4'd3;
    localparam ALU_XOR = 4'd4;
    localparam ALU_SLL = 4'd5;
    localparam ALU_SLT = 4'd6;

    always @* begin
        case (op_i)
            ALU_ADD: result_o = a_i + b_i;
            ALU_SUB: result_o = a_i - b_i;
            ALU_AND: result_o = a_i & b_i;
            ALU_OR : result_o = a_i | b_i;
            ALU_XOR: result_o = a_i ^ b_i;
            ALU_SLL: result_o = a_i << b_i[4:0];
            ALU_SLT: result_o = {{(DATA_W-1){1'b0}}, (a_i < b_i)};
            default: result_o = {DATA_W{1'b0}};
        endcase
    end
endmodule
