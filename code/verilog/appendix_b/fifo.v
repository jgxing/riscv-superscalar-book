// 通用同步 FIFO：多一位指针区分满和空
// 第4章 FTQ、第6章指令缓冲用的都是这套办法
module fifo #(
    parameter DEPTH  = 8,
    parameter DATA_W = 32
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             push_i,
    input  wire [DATA_W-1:0] push_data_i,
    input  wire             pop_i,
    output reg  [DATA_W-1:0] pop_data_o,
    output wire             full_o,
    output wire             empty_o
);
    localparam PTR_W    = $clog2(DEPTH) + 1;  // 下标位数多留 1 位判满
    localparam DEPTH_M1 = DEPTH - 1;  // iverilog 不接受数组上界直接写参数表达式

    reg [DATA_W-1:0] mem [0:DEPTH_M1];
    reg [PTR_W-1:0]  head;
    reg [PTR_W-1:0]  tail;

    wire [PTR_W-1:0] next_head = head + 1'b1;
    wire [PTR_W-1:0] next_tail = tail + 1'b1;

    assign empty_o = (head == tail);
    // 判满：最高位不同、其余位相同。用当前 tail，不是 next_tail
    assign full_o  = (head[PTR_W-1] != tail[PTR_W-1]) &&
                     (head[PTR_W-2:0] == tail[PTR_W-2:0]);

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= {PTR_W{1'b0}};
            tail <= {PTR_W{1'b0}};
            pop_data_o <= {DATA_W{1'b0}};
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= {DATA_W{1'b0}};
        end else begin
            if (push_i && !full_o) begin
                // 索引必须取低位，写满时完整指针会越过数组边界
                mem[tail[PTR_W-2:0]] <= push_data_i;
                tail <= next_tail;
            end
            if (pop_i && !empty_o) begin
                pop_data_o <= mem[head[PTR_W-2:0]];
                head <= next_head;
            end
        end
    end
endmodule
