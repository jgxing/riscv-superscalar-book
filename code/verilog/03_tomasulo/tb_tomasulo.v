// ==============================================================
// Testbench：验证第3章三个核心机制
//   T1 —— 唤醒：广播匹配标签，保留站操作数就绪(ready=1)
//   T2 —— WAW：RAT[R1] 被后来的写入覆盖，旧标签广播不误清
//   T3 —— 广播仲裁：两部件同时请求，一根 CDB 一拍只放行一个
// 运行： iverilog -o sim.vvp *.v && vvp sim.vvp
// ==============================================================
`timescale 1ns/1ps
module tb_tomasulo;
    parameter TAG_W = 5, DATA_W = 32;

    // ---------- DUT 信号 ----------
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // RAT DUT
    reg [2:0] rs1, rs2, rd;
    wire [TAG_W-1:0] q1, q2;
    wire q1_valid, q2_valid;
    reg rename_en, rat_cdb_valid;
    reg [TAG_W-1:0] new_tag, rat_cdb_tag;

    rat #(.NREG(8), .TAG_W(TAG_W)) u_rat (
        .clk(clk), .rst_n(rst_n),
        .rs1(rs1), .rs2(rs2), .q1(q1), .q2(q2),
        .q1_valid(q1_valid), .q2_valid(q2_valid),
        .rename_en(rename_en), .rd(rd), .new_tag(new_tag),
        .cdb_valid(rat_cdb_valid), .cdb_tag(rat_cdb_tag)
    );

    // 保留站 DUT
    reg issue_en, vj_valid_in, vk_valid_in, dispatch_en, rs_cdb_valid;
    reg [3:0] op_in;
    reg [DATA_W-1:0] vj_in, vk_in, rs_cdb_data;
    reg [TAG_W-1:0] qj_in, qk_in, dest_tag_in, rs_cdb_tag;
    wire busy, ready;
    wire [3:0] op_out;
    wire [DATA_W-1:0] vj_out, vk_out;
    wire [TAG_W-1:0] dest_tag_out;

    reservation_station #(.TAG_W(TAG_W), .DATA_W(DATA_W)) u_rs (
        .clk(clk), .rst_n(rst_n),
        .issue_en(issue_en), .op_in(op_in),
        .vj_valid_in(vj_valid_in), .vk_valid_in(vk_valid_in),
        .vj_in(vj_in), .vk_in(vk_in),
        .qj_in(qj_in), .qk_in(qk_in), .dest_tag_in(dest_tag_in),
        .cdb_valid(rs_cdb_valid), .cdb_tag(rs_cdb_tag), .cdb_data(rs_cdb_data),
        .dispatch_en(dispatch_en),
        .busy(busy), .ready(ready), .op_out(op_out),
        .vj_out(vj_out), .vk_out(vk_out), .dest_tag_out(dest_tag_out)
    );

    // CDB 仲裁 DUT
    reg [3:0] req;
    reg [4*TAG_W-1:0] req_tag;
    reg [4*DATA_W-1:0] req_data;
    wire cdb_valid;
    wire [TAG_W-1:0] cdb_tag;
    wire [DATA_W-1:0] cdb_data;
    wire [3:0] grant;

    cdb_arbiter #(.N(4), .TAG_W(TAG_W), .DATA_W(DATA_W)) u_cdb (
        .req(req), .req_tag(req_tag), .req_data(req_data),
        .cdb_valid(cdb_valid), .cdb_tag(cdb_tag),
        .cdb_data(cdb_data), .grant(grant)
    );

    integer errors = 0;
    task chk;
        input [1023:0] msg;
        input cond;
        begin
            if (!cond) begin
                $display("  [FAIL] %0s", msg);
                errors = errors + 1;
            end else begin
                $display("  [PASS] %0s", msg);
            end
        end
    endtask

    initial begin
        $display("==== Chapter 3 Tomasulo core mechanisms ====");
        // 复位
        rs1=0; rs2=0; rd=0; rename_en=0; rat_cdb_valid=0; new_tag=0; rat_cdb_tag=0;
        issue_en=0; vj_valid_in=0; vk_valid_in=0; dispatch_en=0; rs_cdb_valid=0;
        op_in=0; vj_in=0; vk_in=0; qj_in=0; qk_in=0; dest_tag_in=0;
        rs_cdb_tag=0; rs_cdb_data=0;
        req=0; req_tag=0; req_data=0;
        #20 rst_n = 1;

        // ===== T1: 保留站唤醒 =====
        $display("-- T1 Reservation station wakeup --");
        // 发射一项: vj 已有值, vk 在等标签 #21
        @(negedge clk);
        issue_en=1; op_in=4'b0001;
        vj_valid_in=1; vj_in=32'd10;
        vk_valid_in=0; vk_in=0; qj_in=0; qk_in=5'd21; dest_tag_in=5'd30;
        @(negedge clk); issue_en=0;
        #1; chk("After issue: busy=1, ready=0 (waiting vk)", busy && !ready);
        // 广播一个不匹配的标签 #22 —— 不应唤醒
        @(negedge clk); rs_cdb_valid=1; rs_cdb_tag=5'd22; rs_cdb_data=32'd999;
        @(negedge clk); rs_cdb_valid=0;
        #1; chk("Broadcast #22 (no match): still ready=0", !ready && (vk_out===32'd0));
        // 广播匹配标签 #21 —— 应唤醒, vk 锁存数据
        @(negedge clk); rs_cdb_valid=1; rs_cdb_tag=5'd21; rs_cdb_data=32'd7;
        @(negedge clk); rs_cdb_valid=0;
        #1; chk("Broadcast #21 (match): ready=1 and vk=7", ready && (vk_out===32'd7));

        // ===== T2: WAW 覆盖 =====
        $display("-- T2 RAT / WAW --");
        @(negedge clk);
        rename_en=1; rd=3'd1; new_tag=5'd21;   // I1: 写R1 <- #21
        @(negedge clk);
        new_tag=5'd24;                          // I4: 写R1 <- #24 (覆盖)
        @(negedge clk); rename_en=0;
        rs1=3'd1; #1;
        chk("After two writes to R1: latest tag is #24", q1_valid && (q1===5'd24));
        // 广播旧标签 #21 —— 不应误清 R1 的登记
        @(negedge clk); rat_cdb_valid=1; rat_cdb_tag=5'd21;
        @(negedge clk); rat_cdb_valid=0;
        #1; chk("Broadcast old tag #21: R1 still #24 (WAW ok)", q1_valid && (q1===5'd24));
        // 广播新标签 #24 —— 应清除, 表示值已写回寄存器堆
        @(negedge clk); rat_cdb_valid=1; rat_cdb_tag=5'd24;
        @(negedge clk); rat_cdb_valid=0;
        #1; chk("Broadcast new tag #24: R1 entry cleared", !q1_valid);

        // ===== T3: 广播仲裁 =====
        $display("-- T3 CDB arbiter --");
        @(negedge clk);
        req = 4'b0110;                          // 部件1 和 部件2 同时请求
        req_tag = {5'd0,5'd23,5'd22,5'd0};
        req_data = {32'd0,32'd33,32'd22,32'd0};
        #1;
        chk("Two units request: cdb_valid=1", cdb_valid);
        chk("Fixed priority: unit1 wins grant", grant===4'b0010);
        chk("Broadcast unit1 tag #22", cdb_tag===5'd22);
        req=0; #1; chk("No request: cdb_valid=0", !cdb_valid);

        $display("==== Result: %0d errors ====", errors);
        if (errors==0) $display("ALL TESTS PASSED");
        $finish;
    end
endmodule
