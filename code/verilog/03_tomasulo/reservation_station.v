// ==============================================================
// 保留站条目 Reservation Station —— 教材第3章
// 操作数要么已有数据(vj/vk_valid=1)，要么在等某个标签(qj/qk)。
// 监听 CDB：标签匹配即锁存数据、清除等待标志 —— 这就是"唤醒"。
// ==============================================================
module reservation_station #(
    parameter TAG_W  = 5,
    parameter DATA_W = 32
)(
    input  wire             clk,
    input  wire             rst_n,

    // ---- 发射写入（占用本项）----
    input  wire             issue_en,
    input  wire [3:0]       op_in,
    input  wire             vj_valid_in,
    input  wire             vk_valid_in,
    input  wire [DATA_W-1:0] vj_in,
    input  wire [DATA_W-1:0] vk_in,
    input  wire [TAG_W-1:0]  qj_in,
    input  wire [TAG_W-1:0]  qk_in,
    input  wire [TAG_W-1:0]  dest_tag_in,

    // ---- CDB 广播监听 ----
    input  wire             cdb_valid,
    input  wire [TAG_W-1:0]  cdb_tag,
    input  wire [DATA_W-1:0] cdb_data,

    // ---- 被取走执行（简化握手）----
    input  wire             dispatch_en,

    // ---- 输出给功能部件 ----
    output wire             busy,
    output wire             ready,
    output wire [3:0]       op_out,
    output wire [DATA_W-1:0] vj_out,
    output wire [DATA_W-1:0] vk_out,
    output wire [TAG_W-1:0]  dest_tag_out
);
    reg             r_busy;
    reg [3:0]       r_op;
    reg             r_vj_valid, r_vk_valid;
    reg [DATA_W-1:0] r_vj, r_vk;
    reg [TAG_W-1:0]  r_qj, r_qk;
    reg [TAG_W-1:0]  r_dest_tag;

    assign busy         = r_busy;
    assign ready        = r_busy && r_vj_valid && r_vk_valid;  // 两操作数都就绪
    assign op_out       = r_op;
    assign vj_out       = r_vj;
    assign vk_out       = r_vk;
    assign dest_tag_out = r_dest_tag;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_busy <= 1'b0;
            r_vj_valid <= 1'b0;  r_vk_valid <= 1'b0;
            r_vj <= 0;  r_vk <= 0;
            r_qj <= 0;  r_qk <= 0;
            r_op <= 0;  r_dest_tag <= 0;
        end else begin
            // 优先级：被取走 > 发射写入 > CDB 唤醒
            if (dispatch_en) begin
                r_busy <= 1'b0;                 // 交给功能部件，释放本项
            end else if (issue_en) begin
                r_busy      <= 1'b1;
                r_op        <= op_in;
                r_dest_tag  <= dest_tag_in;
                r_vj_valid  <= vj_valid_in;  r_vk_valid <= vk_valid_in;
                r_vj        <= vj_in;        r_vk       <= vk_in;
                r_qj        <= qj_in;        r_qk       <= qk_in;
            end else if (cdb_valid && r_busy) begin
                // 监听广播：两个操作数独立判断，可同拍一起唤醒
                if (!r_vj_valid && (r_qj == cdb_tag)) begin
                    r_vj       <= cdb_data;
                    r_vj_valid <= 1'b1;
                end
                if (!r_vk_valid && (r_qk == cdb_tag)) begin
                    r_vk       <= cdb_data;
                    r_vk_valid <= 1'b1;
                end
            end
        end
    end
endmodule
