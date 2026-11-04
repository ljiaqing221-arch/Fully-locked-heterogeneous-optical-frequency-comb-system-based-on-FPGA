`timescale 1ns/1ps
module counter_example(input wire clk,rst_n,enable,output reg[7:0] count);
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) count<=0;
 else if(enable) count<=count+1'b1;
end
endmodule
