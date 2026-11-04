`timescale 1ns/1ps
module tb_fixed_lo;
 reg clk=0;always #10 clk=~clk; // 50 MHz
 reg rst_n=0;
 wire lo5,lo25,lo50;
 fixed_lo_clock #(.DIVIDE(10)) d5(.clk(clk),.rst_n(rst_n),.lo_out(lo5));
 fixed_lo_clock #(.DIVIDE(2)) d25(.clk(clk),.rst_n(rst_n),.lo_out(lo25));
 fixed_lo_clock #(.DIVIDE(1)) d50(.clk(clk),.rst_n(rst_n),.lo_out(lo50));
 time last5=0,last25=0,last50=0;
 integer n5=0,n25=0,n50=0;
 always @(lo5) if(rst_n) begin
  if(last5!=0 && $time-last5!=100) $fatal(1,"5 MHz half period");last5=$time;n5++;
 end
 always @(lo25) if(rst_n) begin
  if(last25!=0 && $time-last25!=20) $fatal(1,"25 MHz half period");last25=$time;n25++;
 end
 always @(lo50) if(rst_n) begin
  if(last50!=0 && $time-last50!=10) $fatal(1,"50 MHz forwarded half period");last50=$time;n50++;
 end
 initial begin
  #35;rst_n=1;#4000;
  if(n5<30||n25<150||n50<300) $fatal(1,"missing LO clock edges");
  $display("LO TESTS PASSED: static /10, /2, full-rate ODDR periods and 50 percent duty");$finish;
 end
endmodule
