`timescale 1ns/1ps
module spi_bad_period;
spi_frame_tx #(.HALF_PERIOD(0)) dut();
initial begin #50;$display("PARAMETER_ACCEPTED");$finish;end
endmodule
