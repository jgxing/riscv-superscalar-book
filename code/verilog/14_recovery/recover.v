// 重定向与冲刷控制：两路来源选一个，发前端重定向、后端 kill 掩码和状态恢复数据
module recover #(
    parameter CP_ID_W   = 2,
    parameter SEQ_W     = 8,
    parameter PHYS_W    = 6,
    parameter NUM_LOGIC = 32,
    parameter FL_PTR_W  = 6,
    parameter PC_W      = 32,
    parameter NUM_UOP   = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // 来源一：分支执行单元发现预测错误
    input  wire                         br_mispred_i,
    input  wire [PC_W-1:0]              br_pc_i,        // 算出来的正确目标
    input  wire [SEQ_W-1:0]             br_seq_i,       // 分支的序号
    input  wire [CP_ID_W-1:0]           br_cp_i,        // 分支的检查点号

    // 来源二：提交口发现异常
    input  wire                         exc_i,
    input  wire [PC_W-1:0]              exc_pc_i,
    input  wire [SEQ_W-1:0]             exc_seq_i,
    input  wire [CP_ID_W-1:0]           exc_cp_i,

    // 拍快照的接口，透传给检查点缓冲
    input  wire                         save_en_i,
    input  wire [NUM_LOGIC*PHYS_W-1:0]  save_rat_i,
    input  wire [FL_PTR_W-1:0]          save_fl_head_i,
    input  wire [FL_PTR_W-1:0]          save_fl_tail_i,
    input  wire [SEQ_W-1:0]             save_seq_i,
    output wire [CP_ID_W-1:0]           save_id_o,
    output wire                         save_full_o,

    // 释放检查点
    input  wire                         release_en_i,
    input  wire [CP_ID_W-1:0]           release_id_i,

    // 输出：前端重定向
    output reg                          front_redirect_o,
    output reg  [PC_W-1:0]              front_pc_o,
    // 输出：后端冲刷，序号不小于阈值的 uop 全部作废
    output reg                          back_flush_o,
    output reg  [SEQ_W-1:0]             kill_from_o,
    // 输出：恢复到检查点的 RAT 与空闲表指针
    output wire                         restore_en_o,
    output wire [NUM_LOGIC*PHYS_W-1:0]  restore_rat_o,
    output wire [FL_PTR_W-1:0]          restore_fl_head_o,
    output wire [FL_PTR_W-1:0]          restore_fl_tail_o,
    // 输入：一组在飞 uop 的序号，用来逐项判定该不该 kill
    input  wire [SEQ_W*NUM_UOP-1:0]     uop_seq_i,

    // 输出：这组 uop 中哪些落在错误路径上
    output reg  [NUM_UOP-1:0]           kill_mask_o
);
    // 两路来源仲裁：异常优先，因为提交口的事必须马上处理
    reg [PC_W-1:0]   sel_pc;
    reg [SEQ_W-1:0]  sel_seq;
    reg [CP_ID_W-1:0] sel_cp;
    reg any_redirect;
    always @* begin
        any_redirect = exc_i || br_mispred_i;
        if (exc_i) begin
            sel_pc  = exc_pc_i;
            sel_seq = exc_seq_i;
            sel_cp  = exc_cp_i;
        end else if (br_mispred_i) begin
            sel_pc  = br_pc_i;
            sel_seq = br_seq_i;
            sel_cp  = br_cp_i;
        end else begin
            sel_pc  = {PC_W{1'b0}};
            sel_seq = {SEQ_W{1'b0}};
            sel_cp  = {CP_ID_W{1'b0}};
        end
    end

    // 检查点缓冲：保存时挑空槽，恢复时按选中的编号读
    checkpoint #(
        .NCP(4), .CP_ID_W(CP_ID_W),
        .PHYS_W(PHYS_W), .NUM_LOGIC(NUM_LOGIC),
        .FL_PTR_W(FL_PTR_W), .SEQ_W(SEQ_W)
    ) u_cp (
        .clk(clk), .rst_n(rst_n),
        .save_en_i(save_en_i), .save_rat_i(save_rat_i),
        .save_fl_head_i(save_fl_head_i), .save_fl_tail_i(save_fl_tail_i),
        .save_seq_i(save_seq_i),
        .save_id_o(save_id_o), .save_full_o(save_full_o),
        .restore_id_i(sel_cp),
        .restore_rat_o(restore_rat_o),
        .restore_fl_head_o(restore_fl_head_o),
        .restore_fl_tail_o(restore_fl_tail_o),
        .release_en_i(release_en_i), .release_id_i(release_id_i)
    );

    assign restore_en_o = any_redirect;

    // 输出直接由仲裁结果驱动，组合逻辑，一拍内完成
    always @* begin
        front_redirect_o = any_redirect;
        front_pc_o       = sel_pc;
        back_flush_o     = any_redirect;
        kill_from_o      = sel_seq;
    end

    // kill 掩码：给每个在飞 uop 判年龄，序号不小于出错序号的都冲掉
    integer a;
    always @* begin
        for (a = 0; a < NUM_UOP; a = a + 1)
            kill_mask_o[a] = any_redirect &&
                (uop_seq_i[a*SEQ_W +: SEQ_W] >= sel_seq);
    end
endmodule
