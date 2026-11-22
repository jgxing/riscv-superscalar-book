// 从最多 N 个请求里挑出最多两个，编号小的优先
module arbiter #(
    parameter N = 4,
    parameter SEQ_W = 8
)(
    input  wire [N-1:0]         req_i,
    input  wire [N*SEQ_W-1:0]   age_i,     // 每项的年龄，数越小越老
    input  wire [1:0]           limit_i,   // 最多批几个：0、1 或 2
    output wire [N-1:0]         grant0_o,  // 第一个被选中的项
    output wire [N-1:0]         grant1_o,  // 第二个被选中的项
    output wire [N-1:0]         grant_o
);
    reg [N-1:0] g0, g1;
    reg [SEQ_W-1:0] best;
    integer i;

    always @* begin
        // 第一张票给年龄最小的请求，不是编号最小的请求
        g0 = {N{1'b0}};
        best = {SEQ_W{1'b1}};
        for (i = 0; i < N; i = i + 1)
            if (req_i[i] && (age_i[i*SEQ_W +: SEQ_W] < best)) begin
                best = age_i[i*SEQ_W +: SEQ_W];
                g0 = {N{1'b0}};
                g0[i] = 1'b1;
            end

        // 第二张票在剩下的请求里同样挑最老的
        g1 = {N{1'b0}};
        best = {SEQ_W{1'b1}};
        for (i = 0; i < N; i = i + 1)
            if (req_i[i] && !g0[i] && (age_i[i*SEQ_W +: SEQ_W] < best)) begin
                best = age_i[i*SEQ_W +: SEQ_W];
                g1 = {N{1'b0}};
                g1[i] = 1'b1;
            end

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
