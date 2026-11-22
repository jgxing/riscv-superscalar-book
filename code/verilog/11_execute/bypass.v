// 旁路选择器：源物理号与结果目的号做内容比较，命中就改用旁路值
module bypass #(
    parameter PS_W   = 6,
    parameter DATA_W = 32
)(
    input  wire [PS_W-1:0]       ps1_i,        // 源1的物理寄存器号
    input  wire [PS_W-1:0]       ps2_i,        // 源2的物理寄存器号
    input  wire [DATA_W-1:0]     rdata1_i,     // 寄存器堆读出的源1值
    input  wire [DATA_W-1:0]     rdata2_i,
    input  wire [1:0]            byp_en_i,     // 两路旁路结果是否有效
    input  wire [PS_W-1:0]       byp_dest_i0,  // 第0路结果的目的号
    input  wire [DATA_W-1:0]     byp_data_i0,  // 第0路结果的值
    input  wire [PS_W-1:0]       byp_dest_i1,  // 第1路结果的目的号
    input  wire [DATA_W-1:0]     byp_data_i1,
    output wire [DATA_W-1:0]     src1_o,       // 选好的源1值
    output wire [DATA_W-1:0]     src2_o        // 选好的源2值
);
    reg [DATA_W-1:0] s1, s2;

    // 源1：默认用寄存器堆的值，旁路命中再覆盖
    always @* begin
        s1 = rdata1_i;
        if (byp_en_i[0] && (byp_dest_i0 == ps1_i))
            s1 = byp_data_i0;
        if (byp_en_i[1] && (byp_dest_i1 == ps1_i))
            s1 = byp_data_i1;   // 写在后面的优先级更高
    end

    // 源2：同一套逻辑，换成 ps2 和 rdata2
    always @* begin
        s2 = rdata2_i;
        if (byp_en_i[0] && (byp_dest_i0 == ps2_i))
            s2 = byp_data_i0;
        if (byp_en_i[1] && (byp_dest_i1 == ps2_i))
            s2 = byp_data_i1;
    end

    assign src1_o = s1;
    assign src2_o = s2;
endmodule
