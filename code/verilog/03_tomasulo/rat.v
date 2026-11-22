// ==============================================================
// RAT (Register Alias Table) 重命名表 —— 教材第3章
// 作用：记录每个架构寄存器的最新值由哪个标签(物理位置)产生。
//   表项有效(valid=1)：寄存器堆里的旧值已过期，最新值在途，标签为 tag_ram[rd]
//   表项无效(valid=0)：寄存器堆里的值就是当前有效值
// WAW 化解：第二次写同一 rd 用新标签直接覆盖旧登记。
// ==============================================================
module rat #(
    parameter NREG  = 8,          // 架构寄存器个数（教学缩小为 8）
    parameter TAG_W = 5           // 标签位宽
)(
    input  wire             clk,
    input  wire             rst_n,

    // ---- 发射阶段：查两个源寄存器 ----
    input  wire [2:0]       rs1,
    input  wire [2:0]       rs2,
    output wire [TAG_W-1:0] q1,           // 0 表示可直接读寄存器堆
    output wire [TAG_W-1:0] q2,
    output wire             q1_valid,     // 1 表示需要等标签
    output wire             q2_valid,

    // ---- 发射阶段：更新目的寄存器（重命名）----
    input  wire             rename_en,
    input  wire [2:0]       rd,
    input  wire [TAG_W-1:0] new_tag,

    // ---- CDB 写回：清除所有登记该标签的表项 ----
    input  wire             cdb_valid,
    input  wire [TAG_W-1:0]  cdb_tag
);
    localparam NREG_LAST = NREG - 1;   // iverilog 需 localparam 中转数组上界
    reg [TAG_W-1:0] tag_ram [0:NREG_LAST];
    reg             valid [0:NREG_LAST];

    assign q1_valid = valid[rs1];
    assign q2_valid = valid[rs2];
    // 教学约定：标签 0 保留给"可直接读寄存器堆"，实际标签从 1 开始分配
    assign q1 = q1_valid ? tag_ram[rs1] : {TAG_W{1'b0}};
    assign q2 = q2_valid ? tag_ram[rs2] : {TAG_W{1'b0}};

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NREG; i = i + 1) begin
                valid[i] <= 1'b0;
                tag_ram[i] <= {TAG_W{1'b0}};
            end
        end else begin
            // 写回优先于重命名：同一拍广播结果的标签应被清掉
            if (cdb_valid) begin
                for (i = 0; i < NREG; i = i + 1)
                    if (valid[i] && (tag_ram[i] == cdb_tag))
                        valid[i] <= 1'b0;
            end
            if (rename_en) begin
                valid[rd] <= 1'b1;
                tag_ram[rd] <= new_tag;
            end
        end
    end
endmodule
