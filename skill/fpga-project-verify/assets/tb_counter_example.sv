`timescale 1ns/1ps
module tb_counter_example;
reg clk=0;always #5 clk=~clk;reg rst_n=0,enable=0;wire[7:0] count;
counter_example dut(clk,rst_n,enable,count);
initial begin
 repeat(2) @(negedge clk);rst_n=1;
 repeat(4) @(negedge clk);if(count!==0) $fatal(1,"counter hold failed");
 enable=1;repeat(260) @(negedge clk);if(count!==4) $fatal(1,"counter enable/wrap failed");
 rst_n=0;#1;if(count!==0) $fatal(1,"counter reset failed");
 $display("PASS_STANDALONE_COUNTER");$finish;
end
initial begin #100000;$fatal(1,"watchdog");end
endmodule
