`timescale 1ns/1ps
// AD9269 0x14=0x21: multiplexed CMOS, two's complement.
// Accept one channel already captured with its matching OTR on the same edge.
module fv_adc_average #(parameter LOG2=8, parameter TWOS_COMPLEMENT=1)(
 input wire clk,rst_n,ready,otr,input wire [15:0] raw_code,
 output reg [15:0] voltage_code, output reg sample_valid,output reg quality_ok);
 reg [LOG2-1:0] count;
 reg [16+LOG2-1:0] sum;
 reg bad;
 wire [15:0] monotonic_code=TWOS_COMPLEMENT ? raw_code^16'h8000 : raw_code;
 wire invalid_now=otr || monotonic_code<16'h0100 || monotonic_code>16'hFEFF;
 wire [16+LOG2-1:0] total=sum+monotonic_code;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin count<=0;sum<=0;bad<=0;voltage_code<=0;sample_valid<=0;quality_ok<=0;end
  else begin
   sample_valid<=0;
   if(!ready) begin count<=0;sum<=0;bad<=0;quality_ok<=0;end
   else begin
    if(invalid_now) quality_ok<=0;
    if(&count) begin
     count<=0;sum<=0;bad<=0;
     quality_ok<=!(bad||invalid_now);
     if(!(bad||invalid_now)) begin voltage_code<=total>>LOG2;sample_valid<=1;end
    end else begin count<=count+1'b1;sum<=total;bad<=bad||invalid_now;end
   end
  end
 end
endmodule


