`timescale 1ns/1ps
// DAC8552 samples on falling SCLK. Keep SYNC low THROUGH falling edge 24.
// 0x30 updates A, 0x34 updates B, following the source project's format.
module aux_pzt_dac #(parameter HALF_PERIOD=5,parameter [15:0] B_PARK=16'h8000)(
 input wire clk,rst_n,input wire [15:0] pzt_code,
 output reg spi_sync,spi_sclk,spi_mosi,output wire busy);
 reg [23:0] frame;
 reg [15:0] latch_a;
 reg [5:0] falling_count;
 reg [15:0] divider;
 reg [2:0] state;
 reg channel_b;
 assign busy=(state!=0);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin spi_sync<=1;spi_sclk<=0;spi_mosi<=0;frame<=0;
   divider<=0;state<=0;channel_b<=0;falling_count<=0;latch_a<=0;end
  else case(state)
   0: begin latch_a<=pzt_code;channel_b<=0;state<=1;end
   1: begin
    frame<=channel_b?{8'h34,B_PARK}:{8'h30,latch_a};
    spi_mosi<=0;spi_sync<=0;spi_sclk<=0;divider<=0;falling_count<=0;state<=2;
   end
   2: if(divider==HALF_PERIOD-1) begin
    divider<=0;
    if(!spi_sclk) begin spi_sclk<=1;spi_mosi<=frame[23];end
    else begin
     spi_sclk<=0;falling_count<=falling_count+1;
     if(falling_count==23) state<=3;
     else frame<={frame[22:0],1'b0};
    end
   end else divider<=divider+1;
   // Distinct hold state prevents SYNC rising together with the final sample.
   3: if(divider==HALF_PERIOD-1) begin divider<=0;spi_sync<=1;state<=4;end else divider<=divider+1;
   4: if(divider==9) begin divider<=0;if(channel_b) state<=0;else begin channel_b<=1;state<=1;end end
      else divider<=divider+1;
   default:state<=0;
  endcase
 end
endmodule


