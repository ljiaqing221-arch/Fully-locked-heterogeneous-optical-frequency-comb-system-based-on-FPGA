`timescale 1ns/1ps
module tb_edge_configs;
reg clk=0;always #5 clk=~clk;reg rst_n=0,start=0,valid=0,bad=0;
reg [11:0] value=12'hABC;wire done,av;wire[11:0] avg;
dwell_average #(.WIDTH(12),.AVG_LOG2(0),.SETTLE_CYCLES(0)) a(clk,rst_n,start,valid,bad,value,done,av,avg);
reg txvalid=0;wire ready,busy,txdone,cs,sclk,mosi;integer captured_bits=0;
spi_frame_tx #(.FRAME_BITS(1),.HALF_PERIOD(1),.CS_HIGH_CYCLES(1),.CS_HOLD_CYCLES(1),.CPOL(0),.CPHA(0)) tx(clk,rst_n,txvalid,1'b1,ready,busy,txdone,cs,sclk,mosi);
always @(posedge sclk) if(!cs) begin
 captured_bits=captured_bits+1;if(mosi!==1) $fatal(1,"one-bit frame value mismatch");
end
task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
initial begin #100000;$fatal(1,"watchdog");end
initial begin
 tick();rst_n=1;start=1;valid=1;tick();start=0;
 if(done) $fatal(1,"step_start must exclude same-edge sample");
 tick();if(!done||!av||avg!==12'hABC) $fatal(1,"single-sample averaging failed");
 valid=0;tick();if(done||av) $fatal(1,"single-sample flags not pulsed");
 txvalid=1;tick();txvalid=0;wait(txdone);#1;
 if(captured_bits!=1) $fatal(1,"one-bit frame edge count failed");
 $display("PASS_EDGE_CONFIGS");$finish;
end
endmodule
