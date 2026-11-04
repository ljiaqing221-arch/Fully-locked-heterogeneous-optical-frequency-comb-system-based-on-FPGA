`timescale 1ns/1ps
module scan_bad_step;
triangle_scan #(.CODE_STEP(0)) dut();
initial begin #50;$display("PARAMETER_ACCEPTED");$finish;end
endmodule
