`timescale 1ns / 1ps

module tb_pid_error_lock;
reg clk = 0;
always #5 clk = ~clk;
reg rst_n = 0;
reg signed [17:0] error_in = 0;
wire [15:0] lock_out;
wire [15:0] reversed_out;
integer i;
integer ref_u, ref_i, ref_last, e, delta, next_i;

pid_error_lock #(.PID_DIV(2), .LOCK_CONFIRM(4)) dut (
    .clk(clk), .rst_n(rst_n), .error_in(error_in), .lock_out(lock_out)
);
pid_error_lock #(
    .PID_DIV(2), .LOCK_CONFIRM(4), .ERROR_REVERSE(1'b1)
) reversed (
    .clk(clk), .rst_n(rst_n), .error_in(error_in), .lock_out(reversed_out)
);

task reset_core;
begin
    @(negedge clk); rst_n = 0; error_in = 0;
    #1;
    if (lock_out !== 16'h8000 || dut.locked !== 0 || dut.integral_acc !== 0)
        $fatal(1, "Reset contract failed");
    repeat (2) @(negedge clk);
    rst_n = 1;
end
endtask

// Starting at a negative edge, advance precisely one PID_DIV=2 update.
task update;
input integer sample_error;
begin
    error_in = sample_error;
    @(negedge clk);
    @(negedge clk);
end
endtask

initial begin
    #2000000;
    $fatal(1, "Simulation timeout");
end

initial begin
    reset_core();
    error_in = 8192;
    @(negedge clk);
    if (lock_out !== 16'h8000) $fatal(1, "Updated before PID_DIV elapsed");
    @(negedge clk);
    if (lock_out !== 16'h8200) $fatal(1, "Coarse positive step/clamp failed");
    if (reversed_out !== 16'h7E00) $fatal(1, "Feedback polarity failed");
    update(-8192);
    if (lock_out !== 16'h8000) $fatal(1, "Coarse negative step failed");
    update(131071);
    if (lock_out !== 16'h8200) $fatal(1, "Maximum signed input failed");
    update(-131072);
    if (lock_out !== 16'h8000 || dut.integral_acc !== 0)
        $fatal(1, "Minimum signed input/abs/coarse reset failed");

    reset_core();
    update(1024);
    if (lock_out !== 16'h8020 || dut.integral_acc !== 32'sd1024)
        $fatal(1, "Fine boundary or first PID step failed");
    update(0);
    if (lock_out !== 16'h8000) $fatal(1, "Derivative history/fine clamp failed");
    update(1025);
    if (lock_out !== 16'h8080 || dut.integral_acc !== 0)
        $fatal(1, "Coarse boundary failed");

    // Independent integer recurrence checks old-I timing, D timing and clamps.
    reset_core();
    ref_u = 32768; ref_i = 0; ref_last = 0;
    for (i = 0; i < 220; i = i + 1) begin
        e = ((i * 137) % 2301) - 1150;
        if ((e > 1024) || (e < -1024)) begin
            delta = e >>> 3;
            if (delta > 512) delta = 512;
            if (delta < -512) delta = -512;
            next_i = 0;
        end else begin
            delta = (e >>> 5) + (ref_i >>> 10) + ((e - ref_last) >>> 4);
            if (delta > 32) delta = 32;
            if (delta < -32) delta = -32;
            next_i = ref_i + e;
            if (next_i > 262143) next_i = 262143;
            if (next_i < -262143) next_i = -262143;
        end
        ref_u = ref_u + delta;
        if (ref_u > 40960) ref_u = 40960;
        if (ref_u < 24576) ref_u = 24576;
        ref_i = next_i; ref_last = e;
        update(e);
        if (lock_out !== ref_u[15:0] || dut.integral_acc !== ref_i)
            $fatal(1, "Reference recurrence mismatch at vector %0d", i);
    end

    reset_core();
    repeat (300) update(1024);
    if (dut.integral_acc !== 32'sd262143)
        $fatal(1, "Positive integral clamp failed");
    repeat (600) update(-1024);
    if (dut.integral_acc !== -32'sd262143)
        $fatal(1, "Negative integral clamp failed");

    reset_core();
    repeat (30) update(131071);
    if (lock_out !== 16'hA000) $fatal(1, "Upper DAC clamp failed");
    repeat (50) update(-131072);
    if (lock_out !== 16'h6000) $fatal(1, "Lower DAC clamp failed");

    reset_core();
    repeat (3) update(0);
    if (dut.locked !== 0) $fatal(1, "Lock asserted too early");
    update(0);
    if (dut.locked !== 1) $fatal(1, "Lock confirmation failed");
    update(512);
    if (dut.locked !== 1) $fatal(1, "Unlock hysteresis boundary failed");
    update(513);
    if (dut.locked !== 0) $fatal(1, "Unlock threshold failed");
    repeat (2) update(256);
    update(257);
    repeat (3) update(256);
    if (dut.locked !== 0) $fatal(1, "Lock samples were not consecutive");
    update(256);
    if (dut.locked !== 1) $fatal(1, "Reconfirmation failed");
    update(8192);
    if (dut.locked !== 0 || dut.integral_acc !== 0)
        $fatal(1, "Coarse reacquisition failed");

    reset_core();
    $display("PASS: PID arithmetic, cadence, signed extremes, limits and lock hysteresis");
    $finish;
end
endmodule
