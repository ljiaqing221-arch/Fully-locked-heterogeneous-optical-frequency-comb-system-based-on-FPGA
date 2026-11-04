`timescale 1ns / 1ps

module tb_pid_lock_controller_portable;
reg clk = 1'b0;
reg rst_n = 1'b0;
reg adc_ready = 1'b0;
reg adc_otr = 1'b0;
reg [2:0] signal_mode = 3'd0;
reg [15:0] adc_sample;
wire [15:0] ut;
wire [15:0] filtered_adc;
wire [15:0] min_adc_value;
wire [15:0] max_adc_value;
wire [15:0] target_adc;
wire lock_mode;
wire locked;
wire [2:0] ctrl_state;
wire [15:0] wave_count_dbg;
wire [7:0] scan_sweep_count_dbg;
wire wave_event_dbg;
integer smooth_event_total = 0;

always #5 clk = ~clk;

always @(posedge clk) begin
    if ((signal_mode == 3'd6) && wave_event_dbg)
        smooth_event_total <= smooth_event_total + 1;
end

always @(*) begin
    // A smooth resonance valley shaped like the oscilloscope trace: gradual
    // shoulder, steep descent, finite-width bottom, and recovery.
    if ((signal_mode == 3'd6) && (ut == 16'd1600))
        adc_sample = 16'h0200; // offset-binary 8200
    else if ((signal_mode == 3'd6) && (ut == 16'd1700))
        adc_sample = 16'hFE00; // offset-binary 7E00
    else if ((signal_mode == 3'd6) && (ut == 16'd1800))
        adc_sample = 16'hF800; // offset-binary 7800
    else if ((signal_mode == 3'd6) && (ut == 16'd1900))
        adc_sample = 16'hF000; // offset-binary 7000
    else if ((signal_mode == 3'd6) &&
             ((ut == 16'd2000) || (ut == 16'd2100)))
        adc_sample = 16'hE800; // offset-binary 6800, resonance bottom
    else if ((signal_mode == 3'd6) && (ut == 16'd2200))
        adc_sample = 16'hF800; // offset-binary 7800
    else if ((signal_mode == 3'd6) && (ut == 16'd2300))
        adc_sample = 16'hFE00; // offset-binary 7E00
    else if ((signal_mode == 3'd6) && (ut == 16'd2400))
        adc_sample = 16'h0200; // offset-binary 8200
    else if (signal_mode == 3'd6)
        adc_sample = 16'h0400; // offset-binary 8400, local shoulder
    else if ((signal_mode == 3'd5) && (ut == 16'd1300))
        adc_sample = 16'h7000; // isolated high pollution: offset-binary F000
    else if ((signal_mode == 3'd5) && (ut == 16'd1500))
        adc_sample = 16'h8800; // isolated low pollution: offset-binary 0800
    else if ((signal_mode == 3'd5) && (ut >= 16'd1800) && (ut <= 16'd2200))
        adc_sample = 16'h0400; // real feature: offset-binary 8400
    else if (signal_mode == 3'd5)
        adc_sample = 16'hF000; // real baseline: offset-binary 7000
    else if ((signal_mode == 3'd2) && ut[8])
        adc_sample = 16'h7FF8; // twos-complement raw for offset-binary FFF8
    else if ((signal_mode == 3'd2) && !ut[8])
        adc_sample = 16'h8008; // twos-complement raw for offset-binary 0008
    else if ((signal_mode == 3'd4) && (ut >= 16'd1800) && (ut <= 16'd2200))
        adc_sample = 16'h2400; // +281.25 mV, offset-binary A400
    else if (signal_mode == 3'd4)
        adc_sample = 16'h1000; // +125 mV, offset-binary 9000
    else if ((signal_mode == 3'd1) && (ut >= 16'd1800) && (ut <= 16'd2200))
        adc_sample = 16'h0400; // +31.25 mV, offset-binary 8400
    else if (signal_mode == 3'd3)
        adc_sample = (16'h7000 + ((ut - 16'd1000) << 1)) ^ 16'h8000;
    else
        adc_sample = 16'hF000; // -125 mV, offset-binary 7000
end

pid_lock_controller #(
    .DAC_INIT(16'd2000), .DAC_MIN(16'd1000), .DAC_MAX(16'd3000),
    .SCAN_DAC_MIN(16'd1000), .SCAN_DAC_MAX(16'd3000),
    // Keep each DAC value longer than the detector's clear interval so an
    // event is associated with the DAC step that actually caused it.
    .SCAN_STEP(16'd100), .SCAN_DIV(100), .PID_DIV(2),
    .LOCK_EVENTS(2), .MIN_SCAN_SWEEPS(2), .MIN_ADC_RANGE(16'd1000),
    .CENTER_TOLERANCE(16'd50),
    .STEP_AVG_LOG2(3), .MIN_VALID_STEPS(20), .MAX_INVALID_STEPS(2),
    .ADC_SETTLE_CYCLES(16),
    .WAVE_THRESHOLD(16'd100), .FINE_THRESHOLD(16'd200),
    .LOCK_CONFIRM(4), .UNLOCK_THRESHOLD(16'd100)
) dut (
    .clk(clk), .rst_n(rst_n), .adc_ready(adc_ready),
    .adc_sample(adc_sample), .adc_otr(adc_otr), .ut(ut),
    .dac_update_en(), .filtered_adc(filtered_adc), .wave_avg(),
    .min_adc_value(min_adc_value), .max_adc_value(max_adc_value),
    .target_adc(target_adc), .error_now(), .lock_mode(lock_mode),
    .locked(locked), .ctrl_state(ctrl_state), .abs_error_dbg(),
    .wave_count_dbg(wave_count_dbg),
    .scan_sweep_count_dbg(scan_sweep_count_dbg), .wave_event_dbg(wave_event_dbg),
    .scan_valid_dbg(), .invalid_step_count_dbg(), .pid_step_dbg(), .wave_found()
);

initial begin
    #30 rst_n = 1'b1;
    #20 adc_ready = 1'b1;

    // A flat ADC input must complete scans without entering lock mode.
    repeat (10000) @(posedge clk);
    if (lock_mode || (min_adc_value != 16'd0) || (max_adc_value != 16'd0))
        $fatal(1, "flat-input rejection failed: lock=%0d min=%0d max=%0d",
               lock_mode, min_adc_value, max_adc_value);

    // Rail-to-rail samples are rejected and must never qualify for lock.
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    signal_mode = 3'd2;
    rst_n = 1'b1;
    adc_ready = 1'b1;
    repeat (10000) @(posedge clk);
    if (lock_mode)
        $fatal(1, "rail-value rejection failed");

    // A clean but monotonic response has range, but no peak/dip reversal.
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    signal_mode = 3'd3;
    rst_n = 1'b1;
    adc_ready = 1'b1;
    repeat (10000) @(posedge clk);
    if (lock_mode || (min_adc_value != 16'd0) || (max_adc_value != 16'd0))
        $fatal(1, "monotonic-shape rejection failed");

    // The millisecond-scale, smooth resonance valley must be detected even
    // though adjacent 50 MHz ADC samples are almost identical.
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    signal_mode = 3'd6;
    rst_n = 1'b1;
    adc_ready = 1'b1;
    repeat (20000) begin
        @(posedge clk);
        if (lock_mode) begin
            if ((min_adc_value != 16'h6800) || (max_adc_value != 16'h8400) ||
                (target_adc != 16'h7600))
                $fatal(1, "smooth resonance statistics failed: min=%0d max=%0d target=%0d",
                       min_adc_value, max_adc_value, target_adc);
            $display("SMOOTH_RESONANCE_PASS events=%0d min=%0d max=%0d target=%0d",
                     wave_count_dbg, min_adc_value, max_adc_value, target_adc);
            break;
        end
    end
    if (!lock_mode)
        $fatal(1, "smooth resonance valley was not detected: sweeps=%0d scan_events=%0d total_events=%0d scan_valid=%0d captured=%0d active=%0d cand_min=%h cand_max=%h wave_min=%h wave_max=%h",
               scan_sweep_count_dbg, wave_count_dbg, smooth_event_total,
               dut.scan_valid_dbg,
               dut.wave_extrema_captured, dut.extrema_active,
               dut.extrema_min_candidate, dut.extrema_max_candidate,
               dut.wave_min_adc, dut.wave_max_adc);

    // Two isolated, non-OTR, near-rail DAC dwells occur before a real feature.
    // They may trigger the existing wave detector, but must not pollute the
    // extrema or the target.
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    signal_mode = 3'd5;
    rst_n = 1'b1;
    adc_ready = 1'b1;
    repeat (20000) begin
        @(posedge clk);
        if (lock_mode) begin
            if ((min_adc_value != 16'h7000) || (max_adc_value != 16'h8400) ||
                (target_adc != 16'h7A00))
                $fatal(1, "polluted extrema accepted: min=%0d max=%0d target=%0d",
                       min_adc_value, max_adc_value, target_adc);
            $display("POLLUTION_REJECTION_PASS min=%0d max=%0d target=%0d",
                     min_adc_value, max_adc_value, target_adc);
            signal_mode = 3'd0;
            rst_n = 1'b0;
            repeat (4) @(posedge clk);
            signal_mode = 3'd4;
            rst_n = 1'b1;
            adc_ready = 1'b1;
            break;
        end
    end
    if (!rst_n || (signal_mode != 3'd4))
        $fatal(1, "pollution-rejection feature did not enter lock mode: sweeps=%0d wave=%0d scan_valid=%0d captured=%0d cand=%0d min=%0d max=%0d",
               scan_sweep_count_dbg, wave_count_dbg, dut.scan_valid_dbg,
               dut.wave_extrema_captured, dut.extrema_active,
               dut.wave_min_adc, dut.wave_max_adc);

    // Reinitialize, then provide a repeatable feature in the DAC scan range.
    repeat (20000) begin
        @(posedge clk);
        if (lock_mode) begin
            if ((min_adc_value != 16'h9000) || (max_adc_value != 16'hA400) ||
                (target_adc != 16'h9A00))
                $fatal(1, "feature statistics failed: min=%0d max=%0d target=%0d",
                       min_adc_value, max_adc_value, target_adc);
            $display("PASS sweeps=%0d min=%0d max=%0d target=%0d",
                     scan_sweep_count_dbg, min_adc_value, max_adc_value, target_adc);
            $finish;
        end
    end
    $fatal(1, "repeatable feature did not enter lock mode");
end
endmodule
