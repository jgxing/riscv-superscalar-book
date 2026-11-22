// 简化 ROB：按程序顺序分配与提交，执行可乱序写回，异常时精确重定向
module rob #(
    parameter ENTRY    = 8,
    parameter PC_W     = 32,
    parameter PS_W     = 6,
    parameter PTR_W    = 4,      // 多一位用于判满，ENTRY=8 时索引占 3 位
    parameter COMMIT_W = 2        // 每拍最多提交几条
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // 分配：重命名/分派阶段按程序顺序写入
    input  wire                    alloc_en_i,
    input  wire [PC_W-1:0]         alloc_pc_i,
    input  wire [PS_W-1:0]         alloc_dest_i,
    input  wire [PS_W-1:0]         alloc_old_pd_i,

    // 乱序写回：执行完成时按 ROB 索引登记，可带异常
    input  wire                    complete_en_i,
    input  wire [PTR_W-2:0]        complete_idx_i,
    input  wire                    complete_except_i,

    // 提交输出：本拍提交了几条、第一条 PC、释放的 old_pd
    output reg  [COMMIT_W-1:0]     commit_cnt_o,
    output reg  [PC_W-1:0]         commit_pc_o,
    output reg  [PS_W-1:0]         commit_free0_o,
    output reg  [PS_W-1:0]         commit_free1_o,

    // 异常重定向：队头指令带异常时拉高，给出它的 PC
    output reg                     redirect_en_o,
    output reg  [PC_W-1:0]         redirect_pc_o,

    output wire                    full_o,
    output wire                    empty_o
);
    reg                   valid   [0:ENTRY-1];
    reg                   done    [0:ENTRY-1];
    reg                   except  [0:ENTRY-1];
    reg  [PC_W-1:0]        pc      [0:ENTRY-1];
    reg  [PS_W-1:0]        dest    [0:ENTRY-1];
    reg  [PS_W-1:0]        old_pd  [0:ENTRY-1];

    reg [PTR_W-1:0] head, tail;

    wire empty_i = (head == tail);
    wire full_i  = (head[PTR_W-1] != tail[PTR_W-1]) &&
                   (head[PTR_W-2:0] == tail[PTR_W-2:0]);
    assign empty_o = empty_i;
    assign full_o  = full_i;

    // 提交决策：从 head 起数连续 done 的项，遇到带异常的项就停并触发重定向
    reg [PTR_W-2:0]    cmt_idx;
    reg [COMMIT_W-1:0] cmt_cnt;
    reg                cmt_redirect;
    reg [PC_W-1:0]     cmt_redirect_pc;
    reg                cmt_stop;
    integer j;
    always @* begin
        cmt_cnt         = {COMMIT_W{1'b0}};
        cmt_redirect    = 1'b0;
        cmt_redirect_pc = {PC_W{1'b0}};
        cmt_stop        = 1'b0;
        for (j = 0; j < COMMIT_W; j = j + 1) begin
            cmt_idx = head[PTR_W-2:0] + j;   // ENTRY 取 2 的幂，低位加法自然回绕
            if (!cmt_stop && !empty_i && valid[cmt_idx] && done[cmt_idx]) begin
                if (except[cmt_idx]) begin
                    // 异常项之前的正常项本拍照常提交；异常项本身留到下一拍触发重定向
                    if (cmt_cnt == 0) begin
                        cmt_redirect    = 1'b1;
                        cmt_redirect_pc = pc[cmt_idx];
                    end
                    cmt_stop = 1'b1;
                end else begin
                    cmt_cnt = cmt_cnt + 1'b1;
                end
            end else begin
                cmt_stop = 1'b1;
            end
        end
    end

    integer i;
    reg [PTR_W-2:0] s_idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < ENTRY; i = i + 1) begin
                valid[i]  <= 1'b0;
                done[i]   <= 1'b0;
                except[i] <= 1'b0;
                pc[i]     <= {PC_W{1'b0}};
                dest[i]   <= {PS_W{1'b0}};
                old_pd[i] <= {PS_W{1'b0}};
            end
            head <= {PTR_W{1'b0}};
            tail <= {PTR_W{1'b0}};
            commit_cnt_o   <= {COMMIT_W{1'b0}};
            commit_pc_o    <= {PC_W{1'b0}};
            commit_free0_o <= {PS_W{1'b0}};
            commit_free1_o <= {PS_W{1'b0}};
            redirect_en_o  <= 1'b0;
            redirect_pc_o  <= {PC_W{1'b0}};
        end else begin
            // 默认：本拍没有提交、没有重定向
            commit_cnt_o  <= {COMMIT_W{1'b0}};
            redirect_en_o <= 1'b0;

            // 1) 乱序写回：登记完成，并记下是否带异常
            if (complete_en_i) begin
                done[complete_idx_i]   <= 1'b1;
                except[complete_idx_i] <= complete_except_i;
            end

            // 2) 提交
            if (cmt_redirect) begin
                // 队头异常：精确重定向，清空整个 ROB，从异常 PC 重新取指
                redirect_en_o <= 1'b1;
                redirect_pc_o <= cmt_redirect_pc;
                for (i = 0; i < ENTRY; i = i + 1)
                    valid[i] <= 1'b0;
                head <= {PTR_W{1'b0}};
                tail <= {PTR_W{1'b0}};
            end else if (cmt_cnt != 0) begin
                // 正常提交：释放 old_pd，推进 head
                commit_cnt_o   <= cmt_cnt;
                commit_pc_o    <= pc[head[PTR_W-2:0]];
                commit_free0_o <= old_pd[head[PTR_W-2:0]];
                if (cmt_cnt > 1)
                    commit_free1_o <= old_pd[head[PTR_W-2:0] + 1'd1];
                for (i = 0; i < COMMIT_W; i = i + 1)
                    if (i < cmt_cnt) begin
                        s_idx = head[PTR_W-2:0] + i;
                        valid[s_idx] <= 1'b0;
                    end
                head <= head + { {(PTR_W-COMMIT_W){1'b0}}, cmt_cnt };
            end

            // 3) 分配：写在最后，避免同拍提交清掉刚进来的项
            if (alloc_en_i && !full_i) begin
                valid[tail[PTR_W-2:0]]  <= 1'b1;
                done[tail[PTR_W-2:0]]   <= 1'b0;
                except[tail[PTR_W-2:0]] <= 1'b0;
                pc[tail[PTR_W-2:0]]     <= alloc_pc_i;
                dest[tail[PTR_W-2:0]]   <= alloc_dest_i;
                old_pd[tail[PTR_W-2:0]] <= alloc_old_pd_i;
                tail <= tail + 1'b1;
            end
        end
    end
endmodule
