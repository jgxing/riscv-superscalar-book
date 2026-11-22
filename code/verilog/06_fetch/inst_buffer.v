// ============================================================
// 第 6 章 指令缓冲队列
// 每个格子存一个"包裹": 指令字 + 预译码位, 两者同进同出
// 与第 4 章 FTQ 的区别: FTQ 存地址(标量), 这里存捆绑的一组信号
// ============================================================

module inst_buffer #(
    parameter DEPTH    = 8,     // 队列深度
    parameter DATA_W   = 32,    // 指令字宽度
    parameter PREDEC_W = 4      // 预译码位宽度
)(
    input                   clk,
    input                   rst_n,

    // 写端口: 取指单元写入包裹
    input                   push,
    input  [DATA_W-1:0]     push_inst,
    input  [PREDEC_W-1:0]   push_predec,

    // 读端口: 译码/后端读出包裹
    input                   pop,
    output [DATA_W-1:0]     pop_inst,
    output [PREDEC_W-1:0]   pop_predec,

    // 状态标志
    output                  full,
    output                  empty
);
    // ---------- 内部参数 ----------
    // 指针多留一位用于区分空满
    localparam PTR_W = $clog2(DEPTH) + 1;
    // 存储器上界先转 localparam (iverilog 不接受 [0:DEPTH-1] 直接声明)
    localparam DM    = DEPTH - 1;

    // ---------- 存储体 ----------
    // 两个数组用同一个下标访问, 保证指令字与预译码位不拆家
    reg [DATA_W-1:0]   inst_mem  [0:DM];
    reg [PREDEC_W-1:0] predec_mem [0:DM];

    reg [PTR_W-1:0] head, tail;   // head 读指针, tail 写指针

    wire [PTR_W-1:0] next_tail = tail + 1'b1;
    wire [PTR_W-1:0] next_head = head + 1'b1;

    // ---------- 空满标志 ----------
    // 空: 读写指针完全相同
    assign empty = (head == tail);
    // 满: 用当前 tail 判断——写满一圈后 tail 比 head 多绕一圈,
    //     最高位翻转而其余位相同。这样深度才是完整的 DEPTH
    //     (若改用 next_tail 判断, 会提前一格报满, 实际深度只剩 DEPTH-1)
    assign full  = (head[PTR_W-1]   != tail[PTR_W-1])
                && (head[PTR_W-2:0] == tail[PTR_W-2:0]);

    // ---------- 读数据(组合) ----------
    // 索引只取低位, 不能用完整 head (写满时 head 可能 = DEPTH 而越界)
    assign pop_inst   = inst_mem [head[PTR_W-2:0]];
    assign pop_predec = predec_mem[head[PTR_W-2:0]];

    // ---------- 写指针推进(时序) ----------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= {PTR_W{1'b0}};
            tail <= {PTR_W{1'b0}};
        end else begin
            // push 与 pop 两个 if 并列: 读写同拍时各走各的指针
            if (push && !full) begin
                inst_mem [tail[PTR_W-2:0]] <= push_inst;
                predec_mem[tail[PTR_W-2:0]] <= push_predec;
                tail <= next_tail;
            end
            if (pop && !empty) begin
                head <= next_head;
            end
        end
    end

endmodule
