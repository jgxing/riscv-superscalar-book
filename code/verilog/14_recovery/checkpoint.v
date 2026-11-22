// 检查点缓冲：分支重命名时拍下 RAT 与空闲表的快照，预测错误时按编号恢复
module checkpoint #(
    parameter NCP      = 4,
    parameter CP_ID_W  = 2,
    parameter PHYS_W   = 6,
    parameter NUM_LOGIC = 32,
    parameter FL_PTR_W = 6,
    parameter SEQ_W    = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // 拍快照：分支重命名时存进第一个空槽
    input  wire                         save_en_i,
    input  wire [NUM_LOGIC*PHYS_W-1:0]  save_rat_i,
    input  wire [FL_PTR_W-1:0]          save_fl_head_i,
    input  wire [FL_PTR_W-1:0]          save_fl_tail_i,
    input  wire [SEQ_W-1:0]             save_seq_i,
    output wire [CP_ID_W-1:0]           save_id_o,
    output wire                         save_full_o,

    // 恢复：按编号组合读出快照
    input  wire [CP_ID_W-1:0]           restore_id_i,
    output reg  [NUM_LOGIC*PHYS_W-1:0]  restore_rat_o,
    output reg  [FL_PTR_W-1:0]          restore_fl_head_o,
    output reg  [FL_PTR_W-1:0]          restore_fl_tail_o,

    // 释放：分支退休后回收槽位
    input  wire                         release_en_i,
    input  wire [CP_ID_W-1:0]           release_id_i
);
    reg                         valid [0:NCP-1];
    reg [SEQ_W-1:0]             seq_snap   [0:NCP-1];
    reg [FL_PTR_W-1:0]          fl_head_s  [0:NCP-1];
    reg [FL_PTR_W-1:0]          fl_tail_s  [0:NCP-1];
    reg [PHYS_W-1:0]            rat_snap   [0:NCP-1][0:NUM_LOGIC-1];

    // 找第一个空槽
    reg [CP_ID_W-1:0] free_id;
    reg found;
    integer s;
    always @* begin
        free_id = {CP_ID_W{1'b0}};
        found   = 1'b0;
        for (s = 0; s < NCP; s = s + 1)
            if (!valid[s] && !found) begin
                free_id = s;
                found   = 1'b1;
            end
    end
    assign save_id_o   = free_id;
    assign save_full_o = !found;

    // 恢复是纯组合读，编号一到数据就出来
    integer r;
    always @* begin
        for (r = 0; r < NUM_LOGIC; r = r + 1)
            restore_rat_o[r*PHYS_W +: PHYS_W] = rat_snap[restore_id_i][r];
        restore_fl_head_o = fl_head_s[restore_id_i];
        restore_fl_tail_o = fl_tail_s[restore_id_i];
    end

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (s = 0; s < NCP; s = s + 1)
                valid[s] <= 1'b0;
        end else begin
            // 拍快照：整张 RAT 按位切片写进去
            if (save_en_i && found) begin
                valid[free_id]       <= 1'b1;
                seq_snap[free_id]    <= save_seq_i;
                fl_head_s[free_id]   <= save_fl_head_i;
                fl_tail_s[free_id]   <= save_fl_tail_i;
                for (k = 0; k < NUM_LOGIC; k = k + 1)
                    rat_snap[free_id][k] <= save_rat_i[k*PHYS_W +: PHYS_W];
            end
            // 释放写在后面：同一拍既存又放同一槽时，释放优先
            if (release_en_i)
                valid[release_id_i] <= 1'b0;
        end
    end
endmodule
