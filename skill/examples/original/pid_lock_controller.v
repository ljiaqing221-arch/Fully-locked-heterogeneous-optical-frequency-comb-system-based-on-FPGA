`timescale 1ns / 1ps

module pid_lock_controller #(
    parameter [15:0] DAC_INIT           = 16'h8000,
    parameter [15:0] DAC_MIN            = 16'h6000,
    parameter [15:0] DAC_MAX            = 16'hA000,
    // Bipolar DAC output: 16'h8000 = 0 V. These codes limit only the
    // acquisition triangle to approximately -0.2 V .. +0.2 V.
    parameter [15:0] SCAN_DAC_MIN       = 16'h7AE1,
    parameter [15:0] SCAN_DAC_MAX       = 16'h851F,
    parameter [15:0] SCAN_STEP          = 16'd64,
    parameter integer SCAN_DIV          = 2500,
    parameter integer PID_DIV           = 5000,
    parameter integer LOCK_EVENTS       = 4,
    parameter integer MIN_SCAN_SWEEPS   = 2,
    parameter [15:0] MIN_ADC_RANGE      = 16'd1024,
    // The expected -200 mV to +50 mV feature spans about 16'h2000 for a
    // 2 Vp-p ADC range. 16'h3000 leaves margin, while rejecting a bogus
    // near-rail-to-near-rail feature. Absolute voltage is not used as the
    // only qualification criterion.
    parameter [15:0] MAX_ADC_RANGE      = 16'h3000,
    parameter [15:0] CENTER_TOLERANCE   = 16'd1024,
    parameter [15:0] RANGE_TOLERANCE_MIN = 16'd1024,
    // AD9269 register 0x14 = 0x21 selects twos-complement output.
    // Only near-rail values are rejected by default. The measured peak
    // voltage is deliberately not used as a fixed absolute lock window.
    parameter ADC_TWOS_COMPLEMENT       = 1'b1,
    parameter [15:0] ADC_VALID_MIN      = 16'h0400,
    parameter [15:0] ADC_VALID_MAX      = 16'hFBFF,
    parameter integer STEP_AVG_LOG2     = 8,
    parameter integer MIN_VALID_STEPS   = 64,
    parameter integer MAX_INVALID_STEPS = 16,
    // Peak/dip confirmation is deliberately less strict than the final
    // MIN_ADC_RANGE check. Two robust steps establish a trend; the full range
    // and two-sweep consistency checks below remain the lock guardrails.
    parameter [15:0] SHAPE_PROMINENCE   = 16'd512,
    parameter [15:0] SHAPE_REVERSAL     = 16'd256,
    parameter integer SHAPE_CONFIRM_STEPS = 2,
    // A real scan can have long shoulders around a narrow resonance. Keep the
    // extrema window open for one complete rising sweep instead of timing out
    // after only 64 DAC steps. Derive it from the configured scan span so the
    // detector remains correct when SCAN_STEP is changed.
    parameter integer EXTREMA_MAX_STEPS =
        ((SCAN_DAC_MAX - SCAN_DAC_MIN) / SCAN_STEP) + 1,
    parameter integer ADC_SETTLE_CYCLES = 4096,
    parameter [15:0] WAVE_THRESHOLD     = 16'd512,
    parameter [15:0] FINE_THRESHOLD     = 16'd1024,
    parameter integer KP_COARSE_SHIFT   = 3,
    parameter integer KP_FINE_SHIFT     = 5,
    parameter integer KI_FINE_SHIFT     = 10,
    parameter integer KD_FINE_SHIFT     = 4,
    parameter [15:0] COARSE_MAX_STEP    = 16'd512,
    parameter [15:0] FINE_MAX_STEP      = 16'd32,
    parameter integer LOCK_CONFIRM      = 64,
    parameter [15:0] UNLOCK_THRESHOLD   = 16'd512,
    parameter ERROR_REVERSE             = 1'b0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        adc_ready,
    input  wire [15:0] adc_sample,
    input  wire        adc_otr,

    output reg  [15:0] ut,
    output wire        dac_update_en,
    output wire [15:0] filtered_adc,
    output wire [15:0] wave_avg,
    output reg  [15:0] min_adc_value,
    output reg  [15:0] max_adc_value,
    output reg  [15:0] target_adc,
    output reg  signed [17:0] error_now,
    output reg         lock_mode,
    output reg         locked,
    output reg  [2:0]  ctrl_state,
    output wire [15:0] abs_error_dbg,
    output wire [15:0] wave_count_dbg,
    output wire [7:0]  scan_sweep_count_dbg,
    output wire        wave_event_dbg,
    output reg         scan_valid_dbg,
    output reg  [15:0] invalid_step_count_dbg,
    output reg  signed [15:0] pid_step_dbg,
    output wire        wave_found
);

wire [15:0] filtered;
wire [15:0] avg;
wire        detector_valid;
wire [15:0] detector_step_sample;
wire        detector_step_valid;
wire        detector_step_clear;
wire [15:0] adc_offset_binary = ADC_TWOS_COMPLEMENT ?
                                (adc_sample ^ 16'h8000) : adc_sample;

adc_median_filter16 u_filter (
    .clk     (clk),
    .rst_n   (rst_n),
    .adc_in  (adc_offset_binary),
    .adc_out (filtered)
);

wave_detector16 #(
    .WINDOW_BITS    (4),
    .THRESHOLD      (WAVE_THRESHOLD),
    .ASSERT_SAMPLES (1),
    .CLEAR_SAMPLES  (4)
) u_wave_detector (
    .clk           (clk),
    .rst_n         (rst_n),
    .clear         (detector_step_clear),
    .sample_valid  (detector_step_valid),
    .adc_in        (detector_step_sample),
    .avg_out       (avg),
    .detector_valid(detector_valid),
    .wave_found    (wave_found)
);

assign filtered_adc  = filtered;
assign wave_avg      = avg;
assign dac_update_en = 1'b1;

reg [15:0] scan_div_cnt;
reg [15:0] pid_div_cnt;
reg [15:0] wave_count;
reg        scan_dir;
reg        detector_scan_dir_d;
reg [7:0]  scan_sweep_count;
reg [7:0]  valid_sweep_count;
reg        wave_found_d;
reg [15:0] settle_count;
reg        adc_settled;
reg        scan_window_active;

reg [31:0] step_sample_sum;
reg        step_otr_seen;
reg [15:0] valid_step_count;
reg [7:0]  invalid_step_count;
reg [15:0] previous_center;
reg [15:0] previous_range;
reg [15:0] previous_wave_min;
reg [15:0] previous_wave_max;
reg        previous_sweep_valid;
reg [15:0] lock_confirm_count;
reg [15:0] best_lock_ut;
reg [15:0] best_lock_distance;
reg        rise_arm;
reg        fall_arm;
reg        peak_shape_seen;
reg        dip_shape_seen;
reg [7:0]  rise_confirm_count;
reg [7:0]  fall_confirm_count;
reg        step_wave_seen;
reg [15:0] step_wave_baseline;
reg        extrema_trigger_pending;
reg        extrema_active;
reg [15:0] extrema_step_count;
reg [15:0] extrema_min_candidate;
reg [15:0] extrema_max_candidate;
reg [15:0] up_step_history_1;
reg [15:0] up_step_history_2;
reg [1:0]  up_step_history_count;
reg        wave_extrema_captured;
reg [15:0] wave_min_adc;
reg [15:0] wave_max_adc;

reg signed [31:0] integral_acc;
reg signed [17:0] last_error;
reg signed [17:0] delta_error;
reg signed [17:0] raw_error;
reg signed [31:0] step_calc;
reg signed [31:0] p_term;
reg signed [31:0] i_term;
reg signed [31:0] d_term;
reg signed [31:0] next_dac_signed;
reg [15:0] abs_error;

localparam [2:0] ST_WAIT_ADC = 3'd0;
localparam [2:0] ST_SCAN     = 3'd1;
localparam [2:0] ST_ACQUIRE  = 3'd2;
localparam [2:0] ST_COARSE   = 3'd3;
localparam [2:0] ST_FINE     = 3'd4;
localparam [2:0] ST_LOCKED   = 3'd5;

assign abs_error_dbg          = abs_error;
assign wave_count_dbg         = wave_count;
assign scan_sweep_count_dbg   = scan_sweep_count;
assign wave_event_dbg         = wave_found & ~wave_found_d;

localparam integer STEP_AVG_SAMPLES = (1 << STEP_AVG_LOG2);
wire step_average_window = scan_window_active &&
                           (scan_div_cnt >= (SCAN_DIV - STEP_AVG_SAMPLES));
wire [31:0] step_sum_with_current = step_sample_sum +
                                    (step_average_window ? {16'd0, filtered} : 32'd0);
wire [15:0] step_average = step_sum_with_current >> STEP_AVG_LOG2;
wire step_average_valid = !step_otr_seen && !adc_otr &&
                          (step_average >= ADC_VALID_MIN) &&
                          (step_average <= ADC_VALID_MAX);
// Waveform detection is performed once per settled DAC dwell. This matches
// the tens-of-hertz scan waveform seen on the oscilloscope; the previous
// 256-point/50 MHz detector observed only about 5.12 us and followed the slow
// resonance too closely to produce a useful deviation.
assign detector_step_sample = step_average;
wire detector_step_boundary = scan_window_active &&
                              (scan_div_cnt >= (SCAN_DIV - 1));
// Treat each half-sweep as an independent waveform. This allows the detector
// output to show both the shallow and deep traces caused by scan hysteresis,
// while the existing extrema/lock path below still records only the rising
// sweep. Direction changes clear the old moving history before the next
// half-sweep supplies a settled sample. An invalid/OTR dwell also breaks the
// history, so points on opposite sides of bad data cannot form a false peak.
assign detector_step_clear = !adc_ready || !adc_settled ||
                             !scan_window_active ||
                             (scan_dir != detector_scan_dir_d) ||
                             (detector_step_boundary &&
                              !step_average_valid);
assign detector_step_valid = detector_step_boundary &&
                             step_average_valid;
wire [15:0] wave_scan_range = wave_max_adc - wave_min_adc;
wire [15:0] wave_scan_center = wave_min_adc + (wave_scan_range >> 1);
wire [15:0] robust_valid_steps = valid_step_count + (step_average_valid ? 1'b1 : 1'b0);
wire [8:0] robust_invalid_steps = {1'b0, invalid_step_count} +
                                  (step_average_valid ? 1'b0 : 1'b1);
wire robust_statistics_valid = (robust_valid_steps >= MIN_VALID_STEPS) &&
                               (robust_invalid_steps <= MAX_INVALID_STEPS);
wire robust_sweep_valid = robust_statistics_valid && wave_extrema_captured &&
                          (wave_scan_range >= MIN_ADC_RANGE) &&
                          (wave_scan_range <= MAX_ADC_RANGE);
wire [15:0] next_scan_center = wave_scan_center;
wire [15:0] center_difference = (next_scan_center >= previous_center) ?
                                (next_scan_center - previous_center) :
                                (previous_center - next_scan_center);
wire [15:0] range_difference = (wave_scan_range >= previous_range) ?
                               (wave_scan_range - previous_range) :
                               (previous_range - wave_scan_range);
wire [15:0] adaptive_range_tolerance = ((previous_range >> 2) > RANGE_TOLERANCE_MIN) ?
                                       (previous_range >> 2) : RANGE_TOLERANCE_MIN;
wire [16:0] accepted_min_sum = {1'b0, previous_wave_min} + {1'b0, wave_min_adc};
wire [16:0] accepted_max_sum = {1'b0, previous_wave_max} + {1'b0, wave_max_adc};
wire [15:0] accepted_min = accepted_min_sum[16:1];
wire [15:0] accepted_max = accepted_max_sum[16:1];
wire [15:0] accepted_target = accepted_min + ((accepted_max - accepted_min) >> 1);
wire [15:0] lock_point_distance = (step_average >= previous_center) ?
                                  (step_average - previous_center) :
                                  (previous_center - step_average);
function [15:0] median3;
    input [15:0] a;
    input [15:0] b;
    input [15:0] c;
    begin
        if (a > b) begin
            if (b > c)
                median3 = b;
            else if (a > c)
                median3 = c;
            else
                median3 = a;
        end else begin
            if (a > c)
                median3 = a;
            else if (b > c)
                median3 = c;
            else
                median3 = b;
        end
    end
endfunction

// Extrema use a median of three consecutive DAC-step averages. A single bad
// DAC dwell therefore cannot become a permanent maximum or minimum.
wire [15:0] robust_step_average = median3(up_step_history_2,
                                          up_step_history_1,
                                          step_average);
wire robust_step_ready = step_average_valid && (up_step_history_count >= 2);
wire step_wave_event = step_wave_seen ||
                       (wave_event_dbg && !adc_otr && detector_valid);
wire [15:0] extrema_start_min =
    (robust_step_average < step_wave_baseline) ?
    robust_step_average : step_wave_baseline;
wire [15:0] extrema_start_max =
    (robust_step_average > step_wave_baseline) ?
    robust_step_average : step_wave_baseline;
wire [15:0] extrema_min_next =
    (robust_step_average < extrema_min_candidate) ?
    robust_step_average : extrema_min_candidate;
wire [15:0] extrema_max_next =
    (robust_step_average > extrema_max_candidate) ?
    robust_step_average : extrema_max_candidate;
wire [15:0] extrema_range_next = extrema_max_next - extrema_min_next;
wire [15:0] rise_from_min = robust_step_average - extrema_min_next;
wire [15:0] fall_from_max = extrema_max_next - robust_step_average;
wire scan_shape_valid = wave_extrema_captured &&
                        (peak_shape_seen || dip_shape_seen);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        detector_scan_dir_d <= 1'b0;
    else
        detector_scan_dir_d <= scan_dir;
end

always @(*) begin
    raw_error = $signed({2'b00, target_adc}) - $signed({2'b00, filtered});
    if (ERROR_REVERSE)
        raw_error = -raw_error;

    if (raw_error < 0)
        abs_error = (~raw_error[15:0]) + 1'b1;
    else
        abs_error = raw_error[15:0];
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ut                <= DAC_INIT;
        min_adc_value     <= 16'd0;
        max_adc_value     <= 16'd0;
        target_adc        <= 16'h8000;
        error_now         <= 18'sd0;
        lock_mode         <= 1'b0;
        locked            <= 1'b0;
        ctrl_state        <= ST_WAIT_ADC;
        scan_div_cnt      <= 16'd0;
        pid_div_cnt       <= 16'd0;
        wave_count        <= 16'd0;
        scan_dir          <= 1'b0;
        scan_sweep_count  <= 8'd0;
        valid_sweep_count <= 8'd0;
        wave_found_d      <= 1'b0;
        settle_count      <= 16'd0;
        adc_settled       <= 1'b0;
        scan_window_active <= 1'b0;
        step_sample_sum   <= 32'd0;
        step_otr_seen     <= 1'b0;
        valid_step_count  <= 16'd0;
        invalid_step_count <= 8'd0;
        previous_center   <= 16'd0;
        previous_range    <= 16'd0;
        previous_wave_min <= 16'd0;
        previous_wave_max <= 16'd0;
        previous_sweep_valid <= 1'b0;
        lock_confirm_count <= 16'd0;
        best_lock_ut      <= DAC_INIT;
        best_lock_distance <= 16'hFFFF;
        rise_arm          <= 1'b0;
        fall_arm          <= 1'b0;
        peak_shape_seen   <= 1'b0;
        dip_shape_seen    <= 1'b0;
        rise_confirm_count <= 8'd0;
        fall_confirm_count <= 8'd0;
        step_wave_seen    <= 1'b0;
        step_wave_baseline <= 16'd0;
        extrema_trigger_pending <= 1'b0;
        extrema_active    <= 1'b0;
        extrema_step_count <= 16'd0;
        extrema_min_candidate <= 16'd0;
        extrema_max_candidate <= 16'd0;
        up_step_history_1 <= 16'd0;
        up_step_history_2 <= 16'd0;
        up_step_history_count <= 2'd0;
        wave_extrema_captured <= 1'b0;
        wave_min_adc      <= 16'd0;
        wave_max_adc      <= 16'd0;
        integral_acc      <= 32'sd0;
        last_error        <= 18'sd0;
        delta_error       <= 18'sd0;
        p_term            <= 32'sd0;
        i_term            <= 32'sd0;
        d_term            <= 32'sd0;
        pid_step_dbg      <= 16'sd0;
        scan_valid_dbg    <= 1'b0;
        invalid_step_count_dbg <= 16'd0;
    end else begin
        wave_found_d <= wave_found;

        if (!adc_ready) begin
            // No scan or min/max accumulation before AD9269 register setup completes.
            ut               <= DAC_INIT;
            min_adc_value    <= 16'd0;
            max_adc_value    <= 16'd0;
            target_adc       <= 16'h8000;
            error_now        <= 18'sd0;
            lock_mode        <= 1'b0;
            locked           <= 1'b0;
            ctrl_state       <= ST_WAIT_ADC;
            scan_div_cnt     <= 16'd0;
            pid_div_cnt      <= 16'd0;
            wave_count       <= 16'd0;
            scan_dir         <= 1'b0;
            scan_sweep_count <= 8'd0;
            valid_sweep_count <= 8'd0;
            settle_count     <= 16'd0;
            adc_settled      <= 1'b0;
            scan_window_active <= 1'b0;
            step_sample_sum  <= 32'd0;
            step_otr_seen    <= 1'b0;
            valid_step_count <= 16'd0;
            invalid_step_count <= 8'd0;
            previous_center  <= 16'd0;
            previous_range   <= 16'd0;
            previous_wave_min <= 16'd0;
            previous_wave_max <= 16'd0;
            previous_sweep_valid <= 1'b0;
            lock_confirm_count <= 16'd0;
            best_lock_ut     <= DAC_INIT;
            best_lock_distance <= 16'hFFFF;
            rise_arm         <= 1'b0;
            fall_arm         <= 1'b0;
            peak_shape_seen  <= 1'b0;
            dip_shape_seen   <= 1'b0;
            rise_confirm_count <= 8'd0;
            fall_confirm_count <= 8'd0;
            step_wave_seen   <= 1'b0;
            step_wave_baseline <= 16'd0;
            extrema_trigger_pending <= 1'b0;
            extrema_active   <= 1'b0;
            extrema_step_count <= 16'd0;
            extrema_min_candidate <= 16'd0;
            extrema_max_candidate <= 16'd0;
            up_step_history_1 <= 16'd0;
            up_step_history_2 <= 16'd0;
            up_step_history_count <= 2'd0;
            wave_extrema_captured <= 1'b0;
            wave_min_adc     <= 16'd0;
            wave_max_adc     <= 16'd0;
            integral_acc     <= 32'sd0;
            last_error       <= 18'sd0;
            pid_step_dbg     <= 16'sd0;
            scan_valid_dbg   <= 1'b0;
            invalid_step_count_dbg <= 16'd0;
        end else if (!adc_settled) begin
            // Give the ADC output and median filter a short settling interval.
            ut           <= DAC_INIT;
            ctrl_state   <= ST_WAIT_ADC;
            pid_step_dbg <= 16'sd0;
            if (settle_count >= (ADC_SETTLE_CYCLES - 1)) begin
                adc_settled  <= 1'b1;
                ut           <= SCAN_DAC_MIN;
                scan_window_active <= 1'b0;
                step_sample_sum <= 32'd0;
                step_otr_seen <= 1'b0;
                valid_step_count <= 16'd0;
                invalid_step_count <= 8'd0;
                best_lock_ut <= SCAN_DAC_MIN;
                best_lock_distance <= 16'hFFFF;
                rise_arm <= 1'b0;
                fall_arm <= 1'b0;
                peak_shape_seen <= 1'b0;
                dip_shape_seen <= 1'b0;
                rise_confirm_count <= 8'd0;
                fall_confirm_count <= 8'd0;
                step_wave_seen <= 1'b0;
                step_wave_baseline <= 16'd0;
                extrema_trigger_pending <= 1'b0;
                extrema_active <= 1'b0;
                extrema_step_count <= 16'd0;
                extrema_min_candidate <= 16'd0;
                extrema_max_candidate <= 16'd0;
                up_step_history_1 <= 16'd0;
                up_step_history_2 <= 16'd0;
                up_step_history_count <= 2'd0;
                wave_extrema_captured <= 1'b0;
                wave_min_adc <= 16'd0;
                wave_max_adc <= 16'd0;
            end else begin
                settle_count <= settle_count + 1'b1;
            end
        end else if (!lock_mode) begin
            error_now    <= raw_error;
            locked       <= 1'b0;
            ctrl_state   <= (wave_count == 16'd0) ? ST_SCAN : ST_ACQUIRE;
            pid_step_dbg <= 16'sd0;
            pid_div_cnt  <= 16'd0;
            integral_acc <= 32'sd0;
            last_error   <= 18'sd0;

            // Only the last STEP_AVG_SAMPLES samples of each DAC dwell are averaged.
            // This excludes most DAC/laser settling transients from the extrema.
            if (step_average_window)
                step_sample_sum <= step_sample_sum + {16'd0, filtered};
            if (scan_window_active && adc_otr)
                step_otr_seen <= 1'b1;

            if (scan_window_active && wave_event_dbg && !adc_otr && detector_valid &&
                (wave_count < 16'hFFFF))
                wave_count <= wave_count + 1'b1;
            if (scan_window_active && !scan_dir && wave_event_dbg &&
                !adc_otr && detector_valid) begin
                step_wave_seen <= 1'b1;
                step_wave_baseline <= avg;
            end

            if (scan_div_cnt >= (SCAN_DIV - 1)) begin
                scan_div_cnt <= 16'd0;
                step_wave_seen <= 1'b0;
                if (!scan_window_active) begin
                    // Hold SCAN_DAC_MIN for one interval before opening the first window.
                    scan_window_active <= 1'b1;
                    step_sample_sum <= 32'd0;
                    step_otr_seen <= 1'b0;
                    valid_step_count <= 16'd0;
                    invalid_step_count <= 8'd0;
                    best_lock_ut <= SCAN_DAC_MIN;
                    best_lock_distance <= 16'hFFFF;
                    rise_arm <= 1'b0;
                    fall_arm <= 1'b0;
                    peak_shape_seen <= 1'b0;
                    dip_shape_seen <= 1'b0;
                    rise_confirm_count <= 8'd0;
                    fall_confirm_count <= 8'd0;
                    step_wave_baseline <= 16'd0;
                    extrema_trigger_pending <= 1'b0;
                    extrema_active <= 1'b0;
                    extrema_step_count <= 16'd0;
                    extrema_min_candidate <= 16'd0;
                    extrema_max_candidate <= 16'd0;
                    up_step_history_1 <= 16'd0;
                    up_step_history_2 <= 16'd0;
                    up_step_history_count <= 2'd0;
                    wave_extrema_captured <= 1'b0;
                    wave_min_adc <= 16'd0;
                    wave_max_adc <= 16'd0;
                    wave_count   <= 16'd0;
                end else begin
                    // Close the current DAC dwell and contribute one averaged value.
                    step_sample_sum <= 32'd0;
                    step_otr_seen   <= 1'b0;
                    if (step_average_valid) begin
                        valid_step_count <= valid_step_count + 1'b1;

                        // On the rising scan, remember the DAC code nearest the
                        // previous qualified center so PID can start near lock.
                        if (!scan_dir && previous_sweep_valid &&
                            (lock_point_distance < best_lock_distance)) begin
                            best_lock_distance <= lock_point_distance;
                            best_lock_ut       <= ut;
                        end

                        if (!scan_dir) begin
                            // Keep a three-DAC-step history only for extrema. The
                            // wave detector itself still sees the original filtered
                            // ADC stream and is intentionally unchanged.
                            up_step_history_2 <= up_step_history_1;
                            up_step_history_1 <= step_average;
                            if (up_step_history_count < 2)
                                up_step_history_count <= up_step_history_count + 1'b1;

                            if (!wave_extrema_captured && !extrema_active &&
                                step_wave_event)
                                extrema_trigger_pending <= 1'b1;

                            if (robust_step_ready && !wave_extrema_captured) begin
                                if (!extrema_active &&
                                    (extrema_trigger_pending || step_wave_event)) begin
                                    // The existing detector opens the extrema
                                    // window. Nothing before this point can enter
                                    // the target calculation.
                                    extrema_active <= 1'b1;
                                    extrema_trigger_pending <= 1'b0;
                                    extrema_step_count <= 16'd1;
                                    extrema_min_candidate <= extrema_start_min;
                                    extrema_max_candidate <= extrema_start_max;
                                    rise_arm <= 1'b0;
                                    fall_arm <= 1'b0;
                                    rise_confirm_count <= 8'd0;
                                    fall_confirm_count <= 8'd0;
                                end else if (extrema_active) begin
                                    extrema_min_candidate <= extrema_min_next;
                                    extrema_max_candidate <= extrema_max_next;
                                    extrema_step_count <= extrema_step_count + 1'b1;

                                    if (!rise_arm) begin
                                        if (rise_from_min >= SHAPE_PROMINENCE) begin
                                            if (rise_confirm_count >= SHAPE_CONFIRM_STEPS - 1) begin
                                                rise_arm <= 1'b1;
                                                rise_confirm_count <= 8'd0;
                                            end else begin
                                                rise_confirm_count <= rise_confirm_count + 1'b1;
                                            end
                                        end else if (rise_from_min <
                                                     SHAPE_REVERSAL) begin
                                            // Do not erase a nearly confirmed
                                            // broad edge for a small ripple.
                                            rise_confirm_count <= 8'd0;
                                        end
                                    end

                                    if (!fall_arm) begin
                                        if (fall_from_max >= SHAPE_PROMINENCE) begin
                                            if (fall_confirm_count >= SHAPE_CONFIRM_STEPS - 1) begin
                                                fall_arm <= 1'b1;
                                                fall_confirm_count <= 8'd0;
                                            end else begin
                                                fall_confirm_count <= fall_confirm_count + 1'b1;
                                            end
                                        end else if (fall_from_max <
                                                     SHAPE_REVERSAL) begin
                                            fall_confirm_count <= 8'd0;
                                        end
                                    end

                                    // Freeze only after a confirmed reversal
                                    // whose range is already large enough to
                                    // be usable. A small shoulder must not hide
                                    // a later, genuine resonance in this sweep.
                                    if (rise_arm &&
                                        (fall_from_max >= SHAPE_REVERSAL)) begin
                                        if (extrema_range_next >= MIN_ADC_RANGE) begin
                                            peak_shape_seen <= 1'b1;
                                            wave_extrema_captured <= 1'b1;
                                            wave_min_adc <= extrema_min_next;
                                            wave_max_adc <= extrema_max_next;
                                            extrema_active <= 1'b0;
                                            extrema_trigger_pending <= 1'b0;
                                        end else begin
                                            // A completed but too-small bump is
                                            // not the target feature. Restart at
                                            // its return point and keep looking.
                                            extrema_step_count <= 16'd1;
                                            extrema_min_candidate <= robust_step_average;
                                            extrema_max_candidate <= robust_step_average;
                                            rise_arm <= 1'b0;
                                            fall_arm <= 1'b0;
                                            rise_confirm_count <= 8'd0;
                                            fall_confirm_count <= 8'd0;
                                        end
                                    end else if (fall_arm &&
                                                 (rise_from_min >= SHAPE_REVERSAL)) begin
                                        if (extrema_range_next >= MIN_ADC_RANGE) begin
                                            dip_shape_seen <= 1'b1;
                                            wave_extrema_captured <= 1'b1;
                                            wave_min_adc <= extrema_min_next;
                                            wave_max_adc <= extrema_max_next;
                                            extrema_active <= 1'b0;
                                            extrema_trigger_pending <= 1'b0;
                                        end else begin
                                            extrema_step_count <= 16'd1;
                                            extrema_min_candidate <= robust_step_average;
                                            extrema_max_candidate <= robust_step_average;
                                            rise_arm <= 1'b0;
                                            fall_arm <= 1'b0;
                                            rise_confirm_count <= 8'd0;
                                            fall_confirm_count <= 8'd0;
                                        end
                                    end else if (extrema_step_count >=
                                                 (EXTREMA_MAX_STEPS - 1)) begin
                                        // Stop at the configured half-sweep
                                        // bound if no usable reversal appeared.
                                        extrema_active <= 1'b0;
                                        extrema_trigger_pending <= 1'b0;
                                        extrema_step_count <= 16'd0;
                                        rise_arm <= 1'b0;
                                        fall_arm <= 1'b0;
                                        rise_confirm_count <= 8'd0;
                                        fall_confirm_count <= 8'd0;
                                    end
                                end
                            end
                        end
                    end else if (invalid_step_count != 8'hFF) begin
                        invalid_step_count <= invalid_step_count + 1'b1;
                        if (!scan_dir && !wave_extrema_captured) begin
                            // Never bridge an extrema candidate across an OTR or
                            // otherwise invalid DAC dwell.
                            up_step_history_count <= 2'd0;
                            extrema_trigger_pending <= 1'b0;
                            extrema_active <= 1'b0;
                            extrema_step_count <= 16'd0;
                            rise_arm <= 1'b0;
                            fall_arm <= 1'b0;
                            rise_confirm_count <= 8'd0;
                            fall_confirm_count <= 8'd0;
                        end
                    end

                    if (!scan_dir) begin
                        if (ut >= (SCAN_DAC_MAX - SCAN_STEP)) begin
                            ut       <= SCAN_DAC_MAX;
                            scan_dir <= 1'b1;
                        end else begin
                            ut <= ut + SCAN_STEP;
                        end
                    end else begin
                        if (ut <= (SCAN_DAC_MIN + SCAN_STEP)) begin
                            ut       <= SCAN_DAC_MIN;
                            scan_dir <= 1'b0;

                            // A down-ramp ending at SCAN_DAC_MIN completes one robust window.
                            if (scan_sweep_count != 8'hFF)
                                scan_sweep_count <= scan_sweep_count + 1'b1;

                            scan_valid_dbg <= robust_sweep_valid && scan_shape_valid;
                            invalid_step_count_dbg <= {7'd0, robust_invalid_steps};

                            if (robust_sweep_valid && scan_shape_valid) begin
                                previous_center <= wave_scan_center;
                                previous_range  <= wave_scan_range;
                                previous_wave_min <= wave_min_adc;
                                previous_wave_max <= wave_max_adc;
                                if (previous_sweep_valid &&
                                    (center_difference <= CENTER_TOLERANCE) &&
                                    (range_difference <= adaptive_range_tolerance)) begin
                                    if (valid_sweep_count != 8'hFF)
                                        valid_sweep_count <= valid_sweep_count + 1'b1;
                                    if ((valid_sweep_count + 1'b1) >= MIN_SCAN_SWEEPS) begin
                                        min_adc_value <= accepted_min;
                                        max_adc_value <= accepted_max;
                                        target_adc <= accepted_target;
                                        lock_mode  <= 1'b1;
                                        ut         <= best_lock_ut;
                                    end
                                end else begin
                                    valid_sweep_count <= 8'd1;
                                end
                                previous_sweep_valid <= 1'b1;
                            end else begin
                                valid_sweep_count     <= 8'd0;
                                previous_sweep_valid <= 1'b0;
                            end

                            valid_step_count   <= 16'd0;
                            invalid_step_count <= 8'd0;
                            best_lock_ut       <= SCAN_DAC_MIN;
                            best_lock_distance <= 16'hFFFF;
                            rise_arm           <= 1'b0;
                            fall_arm           <= 1'b0;
                            peak_shape_seen    <= 1'b0;
                            dip_shape_seen     <= 1'b0;
                            rise_confirm_count <= 8'd0;
                            fall_confirm_count <= 8'd0;
                            step_wave_baseline <= 16'd0;
                            extrema_trigger_pending <= 1'b0;
                            extrema_active     <= 1'b0;
                            extrema_step_count <= 16'd0;
                            extrema_min_candidate <= 16'd0;
                            extrema_max_candidate <= 16'd0;
                            up_step_history_1  <= 16'd0;
                            up_step_history_2  <= 16'd0;
                            up_step_history_count <= 2'd0;
                            wave_extrema_captured <= 1'b0;
                            wave_min_adc       <= 16'd0;
                            wave_max_adc       <= 16'd0;
                            wave_count         <= 16'd0;
                        end else begin
                            ut <= ut - SCAN_STEP;
                        end
                    end
                end
            end else begin
                scan_div_cnt <= scan_div_cnt + 1'b1;
            end
        end else begin
            error_now <= raw_error;
            if (pid_div_cnt >= (PID_DIV - 1)) begin
                pid_div_cnt <= 16'd0;
                delta_error <= raw_error - last_error;
                last_error  <= raw_error;

                if (abs_error > FINE_THRESHOLD) begin
                    ctrl_state   <= ST_COARSE;
                    locked       <= 1'b0;
                    lock_confirm_count <= 16'd0;
                    integral_acc <= 32'sd0;
                    p_term       <= 32'sd0;
                    i_term       <= 32'sd0;
                    d_term       <= 32'sd0;
                    step_calc = raw_error >>> KP_COARSE_SHIFT;
                    if (step_calc > $signed({16'd0, COARSE_MAX_STEP}))
                        step_calc = $signed({16'd0, COARSE_MAX_STEP});
                    else if (step_calc < -$signed({16'd0, COARSE_MAX_STEP}))
                        step_calc = -$signed({16'd0, COARSE_MAX_STEP});
                end else begin
                    ctrl_state <= locked ? ST_LOCKED : ST_FINE;
                    if (abs_error <= (FINE_THRESHOLD >> 2)) begin
                        if (lock_confirm_count < LOCK_CONFIRM)
                            lock_confirm_count <= lock_confirm_count + 1'b1;
                        if ((lock_confirm_count + 1'b1) >= LOCK_CONFIRM)
                            locked <= 1'b1;
                    end else begin
                        if (!locked)
                            lock_confirm_count <= 16'd0;
                        if (abs_error > UNLOCK_THRESHOLD) begin
                            lock_confirm_count <= 16'd0;
                            locked <= 1'b0;
                        end
                    end

                    if ((integral_acc + raw_error) > 32'sd262143)
                        integral_acc <= 32'sd262143;
                    else if ((integral_acc + raw_error) < -32'sd262143)
                        integral_acc <= -32'sd262143;
                    else
                        integral_acc <= integral_acc + raw_error;

                    p_term = raw_error >>> KP_FINE_SHIFT;
                    i_term = integral_acc >>> KI_FINE_SHIFT;
                    d_term = (raw_error - last_error) >>> KD_FINE_SHIFT;
                    step_calc = p_term + i_term + d_term;

                    if (step_calc > $signed({16'd0, FINE_MAX_STEP}))
                        step_calc = $signed({16'd0, FINE_MAX_STEP});
                    else if (step_calc < -$signed({16'd0, FINE_MAX_STEP}))
                        step_calc = -$signed({16'd0, FINE_MAX_STEP});
                end

                next_dac_signed = $signed({16'd0, ut}) + step_calc;
                pid_step_dbg <= step_calc[15:0];
                if (next_dac_signed < $signed({16'd0, DAC_MIN}))
                    ut <= DAC_MIN;
                else if (next_dac_signed > $signed({16'd0, DAC_MAX}))
                    ut <= DAC_MAX;
                else
                    ut <= next_dac_signed[15:0];
            end else begin
                pid_div_cnt <= pid_div_cnt + 1'b1;
            end
        end
    end
end

endmodule
