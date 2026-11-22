`timescale 1ns/1ps
module tb_perf;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [1:0] commit_i = 2'd0;
    reg front_stall_i = 1'b0;
    reg issue_stall_i = 1'b0;
    reg lsq_stall_i = 1'b0;
    reg recover_i = 1'b0;

    wire [31:0] cycle_o, commit_o;
    wire [31:0] front_stall_o, issue_stall_o, lsq_stall_o, recover_o;
    wire [1:0] bottleneck_o;
    wire stall_any_o;
    wire [31:0] ipc_num_o, ipc_den_o;

    perf_counter uut (
        .clk(clk), .rst_n(rst_n),
        .commit_i(commit_i), .cycle_o(cycle_o), .commit_o(commit_o),
        .front_stall_i(front_stall_i), .issue_stall_i(issue_stall_i),
        .lsq_stall_i(lsq_stall_i), .recover_i(recover_i),
        .front_stall_o(front_stall_o), .issue_stall_o(issue_stall_o),
        .lsq_stall_o(lsq_stall_o), .recover_o(recover_o),
        .bottleneck_o(bottleneck_o), .stall_any_o(stall_any_o),
        .ipc_num_o(ipc_num_o), .ipc_den_o(ipc_den_o)
    );

    always #5 clk = ~clk;

    integer pass = 0, fail = 0;
    task chk;
        input cond;
        input [1023:0] msg;
        begin
            if (cond) begin
                pass = pass + 1;
                $display("PASS %0d: %0s", pass + fail, msg);
            end else begin
                fail = fail + 1;
                $display("FAIL %0d: %0s", pass + fail, msg);
            end
        end
    endtask

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task drive;
        input [1:0] cmt;
        input fs, is, ls, rc;
        begin
            commit_i = cmt;
            front_stall_i = fs;
            issue_stall_i = is;
            lsq_stall_i = ls;
            recover_i = rc;
        end
    endtask

    initial begin
        // 先给一个明确的下降沿，让异步复位真正触发
        rst_n = 1'b1;
        #1;
        rst_n = 1'b0;
        #2;
        chk(cycle_o == 0 && commit_o == 0, "reset: cycle and commit are zero");
        chk(front_stall_o == 0 && issue_stall_o == 0 &&
            lsq_stall_o == 0 && recover_o == 0, "reset: stall counters are zero");
        chk(!stall_any_o && bottleneck_o == 2'd0, "reset: no stall reported");

        rst_n = 1'b1;
        drive(2'd2, 1'b0, 1'b0, 1'b0, 1'b0);

        repeat (4) tick;
        chk(cycle_o == 4, "ideal: four cycles elapsed");
        chk(commit_o == 8, "ideal: two commits per cycle give eight");
        chk(ipc_num_o == 8 && ipc_den_o == 4, "ideal: IPC numerator and denominator");
        chk(!stall_any_o, "ideal: no stall");

        drive(2'd0, 1'b1, 1'b0, 1'b0, 1'b0);
        repeat (3) tick;
        chk(front_stall_o == 3, "frontend: three stall cycles counted");
        chk(commit_o == 8, "frontend: no commit while starved");
        chk(bottleneck_o == 2'd0 && stall_any_o, "frontend: bottleneck code 0");

        drive(2'd0, 1'b0, 1'b1, 1'b0, 1'b0);
        repeat (2) tick;
        chk(issue_stall_o == 2, "issue: two stall cycles counted");
        chk(bottleneck_o == 2'd1, "issue: bottleneck code 1");

        drive(2'd0, 1'b0, 1'b0, 1'b1, 1'b0);
        tick;
        chk(lsq_stall_o == 1, "lsq: one stall cycle counted");
        chk(bottleneck_o == 2'd2, "lsq: bottleneck code 2");

        drive(2'd0, 1'b0, 1'b0, 1'b0, 1'b1);
        tick;
        chk(recover_o == 1, "recover: one redirect cycle counted");
        chk(bottleneck_o == 2'd3, "recover: bottleneck code 3");

        drive(2'd0, 1'b1, 1'b1, 1'b1, 1'b1);
        tick;
        chk(front_stall_o == 4 && issue_stall_o == 3,
            "multiple: all stall counters advance");
        chk(lsq_stall_o == 2 && recover_o == 2,
            "multiple: lsq and recover also advance");
        chk(bottleneck_o == 2'd3, "multiple: recover wins priority");

        drive(2'd1, 1'b0, 1'b0, 1'b0, 1'b0);
        tick;
        chk(!stall_any_o && bottleneck_o == 2'd0, "clear: no stall reported");
        chk(commit_o == 9, "clear: commit resumes");

        $display("TOTAL %0d checks, %0d passed, %0d failed", pass + fail, pass, fail);
        if (fail == 0) $display("ALL TESTS PASSED");
        $finish;
    end
endmodule
