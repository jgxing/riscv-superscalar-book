// ==============================================================
// BTB (Branch Target Buffer) 分支目标缓冲 —— 教材第5章
// 直接映射表：用 PC 中间位索引，表项存 [有效位, 标签, 目标地址]。
//   命中条件：valid=1 且 tag 匹配。命中才给出 target。
// ==============================================================
module btb #(
    parameter PC_W  = 32,
    parameter IDX_W = 4,          // 表深 16 项
    parameter TAG_W = 6
)(
    input  wire             clk,
    input  wire             rst_n,
    // 预测端口：拿 pc 查表
    input  wire [PC_W-1:0]  pc,
    output wire             hit,
    output wire [PC_W-1:0]  target,
    // 更新端口：分支执行完后写入正确目标
    input  wire             update_en,
    input  wire [PC_W-1:0]  update_pc,
    input  wire [PC_W-1:0]  update_target
);
    localparam IDX_MAX = (1 << IDX_W) - 1;
    reg [TAG_W-1:0]  tag        [0:IDX_MAX];
    reg [PC_W-1:0]   target_mem [0:IDX_MAX];
    reg              valid      [0:IDX_MAX];

    // 索引取 PC 中间位（最低 2 位恒为 0，跳过）
    wire [IDX_W-1:0] idx     = pc[IDX_W+1:2];
    wire [IDX_W-1:0] upd_idx = update_pc[IDX_W+1:2];
    wire [TAG_W-1:0] pc_tag  = pc[PC_W-1:PC_W-TAG_W];

    assign hit    = valid[idx] && (tag[idx] == pc_tag);
    assign target = target_mem[idx];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i <= IDX_MAX; i = i + 1) begin
                valid[i]      <= 1'b0;
                tag[i]        <= {TAG_W{1'b0}};
                target_mem[i] <= {PC_W{1'b0}};
            end
        end else if (update_en) begin
            valid[upd_idx]      <= 1'b1;
            tag[upd_idx]        <= update_pc[PC_W-1:PC_W-TAG_W];
            target_mem[upd_idx] <= update_target;
        end
    end
endmodule
