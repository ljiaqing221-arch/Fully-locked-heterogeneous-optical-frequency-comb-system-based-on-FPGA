`timescale 1ns/1ps
module tb_pid_parameter_edges;
reg clk=0;always #5 clk=~clk;reg rst_n=0;wire[15:0] out;
pid_error_lock #(.PID_DIV(1),.FINE_THRESHOLD(65535),.KP_FINE_SHIFT(0),.KI_FINE_SHIFT(0),.KD_FINE_SHIFT(0),.INTEGRAL_LIMIT(2147483600),.UNLOCK_THRESHOLD(32768)) dut(clk,rst_n,18'sd65535,out);
initial begin
 repeat(2) @(negedge clk);rst_n=1;
 repeat(32775) @(negedge clk);
 if(dut.integral_acc!==32'sd2147483600||out!==16'hA000) $fatal(1,"wide integral/PID intermediate overflow");
 $display("PASS_PID_PARAMETER_EDGES");$finish;
end
initial begin #1000000;$fatal(1,"watchdog");end
endmodule
