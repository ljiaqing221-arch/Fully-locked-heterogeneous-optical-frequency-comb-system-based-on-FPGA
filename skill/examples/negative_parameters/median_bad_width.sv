`timescale 1ns/1ps
module median_bad_width;
median5_valid #(.WIDTH(0)) dut();
initial begin #50;$display("PARAMETER_ACCEPTED");$finish;end
endmodule
