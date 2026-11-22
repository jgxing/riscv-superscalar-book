`timescale 1ns/1ps
module tb_lsq;
    reg                 clk;
    reg                 rst_n;

    reg                 alloc_en_i, alloc_is_store_i;
    reg  [7:0]          alloc_age_i;
    reg  [5:0]          alloc_dest_i;
    reg                 st_addr_en_i;
    reg  [2:0]          st_addr_idx_i;
    reg  [31:0]         st_addr_i;
    reg                 st_data_en_i;
    reg  [2:0]          st_data_idx_i;
    reg  [31:0]         st_data_i;
    reg                 ld_en_i;
    reg  [2:0]          ld_idx_i;
    reg  [31:0]         ld_addr_i;

    wire [31:0]         ld_fwd_data_o;
    wire                ld_fwd_hit_o;
    wire [31:0]         ld_addr_o;
    wire [5:0]          ld_dest_o;
    wire                violation_o;
    wire [7:0]          violation_age_o;
    wire [7:0]          busy_o;

    lsq uut (
        .clk(clk), .rst_n(rst_n),
        .alloc_en_i(alloc_en_i), .alloc_is_store_i(alloc_is_store_i),
        .alloc_age_i(alloc_age_i), .alloc_dest_i(alloc_dest_i),
        .st_addr_en_i(st_addr_en_i), .st_addr_idx_i(st_addr_idx_i), .st_addr_i(st_addr_i),
        .st_data_en_i(st_data_en_i), .st_data_idx_i(st_data_idx_i), .st_data_i(st_data_i),
        .ld_en_i(ld_en_i), .ld_idx_i(ld_idx_i), .ld_addr_i(ld_addr_i),
        .ld_fwd_data_o(ld_fwd_data_o), .ld_fwd_hit_o(ld_fwd_hit_o),
        .ld_addr_o(ld_addr_o), .ld_dest_o(ld_dest_o),
        .violation_o(violation_o), .violation_age_o(violation_age_o),
        .busy_o(busy_o)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer total = 0, pass = 0;
    integer i;

    task chk;
        input [1023:0] m;
        input cond;
        begin
            total = total + 1;
            if (cond) begin
                pass = pass + 1;
                $display("PASS %0d: %0s", total, m);
            end else begin
                $display("FAIL %0d: %0s", total, m);
            end
        end
    endtask

    // 底层驱动：13 个输入在一次 negedge 全部更新
    task drive;
        input ae;                 // alloc_en_i
        input ais;                // alloc_is_store_i
        input [7:0] aage;         // alloc_age_i
        input [5:0] adest;        // alloc_dest_i
        input sae;                // st_addr_en_i
        input [2:0] sidx;         // st_addr_idx_i
        input [31:0] saddr;       // st_addr_i
        input sde;                // st_data_en_i
        input [2:0] didx;         // st_data_idx_i
        input [31:0] sdata;       // st_data_i
        input le;                 // ld_en_i
        input [2:0] lidx;         // ld_idx_i
        input [31:0] laddr;       // ld_addr_i
        begin
            @(negedge clk);
            alloc_en_i = ae;          alloc_is_store_i = ais;
            alloc_age_i = aage;       alloc_dest_i = adest;
            st_addr_en_i = sae;       st_addr_idx_i = sidx;    st_addr_i = saddr;
            st_data_en_i = sde;       st_data_idx_i = didx;    st_data_i = sdata;
            ld_en_i = le;             ld_idx_i = lidx;         ld_addr_i = laddr;
            #1;   // 组合输出稳定后再返回，便于检查转发结果
        end
    endtask

    task alloc_uop;
        input ais;
        input [7:0] aage;
        input [5:0] adest;
        begin
            drive(1'b1, ais, aage, adest,
                  1'b0, 3'd0, 32'd0, 1'b0, 3'd0, 32'd0,
                  1'b0, 3'd0, 32'd0);
        end
    endtask

    task store_addr;
        input [2:0] idx;
        input [31:0] a;
        begin
            drive(1'b0, 1'b0, 8'd0, 6'd0,
                  1'b1, idx, a, 1'b0, 3'd0, 32'd0,
                  1'b0, 3'd0, 32'd0);
        end
    endtask

    task store_data;
        input [2:0] idx;
        input [31:0] d;
        begin
            drive(1'b0, 1'b0, 8'd0, 6'd0,
                  1'b0, 3'd0, 32'd0, 1'b1, idx, d,
                  1'b0, 3'd0, 32'd0);
        end
    endtask

    task store_full;
        input [2:0] idx;
        input [31:0] a;
        input [31:0] d;
        begin
            drive(1'b0, 1'b0, 8'd0, 6'd0,
                  1'b1, idx, a, 1'b1, idx, d,
                  1'b0, 3'd0, 32'd0);
        end
    endtask

    task load_read;
        input [2:0] idx;
        input [31:0] a;
        begin
            drive(1'b0, 1'b0, 8'd0, 6'd0,
                  1'b0, 3'd0, 32'd0, 1'b0, 3'd0, 32'd0,
                  1'b1, idx, a);
        end
    endtask

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task do_reset;
        begin
            rst_n = 0;
            repeat (2) @(posedge clk);
            #1;
            rst_n = 1;
        end
    endtask

    initial begin
        alloc_en_i = 1'b0; alloc_is_store_i = 1'b0;
        alloc_age_i = 8'd0; alloc_dest_i = 6'd0;
        st_addr_en_i = 1'b0; st_addr_idx_i = 3'd0; st_addr_i = 32'd0;
        st_data_en_i = 1'b0; st_data_idx_i = 3'd0; st_data_i = 32'd0;
        ld_en_i = 1'b0; ld_idx_i = 3'd0; ld_addr_i = 32'd0;

        do_reset;
        chk("reset: empty queue and no violation",
            (busy_o === 8'd0) && (violation_o === 1'b0));

        // 场景 A：store 先写好，load 读同地址，从 store 转发
        alloc_uop(1'b1, 8'd1, 6'd10); tick;
        chk("A: store allocated to slot 0", busy_o === 8'b00000001);
        alloc_uop(1'b0, 8'd2, 6'd20); tick;
        chk("A: load allocated to slot 1", busy_o === 8'b00000011);
        store_full(3'd0, 32'h100, 32'hAB); tick;
        load_read(3'd1, 32'h100);
        chk("A: forward hit on same address", ld_fwd_hit_o === 1'b1);
        chk("A: forward data is 0xAB", ld_fwd_data_o === 32'hAB);
        chk("A: load dest P20 passes through", ld_dest_o === 6'd20);
        chk("A: load address passes through", ld_addr_o === 32'h100);
        tick;

        // 场景 B：load 先投机读，更老的 store 地址后算出来，发现同址报违例
        alloc_uop(1'b1, 8'd3, 6'd0); tick;
        alloc_uop(1'b0, 8'd4, 6'd21); tick;
        load_read(3'd3, 32'h200);
        chk("B: no forward while older store addr unknown", ld_fwd_hit_o === 1'b0);
        tick;
        store_addr(3'd2, 32'h200); tick;
        chk("B: violation detected", violation_o === 1'b1);
        chk("B: violation age is the load age", violation_age_o === 8'd4);

        // 场景 C：地址不同，不报违例
        alloc_uop(1'b1, 8'd5, 6'd0); tick;
        alloc_uop(1'b0, 8'd6, 6'd22); tick;
        load_read(3'd5, 32'h400); tick;
        store_addr(3'd4, 32'h300); tick;
        chk("C: different address, no violation", violation_o === 1'b0);

        // 场景 D：更年轻的 store 同地址，既不转发也不报违例
        alloc_uop(1'b0, 8'd7, 6'd23); tick;
        load_read(3'd6, 32'h500); tick;
        alloc_uop(1'b1, 8'd8, 6'd0); tick;
        store_full(3'd7, 32'h500, 32'hCD); tick;
        load_read(3'd6, 32'h500);
        chk("D: younger store is not forwarded", ld_fwd_hit_o === 1'b0);
        tick;
        chk("D: younger store causes no violation", violation_o === 1'b0);

        // 场景 E：两个更老的同址 store，转发最年轻的那个
        do_reset;
        chk("E: reset clears queue", busy_o === 8'd0);
        alloc_uop(1'b1, 8'd9, 6'd0); tick;
        store_full(3'd0, 32'h600, 32'h11); tick;
        alloc_uop(1'b1, 8'd10, 6'd0); tick;
        store_full(3'd1, 32'h600, 32'h22); tick;
        alloc_uop(1'b0, 8'd11, 6'd24); tick;
        load_read(3'd2, 32'h600);
        chk("E: forward hit with two older stores", ld_fwd_hit_o === 1'b1);
        chk("E: pick youngest older store 0x22", ld_fwd_data_o === 32'h22);
        tick;

        // 场景 F：store 数据还没到时不能转发
        alloc_uop(1'b1, 8'd12, 6'd0); tick;
        store_addr(3'd3, 32'h700); tick;
        alloc_uop(1'b0, 8'd13, 6'd25); tick;
        load_read(3'd4, 32'h700);
        chk("F: no forward before store data ready", ld_fwd_hit_o === 1'b0);
        tick;
        store_data(3'd3, 32'hEE); tick;
        load_read(3'd4, 32'h700);
        chk("F: forward after store data ready", ld_fwd_data_o === 32'hEE);
        tick;

        // 场景 G：队列满时拒绝入队
        do_reset;
        for (i = 0; i < 8; i = i + 1) begin
            alloc_uop(1'b0, 8'd20 + i[7:0], 6'd0);
            tick;
        end
        chk("G: queue full", busy_o === 8'hFF);
        alloc_uop(1'b0, 8'd99, 6'd0); tick;
        chk("G: alloc rejected when full", busy_o === 8'hFF);

        $display("---- %0d / %0d passed ----", pass, total);
        if (pass == total) $display("ALL TESTS PASSED");
        else               $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
