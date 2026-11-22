// 第4章 FTQ testbench
// 覆盖：复位、写至满、满时拒写、读至空、读写同拍
`timescale 1ns/1ps

module tb_ftq;
    parameter DEPTH  = 8;
    parameter ADDR_W = 32;

    reg              clk;
    reg              rst_n;
    reg              push;
    reg              pop;
    reg  [ADDR_W-1:0] push_addr;
    wire             full;
    wire             empty;
    wire [ADDR_W-1:0] pop_addr;

    ftq #(.DEPTH(DEPTH), .ADDR_W(ADDR_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .push(push), .push_addr(push_addr), .full(full),
        .pop(pop), .pop_addr(pop_addr), .empty(empty)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer errors = 0;
    reg [1023:0] msg;

    task chk;
        input [1023:0] m;
        input cond;
        begin
            if (cond) $display("PASS: %0s", m);
            else begin $display("FAIL: %0s", m); errors = errors + 1; end
        end
    endtask

    // 写一个地址，返回一个周期
    task do_push;
        input [ADDR_W-1:0] a;
        begin
            push = 1'b1; pop = 1'b0; push_addr = a;
            #10;
        end
    endtask

    // 读一个地址并检查，返回一个周期
    task do_pop_check;
        input [ADDR_W-1:0] exp_addr;
        begin
            push = 1'b0; pop = 1'b1;
            #10;
            if (pop_addr === exp_addr)
                $display("PASS: pop got 0x%h", exp_addr);
            else begin
                $display("FAIL: pop expected 0x%h, got 0x%h", exp_addr, pop_addr);
                errors = errors + 1;
            end
        end
    endtask

    integer k;
    initial begin
        $display("==== Chapter 4 FTQ tests ====");

        // --- 复位 ---
        rst_n = 1'b0; push = 1'b0; pop = 1'b0; push_addr = {ADDR_W{1'b0}};
        #10;
        rst_n = 1'b1;
        #10;
        chk("after reset: empty=1", empty === 1'b1);
        chk("after reset: full=0",  full  === 1'b0);

        // --- 连续写入至满 ---
        for (k = 0; k < DEPTH; k = k + 1) begin
            do_push(32'h100 + k*4);
            if (k < DEPTH-1)
                chk("not full before last write", full === 1'b0);
        end
        chk("after DEPTH writes: full=1", full === 1'b1);
        chk("after DEPTH writes: empty=0", empty === 1'b0);

        // --- 满时拒写 ---
        do_push(32'h200);
        chk("write while full keeps full=1", full === 1'b1);

        // --- 读出至空，验证 FIFO 顺序 ---
        for (k = 0; k < DEPTH; k = k + 1)
            do_pop_check(32'h100 + k*4);
        chk("after DEPTH reads: empty=1", empty === 1'b1);
        chk("after DEPTH reads: full=0",  full  === 1'b0);

        // --- 读写同拍 ---
        for (k = 0; k < 4; k = k + 1)
            do_push(32'h300 + k*4);   // 先装 4 个

        push = 1'b1; pop = 1'b1;
        for (k = 0; k < 4; k = k + 1) begin
            push_addr = 32'h400 + k*4;
            #10;
            if (pop_addr === (32'h300 + k*4))
                $display("PASS: same-cycle pop got 0x%h", 32'h300 + k*4);
            else begin
                $display("FAIL: same-cycle pop expected 0x%h, got 0x%h",
                         32'h300 + k*4, pop_addr);
                errors = errors + 1;
            end
            chk("same-cycle: neither full nor empty", (full === 1'b0) && (empty === 1'b0));
        end

        push = 1'b0; pop = 1'b0;
        #10;
        for (k = 0; k < 4; k = k + 1)
            do_pop_check(32'h400 + k*4);
        chk("after same-cycle test: empty=1", empty === 1'b1);

        // --- 结果 ---
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("==== %0d ERRORS ====", errors);
        $finish;
    end
endmodule
