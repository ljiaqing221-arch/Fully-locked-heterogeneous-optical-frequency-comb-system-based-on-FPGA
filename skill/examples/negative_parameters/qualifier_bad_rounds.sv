`timescale 1ns/1ps
module qualifier_bad_rounds;
sweep_qualifier #(.MIN_CONSISTENT_SWEEPS(1)) dut();
initial begin #50;$display("PARAMETER_ACCEPTED");$finish;end
endmodule
