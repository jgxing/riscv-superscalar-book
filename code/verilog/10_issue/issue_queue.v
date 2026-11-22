// 四项的发射队列：监听广播置就绪，按年龄挑就绪项送出去
module issue_queue #(
    parameter ENTRY  = 4,
    parameter PS_W   = 6,
    parameter SEQ_W  = 8,
    parameter UOP_W  = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire [1:0]              alloc_en_i,     // 本拍新进几条
    input  wire [ENTRY-1:0]        alloc_slot_i0,  // 第一条放到哪一项
    input  wire [ENTRY-1:0]        alloc_slot_i1,
    input  wire [UOP_W-1:0]        alloc_uop_i0,   // 打包好的 uop
    input  wire [UOP_W-1:0]        alloc_uop_i1,

    input  wire [1:0]              wakeup_en_i,    // 本拍有几路广播
    input  wire [PS_W-1:0]         wakeup_pd_i0,
    input  wire [PS_W-1:0]         wakeup_pd_i1,

    input  wire [1:0]              unit_free_i,    // 本拍空着几个发射口
    output wire [ENTRY-1:0]        grant0_o,
    output wire [ENTRY-1:0]        grant1_o,
    output wire [ENTRY-1:0]        grant_o,
    output wire [UOP_W-1:0]        issue_uop_o0,
    output wire [UOP_W-1:0]        issue_uop_o1,
    output wire [ENTRY-1:0]        busy_o
);
    // uop 打包格式，总共 32 位
    localparam TYPE_HI = 31, TYPE_LO = 30;
    localparam RDY1    = 29, RDY2    = 28;
    localparam PS1_HI  = 27, PS1_LO  = 22;
    localparam PS2_HI  = 21, PS2_LO  = 16;
    localparam DEST_HI = 15, DEST_LO = 10;
    localparam AGE_HI  =  9, AGE_LO  =  2;

    reg          valid [0:ENTRY-1];
    reg  [1:0]   typ   [0:ENTRY-1];
    reg          rdy1  [0:ENTRY-1];
    reg          rdy2  [0:ENTRY-1];
    reg  [PS_W-1:0]  ps1  [0:ENTRY-1];
    reg  [PS_W-1:0]  ps2  [0:ENTRY-1];
    reg  [PS_W-1:0]  dest [0:ENTRY-1];
    reg  [SEQ_W-1:0] age  [0:ENTRY-1];

    integer e;
    reg [ENTRY-1:0] req;

    // 操作数都就绪的项才有资格被选
    always @* begin
        for (e = 0; e < ENTRY; e = e + 1)
            req[e] = valid[e] & rdy1[e] & rdy2[e];
    end

    // 空闲发射口的数量就是本次最多能批几个
    wire [1:0] limit;
    assign limit = {1'b0, unit_free_i[0]} + {1'b0, unit_free_i[1]};

    wire [ENTRY*SEQ_W-1:0] age_flat;
    genvar gi;
    generate
        for (gi = 0; gi < ENTRY; gi = gi + 1) begin : flatten_age
            assign age_flat[gi*SEQ_W +: SEQ_W] = age[gi];
        end
    endgenerate

    arbiter #(.N(ENTRY), .SEQ_W(SEQ_W)) u_arb (
        .req_i(req), .age_i(age_flat), .limit_i(limit),
        .grant0_o(grant0_o), .grant1_o(grant1_o), .grant_o(grant_o)
    );

    function [UOP_W-1:0] pack_entry;
        input [1:0] t;
        input r1, r2;
        input [PS_W-1:0] s1, s2, d;
        input [SEQ_W-1:0] a;
        begin
            pack_entry = {t, r1, r2, s1, s2, d, a, 2'b0};
        end
    endfunction

    reg [UOP_W-1:0] out0, out1;
    always @* begin
        out0 = {UOP_W{1'b0}};
        out1 = {UOP_W{1'b0}};
        for (e = 0; e < ENTRY; e = e + 1) begin
            if (grant0_o[e])
                out0 = pack_entry(typ[e], rdy1[e], rdy2[e], ps1[e], ps2[e], dest[e], age[e]);
            if (grant1_o[e])
                out1 = pack_entry(typ[e], rdy1[e], rdy2[e], ps1[e], ps2[e], dest[e], age[e]);
        end
    end
    assign issue_uop_o0 = out0;
    assign issue_uop_o1 = out1;

    reg [ENTRY-1:0] busy;
    always @* begin
        for (e = 0; e < ENTRY; e = e + 1)
            busy[e] = valid[e];
    end
    assign busy_o = busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (e = 0; e < ENTRY; e = e + 1) begin
                valid[e] <= 1'b0;
                typ[e]   <= 2'b0;
                rdy1[e]  <= 1'b0;
                rdy2[e]  <= 1'b0;
                ps1[e]   <= {PS_W{1'b0}};
                ps2[e]   <= {PS_W{1'b0}};
                dest[e]  <= {PS_W{1'b0}};
                age[e]   <= {SEQ_W{1'b0}};
            end
        end else begin
            for (e = 0; e < ENTRY; e = e + 1) begin
                // 唤醒：内容比较，命中就把对应的就绪位置一
                if (valid[e] && wakeup_en_i[0] && (ps1[e] == wakeup_pd_i0)) rdy1[e] <= 1'b1;
                if (valid[e] && wakeup_en_i[0] && (ps2[e] == wakeup_pd_i0)) rdy2[e] <= 1'b1;
                if (valid[e] && wakeup_en_i[1] && (ps1[e] == wakeup_pd_i1)) rdy1[e] <= 1'b1;
                if (valid[e] && wakeup_en_i[1] && (ps2[e] == wakeup_pd_i1)) rdy2[e] <= 1'b1;

                // 被选中的项让出位置
                if (grant0_o[e] || grant1_o[e])
                    valid[e] <= 1'b0;

                // 新进来的项写进去；写在最后，同拍不会把新项又选出去
                if (alloc_en_i[0] && alloc_slot_i0[e]) begin
                    valid[e] <= 1'b1;
                    typ[e]   <= alloc_uop_i0[TYPE_HI:TYPE_LO];
                    rdy1[e]  <= alloc_uop_i0[RDY1];
                    rdy2[e]  <= alloc_uop_i0[RDY2];
                    ps1[e]   <= alloc_uop_i0[PS1_HI:PS1_LO];
                    ps2[e]   <= alloc_uop_i0[PS2_HI:PS2_LO];
                    dest[e]  <= alloc_uop_i0[DEST_HI:DEST_LO];
                    age[e]   <= alloc_uop_i0[AGE_HI:AGE_LO];
                end
                if (alloc_en_i[1] && alloc_slot_i1[e]) begin
                    valid[e] <= 1'b1;
                    typ[e]   <= alloc_uop_i1[TYPE_HI:TYPE_LO];
                    rdy1[e]  <= alloc_uop_i1[RDY1];
                    rdy2[e]  <= alloc_uop_i1[RDY2];
                    ps1[e]   <= alloc_uop_i1[PS1_HI:PS1_LO];
                    ps2[e]   <= alloc_uop_i1[PS2_HI:PS2_LO];
                    dest[e]  <= alloc_uop_i1[DEST_HI:DEST_LO];
                    age[e]   <= alloc_uop_i1[AGE_HI:AGE_LO];
                end
            end
        end
    end
endmodule
