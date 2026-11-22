// 仲裁器：N 个请求里按优先级挑出最多两个，给出发票
// 第10章发射队列用的就是它，优先级由输入的 age 决定
module arbiter #(
    parameter N     = 4,
    parameter AGE_W = 8
)(
    input  wire [N-1:0]         req_i,
    input  wire [N*AGE_W-1:0]   age_i,     // 每项年龄，数越小越老
    input  wire [1:0]           limit_i,   // 最多批几个：0、1 或 2
    output wire [N-1:0]         grant0_o,  // 第一张票
    output wire [N-1:0]         grant1_o,  // 第二张票
    output wire [N-1:0]         grant_o
);
    reg [N-1:0]       g0, g1;
    reg [AGE_W-1:0]   best;
    integer i;

    always @* begin
        // 第一张票给年龄最小的请求
        g0   = {N{1'b0}};
        best = {AGE_W{1'b1}};
        for (i = 0; i < N; i = i + 1)
            if (req_i[i] && (age_i[i*AGE_W +: AGE_W] < best)) begin
                best = age_i[i*AGE_W +: AGE_W];
                g0   = {N{1'b0}};
                g0[i] = 1'b1;
            end

        // 第二张票在剩下的请求里同样挑最老的
        g1   = {N{1'b0}};
        best = {AGE_W{1'b1}};
        for (i = 0; i < N; i = i + 1)
            if (req_i[i] && !g0[i] && (age_i[i*AGE_W +: AGE_W] < best)) begin
                best = age_i[i*AGE_W +: AGE_W];
                g1   = {N{1'b0}};
                g1[i] = 1'b1;
            end

        // limit 限制一拍最多放行几个
        if (limit_i == 2'd0) begin
            g0 = {N{1'b0}};
            g1 = {N{1'b0}};
        end else if (limit_i == 2'd1) begin
            g1 = {N{1'b0}};
        end
    end

    assign grant0_o = g0;
    assign grant1_o = g1;
    assign grant_o  = g0 | g1;
endmodule
