`timescale 1ns / 1ps

// Derived from the user's pid_lock_controller.v control branch.
// Business interface: signed error in, unsigned DAC control word out.
// Sampling/filtering/acquisition and the optical plant are external.
module pid_error_lock #(
    parameter [15:0] DAC_INIT = 16'h8000,
    parameter [15:0] DAC_MIN = 16'h6000,
    parameter [15:0] DAC_MAX = 16'hA000,
    parameter integer PID_DIV = 5000,
    parameter [15:0] FINE_THRESHOLD = 16'd1024,
    parameter integer KP_COARSE_SHIFT = 3,
    parameter integer KP_FINE_SHIFT = 5,
    parameter integer KI_FINE_SHIFT = 10,
    parameter integer KD_FINE_SHIFT = 4,
    parameter [15:0] COARSE_MAX_STEP = 16'd512,
    parameter [15:0] FINE_MAX_STEP = 16'd32,
    parameter signed [31:0] INTEGRAL_LIMIT = 32'sd262143,
    parameter integer LOCK_CONFIRM = 64,
    parameter [15:0] UNLOCK_THRESHOLD = 16'd512,
    parameter ERROR_REVERSE = 1'b0
) (
    input wire clk,
    input wire rst_n,
    input wire signed [17:0] error_in,
    output reg [15:0] lock_out
);

reg [31:0] pid_div_count;
reg signed [31:0] integral_acc;
reg signed [31:0] last_error;
reg [31:0] lock_confirm_count;
// Status is internal by default; export separately if explicitly needed.
reg locked;

reg signed [31:0] error_ext;
reg [31:0] abs_error;
reg signed [31:0] integral_next;
reg signed [63:0] integral_candidate;
reg signed [63:0] step_candidate;
reg signed [31:0] step_calc;
reg signed [31:0] next_control;
reg [15:0] control_next;

always @(*) begin
    // Extend before negation and abs, including error_in = -131072.
    error_ext = {{14{error_in[17]}}, error_in};
    if (ERROR_REVERSE)
        error_ext = -error_ext;
    abs_error = (error_ext < 0) ? -error_ext : error_ext;

    integral_next = integral_acc;
    integral_candidate = $signed(integral_acc);
    step_candidate = 64'sd0;
    if (abs_error > {16'd0, FINE_THRESHOLD}) begin
        integral_next = 32'sd0;
        step_calc = error_ext >>> KP_COARSE_SHIFT;
        if (step_calc > $signed({16'd0, COARSE_MAX_STEP}))
            step_calc = $signed({16'd0, COARSE_MAX_STEP});
        else if (step_calc < -$signed({16'd0, COARSE_MAX_STEP}))
            step_calc = -$signed({16'd0, COARSE_MAX_STEP});
    end else begin
        // Use the old accumulator and previous PID-update error, as in source.
        integral_candidate = $signed(integral_acc);
        integral_candidate = integral_candidate + $signed(error_ext);
        if (integral_candidate > $signed(INTEGRAL_LIMIT))
            integral_next = INTEGRAL_LIMIT;
        else if (integral_candidate < -$signed({{32{INTEGRAL_LIMIT[31]}}, INTEGRAL_LIMIT}))
            integral_next = -INTEGRAL_LIMIT;
        else
            integral_next = integral_candidate[31:0];

        step_candidate = $signed(error_ext) >>> KP_FINE_SHIFT;
        integral_candidate = $signed(integral_acc);
        step_candidate = step_candidate + (integral_candidate >>> KI_FINE_SHIFT);
        integral_candidate = $signed(error_ext) - $signed(last_error);
        step_candidate = step_candidate + (integral_candidate >>> KD_FINE_SHIFT);
        if (step_candidate > $signed({16'd0, FINE_MAX_STEP}))
            step_calc = $signed({16'd0, FINE_MAX_STEP});
        else if (step_candidate < -$signed({16'd0, FINE_MAX_STEP}))
            step_calc = -$signed({16'd0, FINE_MAX_STEP});
        else
            step_calc = step_candidate[31:0];
    end

    next_control = $signed({16'd0, lock_out}) + step_calc;
    if (next_control < $signed({16'd0, DAC_MIN}))
        control_next = DAC_MIN;
    else if (next_control > $signed({16'd0, DAC_MAX}))
        control_next = DAC_MAX;
    else
        control_next = next_control[15:0];
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lock_out <= DAC_INIT;
        pid_div_count <= 32'd0;
        integral_acc <= 32'sd0;
        last_error <= 32'sd0;
        lock_confirm_count <= 32'd0;
        locked <= 1'b0;
    end else if (pid_div_count >= (PID_DIV - 1)) begin
        pid_div_count <= 32'd0;
        lock_out <= control_next;
        integral_acc <= integral_next;
        last_error <= error_ext;

        if (abs_error > {16'd0, FINE_THRESHOLD}) begin
            lock_confirm_count <= 32'd0;
            locked <= 1'b0;
        end else if (abs_error <= (FINE_THRESHOLD >> 2)) begin
            if (lock_confirm_count < LOCK_CONFIRM)
                lock_confirm_count <= lock_confirm_count + 1'b1;
            if ((lock_confirm_count + 1'b1) >= LOCK_CONFIRM)
                locked <= 1'b1;
        end else begin
            if (!locked)
                lock_confirm_count <= 32'd0;
            if (abs_error > {16'd0, UNLOCK_THRESHOLD}) begin
                lock_confirm_count <= 32'd0;
                locked <= 1'b0;
            end
        end
    end else begin
        pid_div_count <= pid_div_count + 1'b1;
    end
end

// synthesis translate_off
initial begin
    if (DAC_MIN > DAC_INIT || DAC_INIT > DAC_MAX || PID_DIV < 1 || LOCK_CONFIRM < 1)
        $fatal(1,"PID parameter error: output range or update/confirmation period");
    if (FINE_THRESHOLD < 4 || UNLOCK_THRESHOLD <= (FINE_THRESHOLD >> 2) || UNLOCK_THRESHOLD > FINE_THRESHOLD)
        $fatal(1,"PID parameter error: threshold hysteresis");
    if (INTEGRAL_LIMIT < 0 || KP_COARSE_SHIFT < 0 || KP_COARSE_SHIFT > 31 || KP_FINE_SHIFT < 0 || KP_FINE_SHIFT > 31 || KI_FINE_SHIFT < 0 || KI_FINE_SHIFT > 31 || KD_FINE_SHIFT < 0 || KD_FINE_SHIFT > 31)
        $fatal(1,"PID parameter error: accumulator limit or shift");
    if (ERROR_REVERSE != 0 && ERROR_REVERSE != 1)
        $fatal(1,"PID parameter error: polarity must be 0/1");
end
// synthesis translate_on
endmodule
