`timescale 1ns/1ps
// Same register values as pump_locked, with a slower, explicit SPI clock.
module AD9269_SPI(input wire sys_clk,sys_rst,output reg config_done,
 output reg spi_cs_n,spi_sclk,spi_mosi);
 reg [23:0] delay_count,frame;
 reg [5:0] edges;
 reg [3:0] divider;
 reg [2:0] state;
 reg [1:0] word_index;
 always @(posedge sys_clk or negedge sys_rst) begin
  if(!sys_rst) begin config_done<=0;spi_cs_n<=1;spi_sclk<=1;spi_mosi<=0;
   delay_count<=0;frame<=0;edges<=0;divider<=0;state<=0;word_index<=0;end
  else case(state)
   0: if(delay_count==4999999) begin delay_count<=0;state<=1;end else delay_count<=delay_count+1;
   1: begin
    case(word_index)
     0:frame<=24'h001421; // CMOS multiplex, two's complement
     1:frame<=24'h001711; // same DCO delay as known source; verify timing on board
     default:frame<=24'h00FF01;
    endcase
    state<=2;edges<=0;divider<=0;
   end
   2: begin spi_cs_n<=0;state<=3;end
   3: if(divider==4) begin
    divider<=0;spi_sclk<=~spi_sclk;
    if(spi_sclk) begin spi_mosi<=frame[23];frame<={frame[22:0],1'b0};end
    if(edges==47) state<=4;else edges<=edges+1;
   end else divider<=divider+1;
   4: begin spi_cs_n<=1;spi_sclk<=1;state<=5;end
   5: if(word_index==2) begin config_done<=1;state<=6;end
      else begin word_index<=word_index+1;state<=1;end
   default:state<=6;
  endcase
 end
endmodule
