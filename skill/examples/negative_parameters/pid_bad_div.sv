`timescale 1ns/1ps
module pid_bad_div;
pid_error_lock #(.PID_DIV(0)) dut();
initial begin #50;$display("PARAMETER_ACCEPTED");$finish;end
endmodule
