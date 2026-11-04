`timescale 1ns / 1ps

module AD9269(
    input  wire        SYS_CLK,
    input  wire        SYS_RST,
    input  wire        DATA_RST_N, // reset released in the DCO domain
    input  wire        OTR,
    input  wire        DCO,
    input  wire [15:0] DB15_0,

    output wire        AD_CLK,
    output wire        OEB,
    output wire        PDWM,
    output wire        SCLK,
    output wire        CSB,
    output wire        SDIO,
    output wire        ADC_READY,

    output reg  [15:0] AD_DATA_A,
    output reg  [15:0] AD_DATA_B
);

wire clk_50m;
wire clk_locked;

clk_wiz_1 u_mmcm_clk (
    .clk_50M (clk_50m),
    .reset   (~SYS_RST),
    .locked  (clk_locked),
    .clk_in1 (SYS_CLK)
);

assign AD_CLK = clk_50m;
assign OEB    = 1'b0;
assign PDWM   = 1'b0;

always @(posedge DCO or negedge DATA_RST_N) begin
    if (!DATA_RST_N)
        AD_DATA_A <= 16'd0;
    else
        AD_DATA_A <= DB15_0;
end

always @(negedge DCO or negedge DATA_RST_N) begin
    if (!DATA_RST_N)
        AD_DATA_B <= 16'd0;
    else
        AD_DATA_B <= DB15_0;
end

AD9269_SPI u_ad9269_spi (
    .sys_clk  (SYS_CLK),
    .sys_rst  (SYS_RST & clk_locked),
    .config_done(ADC_READY),
    .spi_cs_n (CSB),
    .spi_sclk (SCLK),
    .spi_mosi (SDIO)
);

endmodule
