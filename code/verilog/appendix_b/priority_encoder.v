// 优先编码器：从一组请求里找出编号最小的置位，输出它的二进制编码
// CAM 命中后要给出位置、中断控制器挑最高优先级，都靠它
module priority_encoder #(
    parameter N = 8
)(
    input  wire [N-1:0]     req_i,
    output reg              valid_o,
    output reg  [2:0]       code_o    // N<=8 用 3 位
);
    reg found;
    integer i;

    always @* begin
        found  = 1'b0;
        code_o = 3'd0;
        // 从低到扫，第一个命中的锁定下来，后面再命中也不覆盖
        for (i = 0; i < N; i = i + 1)
            if (req_i[i] && !found) begin
                found  = 1'b1;
                code_o = i[2:0];
            end
        valid_o = found;
    end
endmodule
