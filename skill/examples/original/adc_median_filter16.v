`timescale 1ns / 1ps

module adc_median_filter16(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] adc_in,
    output reg  [15:0] adc_out
);

reg [15:0] window0;
reg [15:0] window1;
reg [15:0] window2;
reg [15:0] window3;
reg [15:0] window4;
reg [15:0] s0;
reg [15:0] s1;
reg [15:0] s2;
reg [15:0] s3;
reg [15:0] s4;
reg [15:0] tmp;
integer i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        window0 <= 16'd0;
        window1 <= 16'd0;
        window2 <= 16'd0;
        window3 <= 16'd0;
        window4 <= 16'd0;
        adc_out <= 16'd0;
    end else begin
        window4 <= window3;
        window3 <= window2;
        window2 <= window1;
        window1 <= window0;
        window0 <= adc_in;

        s0 = window0;
        s1 = window1;
        s2 = window2;
        s3 = window3;
        s4 = window4;

        for (i = 0; i < 4; i = i + 1) begin
            if (s0 > s1) begin tmp = s0; s0 = s1; s1 = tmp; end
            if (s1 > s2) begin tmp = s1; s1 = s2; s2 = tmp; end
            if (s2 > s3) begin tmp = s2; s2 = s3; s3 = tmp; end
            if (s3 > s4) begin tmp = s3; s3 = s4; s4 = tmp; end
        end

        adc_out <= s2;
    end
end

endmodule
