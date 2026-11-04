`timescale 1ns/1ps
// Fixed integer division. No ADC-derived clock and no error-driven frequency changes.
module fixed_lo_divider #(parameter integer DIVIDE=10)(input wire clk,rst_n,output reg square);
 localparam integer HALF=DIVIDE/2;
 reg [31:0] count;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin count<=0;square<=0;end
  else if(count==HALF-1) begin count<=0;square<=~square;end
  else count<=count+1;
 end
endmodule

module fixed_lo_clock #(parameter integer DIVIDE=10)(input wire clk,rst_n,output wire lo_out);
 generate
  if(DIVIDE==1) begin: g_forward
   // Use the device's DDR output cell for a forwarded full-rate clock.
   ODDR #(.DDR_CLK_EDGE("SAME_EDGE"),.INIT(1'b0),.SRTYPE("ASYNC")) u_oddr(
    .Q(lo_out),.C(clk),.CE(1'b1),.D1(1'b1),.D2(1'b0),.R(~rst_n),.S(1'b0));
  end else begin: g_div
   fixed_lo_divider #(.DIVIDE(DIVIDE)) u_div(.clk(clk),.rst_n(rst_n),.square(lo_out));
  end
 endgenerate
 // Configuration is checked by the build script before synthesis.
endmodule
