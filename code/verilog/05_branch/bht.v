// ==============================================================
// BHT (Branch History Table) 分支历史表 —— 教材第5章
// 每个表项是一个 2 位饱和计数器，用 PC 低位索引。
//   复位默认 01（弱不跳）；taken 加一、not taken 减一，到 11/00 饱和。
//   预测看最高位 cnt[idx][1]：1 猜跳，0 猜不跳。
// ==============================================================
module bht #(
    parameter PC_W  = 32,
    parameter IDX_W = 4          // 表深 2^IDX_W = 16 项
)(
    input  wire             clk,
    input  wire             rst_n,
    // 预测端口：拿 pc 查表
    input  wire [PC_W-1:0]  pc,
    output wire             predict,
    output wire [1:0]       cnt_out,
    // 更新端口：分支执行完后写入真实方向
    input  wire             update_en,
    input  wire [PC_W-1:0]  update_pc,
    input  wire             taken
);
    localparam IDX_MAX = (1 << IDX_W) - 1;
    reg [1:0] cnt [0:IDX_MAX];

    wire [IDX_W-1:0] idx     = pc[IDX_W-1:0];
    wire [IDX_W-1:0] upd_idx = update_pc[IDX_W-1:0];

    assign cnt_out = cnt[idx];
    assign predict = cnt[idx][1];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i <= IDX_MAX; i = i + 1)
                cnt[i] <= 2'b01;          // 弱不跳起步，偏保守
        end else if (update_en) begin
            if (taken)
                cnt[upd_idx] <= (cnt[upd_idx] == 2'b11) ? 2'b11 : cnt[upd_idx] + 1'b1;
            else
                cnt[upd_idx] <= (cnt[upd_idx] == 2'b00) ? 2'b00 : cnt[upd_idx] - 1'b1;
        end
    end
endmodule
