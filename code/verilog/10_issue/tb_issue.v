`timescale 1ns/1ps
module tb_issue;
    reg clk = 1'b0;
    reg rst_n = 1'b1;
    reg [1:0] alloc_en_i;
    reg [3:0] alloc_slot_i0, alloc_slot_i1;
    reg [31:0] alloc_uop_i0, alloc_uop_i1;
    reg [1:0] wakeup_en_i;
    reg [5:0] wakeup_pd_i0, wakeup_pd_i1;
    reg [1:0] unit_free_i;

    wire [3:0] grant0_o, grant1_o, grant_o, busy_o;
    wire [31:0] issue_uop_o0, issue_uop_o1;

    issue_queue dut (
        .clk(clk), .rst_n(rst_n),
        .alloc_en_i(alloc_en_i),
        .alloc_slot_i0(alloc_slot_i0), .alloc_slot_i1(alloc_slot_i1),
        .alloc_uop_i0(alloc_uop_i0), .alloc_uop_i1(alloc_uop_i1),
        .wakeup_en_i(wakeup_en_i),
        .wakeup_pd_i0(wakeup_pd_i0), .wakeup_pd_i1(wakeup_pd_i1),
        .unit_free_i(unit_free_i),
        .grant0_o(grant0_o), .grant1_o(grant1_o), .grant_o(grant_o),
        .issue_uop_o0(issue_uop_o0), .issue_uop_o1(issue_uop_o1),
        .busy_o(busy_o)
    );

    integer n = 0, errors = 0;

    function [31:0] mk;
        input [1:0] t;
        input r1, r2;
        input [5:0] s1, s2, d;
        input [7:0] a;
        begin
            mk = {t, r1, r2, s1, s2, d, a, 2'b0};
        end
    endfunction

    task chk;
        input ok;
        input [1023:0] msg;
        begin
            n = n + 1;
            if (ok) $display("PASS %0d  %0s", n, msg);
            else begin
                $display("FAIL %0d  %0s", n, msg);
                errors = errors + 1;
            end
        end
    endtask

    task tick;
        begin
            #1 clk = 1'b0;
            #1 clk = 1'b1;
            #1;
        end
    endtask

    task drive;
        input [1:0] ae;
        input [3:0] s0, s1;
        input [31:0] u0, u1;
        input [1:0] we;
        input [5:0] w0, w1;
        input [1:0] uf;
        begin
            alloc_en_i = ae;
            alloc_slot_i0 = s0; alloc_slot_i1 = s1;
            alloc_uop_i0 = u0;  alloc_uop_i1 = u1;
            wakeup_en_i = we;
            wakeup_pd_i0 = w0;  wakeup_pd_i1 = w1;
            unit_free_i = uf;
        end
    endtask

    initial begin
        // 复位
        rst_n = 1'b0;
        drive(2'b00, 4'b0000,4'b0000, 32'd0,32'd0, 2'b00, 6'd0,6'd0, 2'b00);
        tick;
        rst_n = 1'b1;
        #1;
        chk(busy_o == 4'b0000, "reset: all entries empty");
        chk(grant_o == 4'b0000, "reset: no grant");

        // 放进 E0（等 P10）和 E2（就绪且最老）
        drive(2'b11, 4'b0001,4'b0100,
              mk(2'd0,1'b0,1'b1,6'd10,6'd2,6'd11,8'd1),
              mk(2'd0,1'b1,1'b1,6'd5,6'd6,6'd7,8'd0),
              2'b00, 6'd0,6'd0, 2'b00);
        tick;
        chk(busy_o == 4'b0101, "alloc: E0 and E2 busy");
        drive(2'b00, 4'b0000,4'b0000, 32'd0,32'd0,
              2'b00, 6'd0,6'd0, 2'b01);
        #1;
        chk(grant_o == 4'b0100, "one port: oldest ready E2 wins");

        // 再放进 E1，年龄比 E2 大；分配这拍仍不让发射口生效
        drive(2'b01, 4'b0010,4'b0000,
              mk(2'd0,1'b1,1'b1,6'd3,6'd4,6'd8,8'd2), 32'd0,
              2'b00, 6'd0,6'd0, 2'b00);
        tick;
        chk(busy_o == 4'b0111, "alloc: E1 busy too");
        drive(2'b00, 4'b0000,4'b0000, 32'd0,32'd0,
              2'b00, 6'd0,6'd0, 2'b01);
        #1;
        chk(grant_o == 4'b0100, "one port: E2 still wins");
        drive(2'b00, 4'b0000,4'b0000, 32'd0,32'd0,
              2'b00, 6'd0,6'd0, 2'b11);
        #1;
        chk(grant_o == 4'b0110, "two ports: E2 and E1 granted");
        chk(grant0_o == 4'b0100 && grant1_o == 4'b0010, "grant order follows age");

        // 发射出去
        tick;
        chk(busy_o == 4'b0001, "issue: E2 and E1 leave the queue");

        // 广播 P10 唤醒 E0
        drive(2'b00, 4'b0000,4'b0000, 32'd0,32'd0,
              2'b01, 6'd10,6'd0, 2'b11);
        tick;
        chk(grant_o == 4'b0001, "wakeup: P10 makes E0 ready");
        drive(2'b00, 4'b0000,4'b0000, 32'd0,32'd0,
              2'b00, 6'd0,6'd0, 2'b11);
        tick;
        chk(busy_o == 4'b0000, "issue: E0 leaves after wakeup");

        // 没有空闲发射口时不发授权
        drive(2'b01, 4'b0010,4'b0000,
              mk(2'd0,1'b1,1'b1,6'd30,6'd31,6'd32,8'd3), 32'd0,
              2'b00, 6'd0,6'd0, 2'b00);
        tick;
        chk(grant_o == 4'b0000, "no free unit: no grant");
        drive(2'b00, 4'b0000,4'b0000, 32'd0,32'd0,
              2'b00, 6'd0,6'd0, 2'b11);
        #1;
        chk(grant_o == 4'b0010, "free unit appears: E1 granted");
        tick;
        chk(busy_o == 4'b0000, "issue: E1 leaves");

        // 两路广播同拍唤醒一项的两个源
        drive(2'b01, 4'b0001,4'b0000,
              mk(2'd0,1'b0,1'b0,6'd20,6'd21,6'd22,8'd4), 32'd0,
              2'b00, 6'd0,6'd0, 2'b11);
        tick;
        drive(2'b00, 4'b0000,4'b0000, 32'd0,32'd0,
              2'b11, 6'd20,6'd21, 2'b11);
        tick;
        chk(grant_o == 4'b0001, "two broadcasts wake both sources");
        drive(2'b00, 4'b0000,4'b0000, 32'd0,32'd0,
              2'b00, 6'd0,6'd0, 2'b11);
        tick;
        chk(busy_o == 4'b0000, "issue: double-woken entry leaves");

        // 只有一个就绪项时第二个授权必须为空
        drive(2'b01, 4'b0010,4'b0000,
              mk(2'd0,1'b1,1'b1,6'd40,6'd41,6'd42,8'd5), 32'd0,
              2'b00, 6'd0,6'd0, 2'b11);
        tick;
        chk(grant0_o == 4'b0010 && grant1_o == 4'b0000, "single request: second grant empty");

        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", n);
        else $display("%0d TESTS FAILED", errors);
        $finish;
    end
endmodule
