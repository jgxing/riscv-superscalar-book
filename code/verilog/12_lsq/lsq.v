// 简化 LSQ：按程序顺序记账，做 store-to-load 转发，检测 load 投机违例
module lsq #(
    parameter ENTRY  = 8,
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter AGE_W  = 8,
    parameter PS_W   = 6,
    parameter IDX_W  = 3   // ENTRY=8 时索引需要 3 位
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // 入队：一条访存 uop 占一项，顺序由年龄给出
    input  wire                    alloc_en_i,
    input  wire                    alloc_is_store_i,
    input  wire [AGE_W-1:0]        alloc_age_i,
    input  wire [PS_W-1:0]         alloc_dest_i,

    // store 的地址与数据分开就绪
    input  wire                    st_addr_en_i,
    input  wire [IDX_W-1:0]        st_addr_idx_i,
    input  wire [ADDR_W-1:0]       st_addr_i,
    input  wire                    st_data_en_i,
    input  wire [IDX_W-1:0]        st_data_idx_i,
    input  wire [DATA_W-1:0]       st_data_i,

    // load 地址算完，投机读
    input  wire                    ld_en_i,
    input  wire [IDX_W-1:0]        ld_idx_i,
    input  wire [ADDR_W-1:0]       ld_addr_i,

    // 转发结果：命中时 data 有效，未命中时给出地址去访存
    output reg  [DATA_W-1:0]       ld_fwd_data_o,
    output reg                     ld_fwd_hit_o,
    output reg  [ADDR_W-1:0]       ld_addr_o,
    output reg  [PS_W-1:0]         ld_dest_o,

    // 违例：更老的 store 地址算完后，发现它和已投机的 load 同址
    output reg                     violation_o,
    output reg  [AGE_W-1:0]        violation_age_o,

    output wire [ENTRY-1:0]        busy_o
);
    reg                   valid    [0:ENTRY-1];
    reg                   is_store [0:ENTRY-1];
    reg  [AGE_W-1:0]      age      [0:ENTRY-1];
    reg  [PS_W-1:0]       dest     [0:ENTRY-1];
    reg  [ADDR_W-1:0]     addr     [0:ENTRY-1];
    reg                   addr_rdy [0:ENTRY-1];
    reg  [DATA_W-1:0]     data     [0:ENTRY-1];
    reg                   data_rdy [0:ENTRY-1];
    reg                   ld_done  [0:ENTRY-1];

    integer e;
    reg [ENTRY-1:0] busy;
    always @* begin
        for (e = 0; e < ENTRY; e = e + 1)
            busy[e] = valid[e];
    end
    assign busy_o = busy;

    // 转发检查：找所有更老、同址、地址和数据都已就绪的 store，取其中最年轻的
    reg [DATA_W-1:0] fwd_data;
    reg              fwd_hit;
    reg [AGE_W-1:0]  best_age;
    always @* begin
        fwd_data = {DATA_W{1'b0}};
        fwd_hit  = 1'b0;
        best_age = {AGE_W{1'b0}};
        if (ld_en_i) begin
            for (e = 0; e < ENTRY; e = e + 1) begin
                if (valid[e] && is_store[e] && addr_rdy[e] && data_rdy[e] &&
                    (addr[e] == ld_addr_i) &&
                    (age[e] < age[ld_idx_i]) &&
                    (!fwd_hit || (age[e] > best_age))) begin
                    best_age = age[e];
                    fwd_data = data[e];
                    fwd_hit  = 1'b1;
                end
            end
        end
    end

    always @* begin
        ld_fwd_data_o = fwd_data;
        ld_fwd_hit_o  = fwd_hit;
        ld_addr_o     = ld_addr_i;
        ld_dest_o     = valid[ld_idx_i] ? dest[ld_idx_i] : {PS_W{1'b0}};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (e = 0; e < ENTRY; e = e + 1) begin
                valid[e]    <= 1'b0;
                is_store[e] <= 1'b0;
                age[e]      <= {AGE_W{1'b0}};
                dest[e]     <= {PS_W{1'b0}};
                addr[e]     <= {ADDR_W{1'b0}};
                addr_rdy[e] <= 1'b0;
                data[e]     <= {DATA_W{1'b0}};
                data_rdy[e] <= 1'b0;
                ld_done[e]  <= 1'b0;
            end
            violation_o    <= 1'b0;
            violation_age_o <= {AGE_W{1'b0}};
        end else begin
            // 默认这一拍没有违例
            violation_o     <= 1'b0;
            violation_age_o <= {AGE_W{1'b0}};

            // 入队：找第一个空项
            begin : alloc_block
                integer first_free;
                first_free = -1;
                for (e = 0; e < ENTRY; e = e + 1)
                    if (!valid[e] && (first_free < 0)) first_free = e;
                if (alloc_en_i && (first_free >= 0)) begin
                    valid[first_free]    <= 1'b1;
                    is_store[first_free] <= alloc_is_store_i;
                    age[first_free]      <= alloc_age_i;
                    dest[first_free]     <= alloc_dest_i;
                    addr_rdy[first_free] <= 1'b0;
                    data_rdy[first_free] <= 1'b0;
                    ld_done[first_free]  <= 1'b0;
                end
            end

            // store 地址就绪，顺便检查有没有更老的 load 已经投机读过同一地址
            if (st_addr_en_i) begin
                addr[st_addr_idx_i]     <= st_addr_i;
                addr_rdy[st_addr_idx_i] <= 1'b1;
                for (e = 0; e < ENTRY; e = e + 1) begin
                    if (valid[e] && !is_store[e] && ld_done[e] &&
                        (age[e] > age[st_addr_idx_i]) &&
                        (addr[e] == st_addr_i)) begin
                        violation_o     <= 1'b1;
                        violation_age_o <= age[e];
                    end
                end
            end

            // store 数据就绪
            if (st_data_en_i) begin
                data[st_data_idx_i]     <= st_data_i;
                data_rdy[st_data_idx_i] <= 1'b1;
            end

            // load 地址就绪，记下地址和已投机标记
            if (ld_en_i) begin
                addr[ld_idx_i]     <= ld_addr_i;
                addr_rdy[ld_idx_i] <= 1'b1;
                ld_done[ld_idx_i]  <= 1'b1;
            end
        end
    end
endmodule
