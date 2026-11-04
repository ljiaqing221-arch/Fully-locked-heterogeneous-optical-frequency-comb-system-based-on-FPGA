`timescale 1ns/1ps
module average_bad_window;
dwell_average #(.AVG_LOG2(17)) dut();
initial begin #50;$display("PARAMETER_ACCEPTED");$finish;end
endmodule
