// 交叉开关 crossbar：N 个输入按需路由到 N 个输出
// 每个输入带上想去的输出号，输出侧从所有指向自己的输入里选一个
// 冲突时编号小的输入优先，这是最简单的仲裁策略
module crossbar #(
    parameter N      = 4,
    parameter DATA_W = 32
)(
    input  wire [N-1:0]             req_i,     // 每个输入有没有请求
    input  wire [N*2-1:0]           dst_i,     // 每个输入的目标号，N<=4 用 2 位
    input  wire [N*DATA_W-1:0]      data_i,    // N 路输入数据打包
    output reg  [N*DATA_W-1:0]      data_o,    // N 路输出数据打包
    output reg  [N-1:0]             valid_o    // 每个输出有没有拿到数据
);
    integer out_k, in_j;

    always @* begin
        for (out_k = 0; out_k < N; out_k = out_k + 1) begin
            valid_o[out_k] = 1'b0;
            data_o[out_k*DATA_W +: DATA_W] = {DATA_W{1'b0}};
            // 遍历所有输入，找指向本输出且编号最小的那个
            for (in_j = 0; in_j < N; in_j = in_j + 1) begin
                if (req_i[in_j] &&
                    (dst_i[in_j*2 +: 2] == out_k[1:0]) &&
                    !valid_o[out_k]) begin
                    valid_o[out_k] = 1'b1;
                    data_o[out_k*DATA_W +: DATA_W] = data_i[in_j*DATA_W +: DATA_W];
                end
            end
        end
    end
endmodule
