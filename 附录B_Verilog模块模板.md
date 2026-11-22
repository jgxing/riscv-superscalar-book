# 附录 B　Verilog 简化模块模板

这一章把全书反复用到的五个基础构件集中列出来。它们都是参数化的，可以直接拿去用，也可以按需要改。每个模块先讲接口怎么来的，再讲实现里要注意的地方，最后给完整代码。所有代码都在 `code/verilog/appendix_b/`，仿真 28 项全过。

![图B-1 五个模板模块在核里的位置](../figures/figB-1-module-map.svg)

*图B-1　五个模板模块在核里的位置*

## B.1 同步 FIFO

### 它要解决什么问题

处理器里到处是队列。取指目标队列、指令缓冲、发射队列、重排序缓冲，本质上都是先进先出的存储。写一个通用的 FIFO，以后碰到队列就改个参数拿来用。

### 接口怎么来

先想写入这一侧。生产者要给出写入使能和数据。

```verilog
    input  wire             push_i,
    input  wire [DATA_W-1:0] push_data_i,
```

再看读取这一侧。消费者给读出使能，队列吐出数据。

```verilog
    input  wire             pop_i,
    output reg  [DATA_W-1:0] pop_data_o,
```

光能读写还不够。生产者写之前得知道满没满，消费者读之前得知道空没空，于是补上两个状态信号。

```verilog
    output wire             full_o,
    output wire             empty_o
```

最后补上时钟和复位。存跨拍状态，一定要有时钟；要能回到初始状态，一定要有复位。

```verilog
    input  wire             clk,
    input  wire             rst_n,
```

接口就齐了。深度和数据位宽用参数表示，改一个数字就能得到不同规格的队列。

### 实现里要注意什么

第一件事是怎么判满判空。最直接的办法是记一个计数值，但那样要多一个计数器。更省事的是用两个指针，head 指向队头，tail 指向队尾。两者相等时是空。可是写满一圈后 tail 又会追上 head，空和满就分不清了。

解法是多给指针一位。深度 8 的队列，下标只要 3 位，指针却用 4 位。tail 比 head 多绕一整圈时，最高位不同、低位相同，这就是满。

```verilog
    assign empty_o = (head == tail);
    // 判满：最高位不同、其余位相同。用当前 tail，不是 next_tail
    assign full_o  = (head[PTR_W-1] != tail[PTR_W-1]) &&
                     (head[PTR_W-2:0] == tail[PTR_W-2:0]);
```

这里用的是当前 tail，不是加一之后的 tail。用加一后的值判满，深度会平白少一格，这是第 6 章踩过的坑。

第二件事是怎么索引存储器。多出来的最高位只用于判满，不能拿去当数组下标。写满时指针会走到 8，用 4 位指针直接索引深度 8 的数组就越界了，仿真器会读出 x，而且症状很隐蔽。

```verilog
                // 索引必须取低位，写满时完整指针会越过数组边界
                mem[tail[PTR_W-2:0]] <= push_data_i;
```

第三件事是指针宽度怎么算。写一个固定值当然省事，但换个深度就要改。用系统函数算最稳妥。

```verilog
    localparam PTR_W    = $clog2(DEPTH) + 1;  // 下标位数多留 1 位判满
    localparam DEPTH_M1 = DEPTH - 1;  // iverilog 不接受数组上界直接写参数表达式
```

指针位数取深度的对数再加一。数组上界不能直接在方括号里写参数表达式，先转成 `localparam`，这是仿真器的要求。

### 完整代码

```verilog
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
```

读写同拍时各走各的指针，一个推进 tail，一个推进 head，互不干扰。复位时用循环把整个存储器清零，仿真波形才干净。

## B.2 内容寻址存储器 CAM

### 它要解决什么问题

普通存储器给地址，读出那个单元的内容。CAM 反过来，给一个内容，问它在哪几个单元里。保留站监听 CDB 广播时，每条表项都在问"广播的物理号是不是我等的那个"；BTB 查表时，也在问"哪个表项的标签和当前 PC 对得上"。这些动作都是 CAM。

### 接口怎么来

先要有查询的 key，还要有被查的整张表。表项很多，跨模块传递时用打包向量，N 项每项 KEY_W 位，拼成 N*KEY_W 位。

```verilog
    input  wire [KEY_W-1:0]    key_i,
    input  wire [N*KEY_W-1:0]  table_i,   // N 个表项打包成一位向量
    input  wire [N-1:0]        valid_i,
```

光知道哪项命中还不够，还得知道位置，好去读对应的表项或者发出选择信号。

```verilog
    output wire [N-1:0]        match_o,   // 每项是否相等
    output reg                 hit_o,     // 有没有任一项命中
    output reg  [2:0]          index_o    // 命中项编号，N<=8 用 3 位
```

`match_o` 保留逐项的相等结果，`index_o` 给出编号。多数时候用 `index_o` 就够了，保留 `match_o` 是为了调试时能看到到底哪几项命中。

### 实现里要注意什么

并行比较用 generate 循环展开。每一项先检查有效位，再比内容。注意 `+:` 位选的写法，它从起始位往上取 KEY_W 位。

```verilog
    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : cmp
            assign eq[g] = valid_i[g] &&
                           (table_i[g*KEY_W +: KEY_W] == key_i);
        end
    endgenerate
```

无效的表项即便内容一样也不算命中。这一位有效位很关键，否则存储器里残留的旧值会造成假命中。

多项同时命中时取编号最小的那个，和仲裁器挑最老的是一个道理。

```verilog
    // 多项同时命中时取编号最小的那个，和仲裁器的"最老优先"一个道理
    always @* begin
        hit_o   = 1'b0;
        index_o = 3'd0;
        for (i = 0; i < N; i = i + 1)
            if (eq[i] && !hit_o) begin
                hit_o   = 1'b1;
                index_o = i[2:0];
            end
    end
```

循环里用 `!hit_o` 锁定第一个命中项，后面再命中也不覆盖。位宽写死 3 位是因为教学核里这类表最多 8 项，改成更大的表要相应加宽。

### 完整代码

```verilog
// 内容寻址存储器 CAM：给一个 key，并行查所有表项，返回命中和位置
// 发射队列的源操作数监听、TLB、分支目标表都用到这个动作
module cam #(
    parameter N     = 8,
    parameter KEY_W = 6
)(
    input  wire [KEY_W-1:0]    key_i,
    input  wire [N*KEY_W-1:0]  table_i,   // N 个表项打包成一位向量
    input  wire [N-1:0]        valid_i,
    output wire [N-1:0]        match_o,   // 每项是否相等
    output reg                 hit_o,     // 有没有任一项命中
    output reg  [2:0]          index_o    // 命中项编号，N<=8 用 3 位
);
    wire [N-1:0] eq;
    integer i;

    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : cmp
            assign eq[g] = valid_i[g] &&
                           (table_i[g*KEY_W +: KEY_W] == key_i);
        end
    endgenerate

    assign match_o = eq;

    // 多项同时命中时取编号最小的那个，和仲裁器的"最老优先"一个道理
    always @* begin
        hit_o   = 1'b0;
        index_o = 3'd0;
        for (i = 0; i < N; i = i + 1)
            if (eq[i] && !hit_o) begin
                hit_o   = 1'b1;
                index_o = i[2:0];
            end
    end
endmodule
```

## B.3 优先编码器

### 它要解决什么问题

CAM 给出的是独热信号，比如 `8'b00000100`，表示第 2 项命中。可后续电路要的是一个编号，`3'd2`。把独热信号变成二进制编号，就是优先编码器的活。中断控制器从一堆请求里挑最高优先级，用的也是同一个电路。

### 接口怎么来

输入是一组请求，输出是有效位和编号。

```verilog
    input  wire [N-1:0]     req_i,
    output reg              valid_o,
    output reg  [2:0]       code_o    // N<=8 用 3 位
```

### 实现里要注意什么

从低位往高位扫，第一个置位的锁定下来，后面再置位也不覆盖。这样编号最小的请求优先级最高。

```verilog
    reg found;
    integer i;

    always @* begin
        found  = 1'b0;
        code_o = 3'd0;
        // 从低到扫，第一个命中的锁定下来，后面再命中也不覆盖
        for (i = 0; i < N; i = i + 1)
            if (req_i[i] && !found) begin
                found  = 1'b1;
                code_o = i[2:0];
            end
        valid_o = found;
    end
```

这里有个容易错的地方。不能拿 `valid_o` 直接当锁定标志，因为如果在循环开始前先算了 `valid_o = |req_i`，那只要有一个请求，它一开始就是 1，循环里的 `!valid_o` 永远不成立。要另设一个初值为 0 的临时变量 `found`，最后再赋给 `valid_o`。

### 完整代码

```verilog
// 优先编码器：从一组请求里找出编号最小的置位，输出它的二进制编码
// CAM 命中后要给出位置、中断控制器挑最高优先级，都靠它
module priority_encoder #(
    parameter N = 8
)(
    input  wire [N-1:0]     req_i,
    output reg              valid_o,
    output reg  [2:0]       code_o    // N<=8 用 3 位
);
    reg found;
    integer i;

    always @* begin
        found  = 1'b0;
        code_o = 3'd0;
        // 从低到扫，第一个命中的锁定下来，后面再命中也不覆盖
        for (i = 0; i < N; i = i + 1)
            if (req_i[i] && !found) begin
                found  = 1'b1;
                code_o = i[2:0];
            end
        valid_o = found;
    end
endmodule
```

## B.4 仲裁器

### 它要解决什么问题

好几个请求同时要用一个端口，只能放行一部分。仲裁器决定放谁。第 10 章的发射队列每拍最多发射两条，就是仲裁器在发票。

### 接口怎么来

先有请求，再有每个请求的优先级。优先级用年龄表示，数越小越老，越老越先走。

```verilog
    input  wire [N-1:0]         req_i,
    input  wire [N*AGE_W-1:0]   age_i,     // 每项年龄，数越小越老
    input  wire [1:0]           limit_i,   // 最多批几个：0、1 或 2
```

然后是两个票和总放行信号。分成两张票，是为了后续电路能分别处理第一选择和第二选择。

```verilog
    output wire [N-1:0]         grant0_o,  // 第一张票
    output wire [N-1:0]         grant1_o,  // 第二张票
    output wire [N-1:0]         grant_o
```

### 实现里要注意什么

关键是比较年龄，不是比较编号。编号小的表项不一定更老，队列项是循环使用的。先找年龄最小的发第一张票。

```verilog
        // 第一张票给年龄最小的请求
        g0   = {N{1'b0}};
        best = {AGE_W{1'b1}};
        for (i = 0; i < N; i = i + 1)
            if (req_i[i] && (age_i[i*AGE_W +: AGE_W] < best)) begin
                best = age_i[i*AGE_W +: AGE_W];
                g0   = {N{1'b0}};
                g0[i] = 1'b1;
            end
```

`best` 初值设成全 1，保证第一个有效请求一定能入选。每找到一个更老的，就清掉之前的票。第二张票在剩下的请求里同样挑最老的，判断条件多一项 `!g0[i]`，避免同一项拿两张票。

`limit_i` 控制一拍最多放行几个，取 0 就一张都不发，取 1 就只发第一张。

### 完整代码

```verilog
// 仲裁器：N 个请求里按优先级挑出最多两个，给出发票
// 第10章发射队列用的就是它，优先级由输入的 age 决定
module arbiter #(
    parameter N     = 4,
    parameter AGE_W = 8
)(
    input  wire [N-1:0]         req_i,
    input  wire [N*AGE_W-1:0]   age_i,     // 每项年龄，数越小越老
    input  wire [1:0]           limit_i,   // 最多批几个：0、1 或 2
    output wire [N-1:0]         grant0_o,  // 第一张票
    output wire [N-1:0]         grant1_o,  // 第二张票
    output wire [N-1:0]         grant_o
);
    reg [N-1:0]       g0, g1;
    reg [AGE_W-1:0]   best;
    integer i;

    always @* begin
        // 第一张票给年龄最小的请求
        g0   = {N{1'b0}};
        best = {AGE_W{1'b1}};
        for (i = 0; i < N; i = i + 1)
            if (req_i[i] && (age_i[i*AGE_W +: AGE_W] < best)) begin
                best = age_i[i*AGE_W +: AGE_W];
                g0   = {N{1'b0}};
                g0[i] = 1'b1;
            end

        // 第二张票在剩下的请求里同样挑最老的
        g1   = {N{1'b0}};
        best = {AGE_W{1'b1}};
        for (i = 0; i < N; i = i + 1)
            if (req_i[i] && !g0[i] && (age_i[i*AGE_W +: AGE_W] < best)) begin
                best = age_i[i*AGE_W +: AGE_W];
                g1   = {N{1'b0}};
                g1[i] = 1'b1;
            end

        // limit 限制一拍最多放行几个
        if (limit_i == 2'd0) begin
            g0 = {N{1'b0}};
            g1 = {N{1'b0}};
        end else if (limit_i == 2'd1) begin
            g1 = {N{1'b0}};
        end
    end

    assign grant0_o = g0;
    assign grant1_o = g1;
    assign grant_o  = g0 | g1;
endmodule
```

## B.5 交叉开关

### 它要解决什么问题

仲裁器决定谁先走，交叉开关负责把选中的数据送到正确的出口。执行结果写回时，多个功能部件可能同时出结果，要按目的物理寄存器送到对应端口；旁路网络里，多个广播源要选一个送进 ALU 的输入。这些都是交叉开关。

### 接口怎么来

每一路输入要有请求、目标号和数据。目标号告诉它想去哪个出口。三样东西都用打包向量传。

```verilog
    input  wire [N-1:0]             req_i,     // 每个输入有没有请求
    input  wire [N*2-1:0]           dst_i,     // 每个输入的目标号，N<=4 用 2 位
    input  wire [N*DATA_W-1:0]      data_i,    // N 路输入数据打包
```

输出是送到位的数据和每路的有效位。

```verilog
    output reg  [N*DATA_W-1:0]      data_o,    // N 路输出数据打包
    output reg  [N-1:0]             valid_o    // 每个输出有没有拿到数据
```

### 实现里要注意什么

对每个出口，遍历所有输入，找出指向它且编号最小的那一路。编号小的优先，这是最简单的冲突处理办法。

```verilog
            for (in_j = 0; in_j < N; in_j = in_j + 1) begin
                if (req_i[in_j] &&
                    (dst_i[in_j*2 +: 2] == out_k[1:0]) &&
                    !valid_o[out_k]) begin
                    valid_o[out_k] = 1'b1;
                    data_o[out_k*DATA_W +: DATA_W] = data_i[in_j*DATA_W +: DATA_W];
                end
            end
```

每个出口在开始遍历前先清零，`valid_o[out_k]` 一旦置位就不再被覆盖，于是留下编号最小的输入。没有输入指向的出口保持零。

目标号在这里写死 2 位，对应 N 不超过 4。路数更多时要相应加宽，并且把 `out_k[1:0]` 改成足够宽的位选。

### 完整代码

```verilog
// 交叉开关 crossbar：N 个输入按需路由到 N 个输出
// 每个输入带上想去的输出号，输出侧从所有指向自己的输入里选一个
// 冲突时编号小的输入优先，这是最简单的仲裁策略
module crossbar #(
    parameter N      = 4,
    parameter DATA_W = 32
)(
    input  wire [N-1:0]             req_i,     // 每个输入有没有请求
    input  wire [N*2-1:0]           dst_i,     // 每个输入的目标号，N<=4 用 2 位
    input  wire [N*DATA_W-1:0]      data_i,    // N 路输入数据打包
    output reg  [N*DATA_W-1:0]      data_o,    // N 路输出数据打包
    output reg  [N-1:0]             valid_o    // 每个输出有没有拿到数据
);
    integer out_k, in_j;

    always @* begin
        for (out_k = 0; out_k < N; out_k = out_k + 1) begin
            valid_o[out_k] = 1'b0;
            data_o[out_k*DATA_W +: DATA_W] = {DATA_W{1'b0}};
            // 遍历所有输入，找指向本输出且编号最小的那个
            for (in_j = 0; in_j < N; in_j = in_j + 1) begin
                if (req_i[in_j] &&
                    (dst_i[in_j*2 +: 2] == out_k[1:0]) &&
                    !valid_o[out_k]) begin
                    valid_o[out_k] = 1'b1;
                    data_o[out_k*DATA_W +: DATA_W] = data_i[in_j*DATA_W +: DATA_W];
                end
            end
        end
    end
endmodule
```

## B.6 运行自测

五个模块的自测程序在 `tb_appendix_b.v`，覆盖复位、写满、满时拒写、读写同拍、CAM 命中未命中、多项命中取小编号、优先编码、仲裁限流、交叉开关路由与冲突。

```bash
iverilog -g2012 -o sim.vvp *.v
vvp sim.vvp
```

跑完会打印 28 项 PASS。

## 小结

- FIFO 用多一位指针判满判空，索引存储器只取低位。
- CAM 并行比较返回独热命中位，有效位防止旧值假命中，优先编码器把独热位变成编号。
- 仲裁器按年龄发票，不按表项编号；limit 控制一拍放行几条。
- 交叉开关按目标号路由，冲突时编号小的输入优先。
- 跨模块传多个同类数据用打包向量和 `+:` 位选；打包向量最右端是 0 号单元。

## 思考题

1. 把 FIFO 的判满条件改成用 `next_tail`，仿真看深度变成多少，解释原因。
2. CAM 里如果去掉有效位判断，存储器中的旧值会造成什么问题？设计一个场景让这个错误现形。
3. 优先编码器里为什么不能用 `valid_o` 当循环内的锁定标志？
4. 仲裁器如果改成按编号发票而不是按年龄，在队列循环使用的场景下会发生什么？
5. 交叉开关里两个输入指向同一出口，当前是编号小的优先。如果要改成轮转优先，需要增加哪些信号？
