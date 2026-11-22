// 空闲物理寄存器池：深度 32 的循环队列
// 复位时装入 P32..P63，P0..P31 留给 32 个逻辑寄存器的初始映射
module free_list #(
    parameter PHYS_W   = 6,
    parameter NUM_LOGIC = 32,
    parameter DEPTH    = 32,
    parameter PTR_W    = 6
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire [1:0]           alloc_i,     // 本拍要分配几个
    input  wire [1:0]           free_en_i,   // 本拍要回收几个
    input  wire [PHYS_W-1:0]    free_i0,     // 回收的物理寄存器号
    input  wire [PHYS_W-1:0]    free_i1,
    output wire [PHYS_W-1:0]    pd_o0,       // 分配出去的物理寄存器号
    output wire [PHYS_W-1:0]    pd_o1,
    output wire                 empty_o,
    output wire                 full_o,
    output wire [PTR_W-1:0]     count_o
);
    localparam [PTR_W-1:0] TAIL_INIT = DEPTH;

    reg [PHYS_W-1:0] fl_mem [0:DEPTH-1];
    reg [PTR_W-1:0] head, tail;
    integer i;

    // 多一位指针判满时，索引存储器只能用低位
    assign pd_o0 = fl_mem[head[PTR_W-2:0]];
    // 分配两个时第二个要跳过一项；alloc_i 为 2 时最高位为 1
    assign pd_o1 = fl_mem[head[PTR_W-2:0] + alloc_i[1]];

    assign empty_o = (head == tail);
    assign full_o  = (head[PTR_W-1] != tail[PTR_W-1]) &&
                     (head[PTR_W-2:0] == tail[PTR_W-2:0]);
    assign count_o = tail - head;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= {PTR_W{1'b0}};
            tail <= TAIL_INIT;
            for (i = 0; i < DEPTH; i = i + 1)
                fl_mem[i] <= (i + NUM_LOGIC) & ((1 << PHYS_W) - 1);
        end else begin
            head <= head + alloc_i;
            // free_en_i 是逐位使能，11 表示回收两个，不能直接当数值 3 加
            tail <= tail + {4'b0, free_en_i[0]} + {4'b0, free_en_i[1]};
            if (free_en_i[0])
                fl_mem[tail[PTR_W-2:0]] <= free_i0;
            if (free_en_i[1])
                fl_mem[tail[PTR_W-2:0] + free_en_i[0]] <= free_i1;
        end
    end
endmodule
