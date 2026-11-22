// 第4章 取指目标队列 FTQ
// 一个存地址的简单同步 FIFO：预测器从队尾写，取指从队头读。
// 用"多一位指针"区分满和空，避免 head==tail 的二义性。
module ftq #(
    parameter DEPTH  = 8,
    parameter ADDR_W = 32
)(
    input  wire             clk,
    input  wire             rst_n,

    // 预测器写端口（生产者）
    input  wire             push,
    input  wire [ADDR_W-1:0] push_addr,
    output wire             full,

    // 取指读端口（消费者）
    input  wire             pop,
    output reg  [ADDR_W-1:0] pop_addr,
    output wire             empty
);
    // 深度 8 需要 3 位表示下标，多留一位用来区分满和空
    localparam PTR_W    = 4;
    // iverilog 不接受存储器上界直接写参数表达式，先转成 localparam
    localparam DEPTH_M1 = DEPTH - 1;

    reg [ADDR_W-1:0] ftq_mem [0:DEPTH_M1];
    reg [PTR_W-1:0]  head;   // 队头指针，取指一侧推进
    reg [PTR_W-1:0]  tail;   // 队尾指针，预测一侧推进

    wire [PTR_W-1:0] next_tail = tail + 1'b1;
    wire [PTR_W-1:0] next_head = head + 1'b1;

    // 判空：两个指针完全相同
    // 判满：最高位不同、其余位相同（tail 比 head 多绕了一整圈）
    assign empty = (head == tail);
    assign full  = (head[PTR_W-1] != tail[PTR_W-1]) &&
                   (head[PTR_W-2:0] == tail[PTR_W-2:0]);

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head     <= {PTR_W{1'b0}};
            tail     <= {PTR_W{1'b0}};
            pop_addr <= {ADDR_W{1'b0}};
            for (i = 0; i < DEPTH; i = i + 1)
                ftq_mem[i] <= {ADDR_W{1'b0}};
        end else begin
            // 写、读同拍时各走各的指针，先写后读互不干扰
            if (push && !full) begin
                ftq_mem[tail[PTR_W-2:0]] <= push_addr;
                tail          <= next_tail;
            end
            if (pop && !empty) begin
                pop_addr <= ftq_mem[head[PTR_W-2:0]];
                head     <= next_head;
            end
        end
    end
endmodule
