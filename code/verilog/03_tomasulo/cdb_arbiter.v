// ==============================================================
// CDB 仲裁器 —— 教材第3章"广播瓶颈"的具体体现
// 多个功能部件同时完成，一根 CDB 一拍只能 broadcast 一个结果。
// 采用简单固定优先仲裁（编号小者优先）。
// 用 for + first-winner 写法，纯 Verilog-2001 可综合。
// ==============================================================
module cdb_arbiter #(
    parameter N     = 4,
    parameter TAG_W = 5,
    parameter DATA_W = 32
)(
    input  wire [N-1:0]              req,
    input  wire [N*TAG_W-1:0]        req_tag,    // 拼接: {tagN,...,tag1,tag0}
    input  wire [N*DATA_W-1:0]       req_data,
    output reg                       cdb_valid,
    output reg  [TAG_W-1:0]          cdb_tag,
    output reg  [DATA_W-1:0]         cdb_data,
    output reg  [N-1:0]              grant       // 给被选中者回握手
);
    integer k;
    always @(*) begin
        cdb_valid = 1'b0;
        cdb_tag   = {TAG_W{1'b0}};
        cdb_data  = {DATA_W{1'b0}};
        grant     = {N{1'b0}};
        for (k = 0; k < N; k = k + 1) begin
            if (req[k] && !cdb_valid) begin      // 第一个置位请求者获胜
                cdb_valid = 1'b1;
                cdb_tag   = req_tag[k*TAG_W +: TAG_W];
                cdb_data  = req_data[k*DATA_W +: DATA_W];
                grant[k]  = 1'b1;
            end
        end
    end
endmodule
