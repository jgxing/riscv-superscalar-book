`timescale 1ns/1ps

// 第 15 章 性能计数器骨架
// 把第 1 章那张 CPI 账本做成电路：周期数、提交数、四类停顿次数，
// 再加一个瓶颈编码，指出当前这一拍最该治哪一块。
module perf_counter #(
    parameter CNT_W    = 32,
    parameter COMMIT_W = 2
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // 第一组：算 IPC 要的两个数
    input  wire [COMMIT_W-1:0]     commit_i,     // 本拍提交了几条 uop
    output reg  [CNT_W-1:0]        cycle_o,      // 累计周期数
    output reg  [CNT_W-1:0]        commit_o,     // 累计提交数

    // 第二组：定位瓶颈要的四类事件
    input  wire                    front_stall_i, // 前端断粮
    input  wire                    issue_stall_i, // 发射口没货或执行端口不够
    input  wire                    lsq_stall_i,   // 访存队列满或等地址
    input  wire                    recover_i,     // 重定向与冲刷
    output reg  [CNT_W-1:0]        front_stall_o,
    output reg  [CNT_W-1:0]        issue_stall_o,
    output reg  [CNT_W-1:0]        lsq_stall_o,
    output reg  [CNT_W-1:0]        recover_o,

    // 第三组：当前瓶颈与 IPC 的分子分母
    output wire [1:0]              bottleneck_o,  // 0 前端 1 发射 2 访存 3 恢复
    output wire                    stall_any_o,   // 本拍是否有停顿
    output wire [CNT_W-1:0]        ipc_num_o,
    output wire [CNT_W-1:0]        ipc_den_o
);

    // 周期数和提交数各走各的：周期每拍加一，提交按本拍实际条数加
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_o  <= {CNT_W{1'b0}};
            commit_o <= {CNT_W{1'b0}};
        end else begin
            cycle_o  <= cycle_o + 1'b1;
            commit_o <= commit_o + commit_i;   // 短信号按上下文零扩展
        end
    end

    // 四类停顿各记各的账，同一拍可以同时命中多个
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            front_stall_o <= {CNT_W{1'b0}};
            issue_stall_o <= {CNT_W{1'b0}};
            lsq_stall_o   <= {CNT_W{1'b0}};
            recover_o     <= {CNT_W{1'b0}};
        end else begin
            front_stall_o <= front_stall_o + front_stall_i;
            issue_stall_o <= issue_stall_o + issue_stall_i;
            lsq_stall_o   <= lsq_stall_o   + lsq_stall_i;
            recover_o     <= recover_o     + recover_i;
        end
    end

    // 同一拍多个事件同时成立时按影响面取一个：恢复最重，前端最轻
    assign stall_any_o = front_stall_i | issue_stall_i | lsq_stall_i | recover_i;
    assign bottleneck_o = recover_i     ? 2'd3 :
                          lsq_stall_i   ? 2'd2 :
                          issue_stall_i ? 2'd1 :
                          front_stall_i ? 2'd0 : 2'd0;

    // IPC 留给上层软件算，这里只给分子分母，避免定点除法白丢精度
    assign ipc_num_o = commit_o;
    assign ipc_den_o = cycle_o;

endmodule
