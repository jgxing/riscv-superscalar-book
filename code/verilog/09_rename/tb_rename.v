`timescale 1ns/1ps
module tb_rename;
    reg clk = 1'b0;
    reg rst_n = 1'b1;
    reg [1:0] wen_i;
    reg [4:0] rd_i0, rd_i1, rs1_i0, rs2_i0, rs1_i1, rs2_i1;
    reg [1:0] free_en_i;
    reg [5:0] free_i0, free_i1;

    wire [5:0] pd_o0, pd_o1, ps1_o0, ps2_o0, ps1_o1, ps2_o1;
    wire [5:0] old_pd_o0, old_pd_o1;
    wire [5:0] free_cnt;
    wire stall_o;

    rename dut (
        .clk(clk), .rst_n(rst_n),
        .wen_i(wen_i),
        .rd_idx_i0(rd_i0), .rd_idx_i1(rd_i1),
        .rs1_idx_i0(rs1_i0), .rs2_idx_i0(rs2_i0),
        .rs1_idx_i1(rs1_i1), .rs2_idx_i1(rs2_i1),
        .free_en_i(free_en_i), .free_i0(free_i0), .free_i1(free_i1),
        .pd_o0(pd_o0), .pd_o1(pd_o1),
        .ps1_o0(ps1_o0), .ps2_o0(ps2_o0),
        .ps1_o1(ps1_o1), .ps2_o1(ps2_o1),
        .old_pd_o0(old_pd_o0), .old_pd_o1(old_pd_o1),
        .free_cnt_o(free_cnt), .stall_o(stall_o)
    );

    integer n = 0, errors = 0, i;

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
        input [1:0] w;
        input [4:0] r0, r1, a0, b0, a1, b1;
        input [1:0] fe;
        input [5:0] f0, f1;
        begin
            wen_i = w;
            rd_i0 = r0;   rd_i1 = r1;
            rs1_i0 = a0;  rs2_i0 = b0;
            rs1_i1 = a1;  rs2_i1 = b1;
            free_en_i = fe;
            free_i0 = f0; free_i1 = f1;
        end
    endtask

    initial begin
        // 复位后的初始映射：Ri 对应 Pi，空闲表满
        rst_n = 1'b0;
        drive(2'b00, 5'd0,5'd0, 5'd2,5'd3, 5'd5,5'd6, 2'b00, 6'd0,6'd0);
        tick;
        rst_n = 1'b1;
        #1;
        chk(ps1_o0 == 6'd2, "reset: RAT[R2] = P2");
        chk(ps2_o0 == 6'd3, "reset: RAT[R3] = P3");
        chk(ps1_o1 == 6'd5, "reset: RAT[R5] = P5");
        chk(old_pd_o0 == 6'd0, "reset: RAT[R0] = P0");
        chk(free_cnt == 6'd32, "reset: 32 free registers");
        chk(!stall_o, "reset: no stall");

        // U1 MUL R1,R2,R3：分到 P32，源操作数保持 R2/R3 的初值
        drive(2'b01, 5'd1,5'd0, 5'd2,5'd3, 5'd0,5'd0, 2'b00, 6'd0,6'd0);
        #1;
        chk(pd_o0 == 6'd32, "U1: allocate P32");
        chk(ps1_o0 == 6'd2 && ps2_o0 == 6'd3, "U1: sources read old mapping");
        chk(old_pd_o0 == 6'd1, "U1: old R1 mapping is P1");
        tick;
        chk(free_cnt == 6'd31, "U1: free count 31");

        // U2 ADD R4,R1,R5：读 R1 应得到 P32
        drive(2'b01, 5'd4,5'd0, 5'd1,5'd5, 5'd0,5'd0, 2'b00, 6'd0,6'd0);
        #1;
        chk(pd_o0 == 6'd33, "U2: allocate P33");
        chk(ps1_o0 == 6'd32, "U2: R1 renamed to P32");
        chk(old_pd_o0 == 6'd4, "U2: old R4 mapping is P4");
        tick;
        chk(free_cnt == 6'd30, "U2: free count 30");

        // 同组两条：第一条写 R1 得 P34，第二条读 R1 应立刻看到 P34
        drive(2'b11, 5'd1,5'd4, 5'd9,5'd10, 5'd1,5'd5, 2'b00, 6'd0,6'd0);
        #1;
        chk(pd_o0 == 6'd34 && pd_o1 == 6'd35, "group: allocate P34 and P35");
        chk(ps1_o1 == 6'd34, "group: second uop sees first result");
        chk(ps2_o1 == 6'd5, "group: R5 keeps its old mapping");
        chk(old_pd_o0 == 6'd32, "group: old R1 mapping is P32");
        chk(old_pd_o1 == 6'd33, "group: old R4 mapping is P33");
        tick;
        chk(free_cnt == 6'd28, "group: free count 28");

        // 提交回收旧映射 P32 和 P33
        drive(2'b00, 5'd0,5'd0, 5'd0,5'd0, 5'd0,5'd0, 2'b11, 6'd32,6'd33);
        tick;
        chk(free_cnt == 6'd30, "commit: free P32 and P33");

        // 新一轮分配拿到 P36/P37
        drive(2'b11, 5'd6,5'd7, 5'd0,5'd0, 5'd0,5'd0, 2'b00, 6'd0,6'd0);
        #1;
        chk(pd_o0 == 6'd36 && pd_o1 == 6'd37, "alloc: fresh P36 and P37");
        tick;
        chk(free_cnt == 6'd28, "alloc: free count 28");

        // 一直分配到只剩一个空闲项
        for (i = 0; i < 27; i = i + 1) begin
            drive(2'b01, 5'd8,5'd0, 5'd0,5'd0, 5'd0,5'd0, 2'b00, 6'd0,6'd0);
            #1;
            if (stall_o) begin
                $display("FAIL drain: unexpected stall");
                errors = errors + 1;
            end
            tick;
        end
        chk(free_cnt == 6'd1, "drain: one free register left");

        // 只剩一个却要两个，背压信号应拉起
        drive(2'b11, 5'd8,5'd9, 5'd0,5'd0, 5'd0,5'd0, 2'b00, 6'd0,6'd0);
        #1;
        chk(stall_o, "stall: two requests with one free register");
        drive(2'b01, 5'd8,5'd0, 5'd0,5'd0, 5'd0,5'd0, 2'b00, 6'd0,6'd0);
        #1;
        chk(!stall_o, "no stall for a single request");
        tick;
        chk(free_cnt == 6'd0, "empty: free list drained");

        if (errors == 0) $display("ALL TESTS PASSED (%0d checks)", n);
        else $display("%0d TESTS FAILED", errors);
        $finish;
    end
endmodule
