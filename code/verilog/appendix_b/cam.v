// 内容寻址存储器 CAM：给一个 key，并行查所有表项，返回命中和位置
// 发射队列的源操作数监听、TLB、分支目标表都用到这个动作
module cam #(
    parameter N     = 8,
    parameter KEY_W = 6
)(
    input  wire [KEY_W-1:0]    key_i,
    input  wire [N*KEY_W-1:0]  table_i,   // N 个表项打包成一位向量
    input  wire [N-1:0]        valid_i,
    output wire [N-1:0]        match_o,   // 每项是否相等
    output reg                 hit_o,     // 有没有任一项命中
    output reg  [2:0]          index_o    // 命中项编号，N<=8 用 3 位
);
    wire [N-1:0] eq;
    integer i;

    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : cmp
            assign eq[g] = valid_i[g] &&
                           (table_i[g*KEY_W +: KEY_W] == key_i);
        end
    endgenerate

    assign match_o = eq;

    // 多项同时命中时取编号最小的那个，和仲裁器的"最老优先"一个道理
    always @* begin
        hit_o   = 1'b0;
        index_o = 3'd0;
        for (i = 0; i < N; i = i + 1)
            if (eq[i] && !hit_o) begin
                hit_o   = 1'b1;
                index_o = i[2:0];
            end
    end
endmodule
