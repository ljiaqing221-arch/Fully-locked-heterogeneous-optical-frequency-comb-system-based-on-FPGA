`timescale 1ns / 1ps

// Step-domain waveform detector.
//
// adc_in is one settled ADC average per DAC scan step, not a 50 MHz raw
// sample. Comparing scan-step values over a short history makes the detector
// sensitive to the millisecond-scale resonance dip while remaining insensitive
// to individual ADC glitches and DAC settling transients.
module wave_detector16 #(
    parameter integer WINDOW_BITS    = 4,
    parameter [15:0]  THRESHOLD      = 16'd512,
    parameter integer ASSERT_SAMPLES = 1,
    parameter integer CLEAR_SAMPLES  = 4,
    parameter integer WEAK_ASSERT_SAMPLES = 3,
    parameter integer RETRIGGER_SAMPLES   = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,
    input  wire        sample_valid,
    input  wire [15:0] adc_in,
    output wire [15:0] avg_out,
    output reg         detector_valid,
    output reg         wave_found
);

localparam integer WINDOW_SIZE = (1 << WINDOW_BITS);
localparam [16:0] WEAK_THRESHOLD  = {1'b0, THRESHOLD} >> 1;
localparam [16:0] CLEAR_THRESHOLD = {1'b0, THRESHOLD} >> 2;

reg [15:0] buffer [0:WINDOW_SIZE-1];
reg [WINDOW_BITS-1:0] index;
reg [31:0] sum;
reg [15:0] avg_reg;
reg [15:0] assert_count;
reg [15:0] weak_count;
reg [15:0] clear_count;
reg [15:0] retrigger_count;
reg        armed;
reg [15:0] anchor_high;
reg [15:0] anchor_low;

reg [31:0] sum_next;
reg [15:0] avg_next;
reg [15:0] baseline;
reg [16:0] deviation;
reg [16:0] fall_excursion;
reg [16:0] rise_excursion;
reg [16:0] detection_metric;
reg [15:0] event_baseline;
integer i;

assign avg_out = avg_reg;

always @(*) begin
    // Use the preceding scan-step window as the baseline. The current point is
    // inserted only after its deviation has been evaluated, so the leading
    // edge of a resonance valley is not diluted before detection.
    baseline = sum >> WINDOW_BITS;
    sum_next = sum - {16'd0, buffer[index]} + {16'd0, adc_in};
    avg_next = sum_next >> WINDOW_BITS;

    if ({1'b0, adc_in} >= {1'b0, baseline})
        deviation = {1'b0, adc_in} - {1'b0, baseline};
    else
        deviation = {1'b0, baseline} - {1'b0, adc_in};

    // The moving-average departure catches a narrow/steep edge. Excursion
    // from a running local anchor catches a broad peak or valley whose slope
    // is slow enough for the moving average to follow it. Use whichever has
    // stronger evidence, and retain the corresponding pre-feature shoulder.
    if (anchor_high >= adc_in)
        fall_excursion = {1'b0, anchor_high} - {1'b0, adc_in};
    else
        fall_excursion = 17'd0;
    if (adc_in >= anchor_low)
        rise_excursion = {1'b0, adc_in} - {1'b0, anchor_low};
    else
        rise_excursion = 17'd0;
    detection_metric = deviation;
    event_baseline = baseline;
    if ((fall_excursion >= rise_excursion) &&
        (fall_excursion > detection_metric)) begin
        detection_metric = fall_excursion;
        event_baseline = anchor_high;
    end else if (rise_excursion > detection_metric) begin
        detection_metric = rise_excursion;
        event_baseline = anchor_low;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        index          <= {WINDOW_BITS{1'b0}};
        sum            <= 32'd0;
        avg_reg        <= 16'd0;
        assert_count   <= 16'd0;
        weak_count     <= 16'd0;
        clear_count    <= 16'd0;
        retrigger_count <= 16'd0;
        armed          <= 1'b1;
        anchor_high    <= 16'd0;
        anchor_low     <= 16'hFFFF;
        detector_valid <= 1'b0;
        wave_found     <= 1'b0;
        for (i = 0; i < WINDOW_SIZE; i = i + 1)
            buffer[i] <= 16'd0;
    end else if (clear) begin
        // Each half-sweep is an independent detection window.
        index          <= {WINDOW_BITS{1'b0}};
        sum            <= 32'd0;
        avg_reg        <= 16'd0;
        assert_count   <= 16'd0;
        weak_count     <= 16'd0;
        clear_count    <= 16'd0;
        retrigger_count <= 16'd0;
        armed          <= 1'b1;
        anchor_high    <= 16'd0;
        anchor_low     <= 16'hFFFF;
        detector_valid <= 1'b0;
        wave_found     <= 1'b0;
        for (i = 0; i < WINDOW_SIZE; i = i + 1)
            buffer[i] <= 16'd0;
    end else begin
        // wave_found is a one-clock event. State changes only when a new,
        // settled DAC-step average is available.
        wave_found <= 1'b0;

        if (sample_valid) begin
            if (!detector_valid) begin
                // Seed the whole history with the first valid step. This avoids
                // a false event caused by an initially zero-filled average.
                for (i = 0; i < WINDOW_SIZE; i = i + 1)
                    buffer[i] <= adc_in;
                index          <= {WINDOW_BITS{1'b0}};
                sum            <= ({16'd0, adc_in} << WINDOW_BITS);
                avg_reg        <= adc_in;
                assert_count   <= 16'd0;
                weak_count     <= 16'd0;
                clear_count    <= 16'd0;
                retrigger_count <= 16'd0;
                armed          <= 1'b1;
                anchor_high    <= adc_in;
                anchor_low     <= adc_in;
                detector_valid <= 1'b1;
            end else begin
                sum           <= sum_next;
                buffer[index] <= adc_in;
                index         <= index + 1'b1;
                avg_reg       <= avg_next;

                if (armed) begin
                    clear_count     <= 16'd0;
                    retrigger_count <= 16'd0;
                    if (adc_in > anchor_high)
                        anchor_high <= adc_in;
                    if (adc_in < anchor_low)
                        anchor_low <= adc_in;

                    if (detection_metric >= {1'b0, THRESHOLD}) begin
                        weak_count <= 16'd0;
                        if (assert_count >= ASSERT_SAMPLES - 1) begin
                            wave_found   <= 1'b1;
                            armed        <= 1'b0;
                            assert_count <= 16'd0;
                            // Hold the pre-event baseline for one scan step so
                            // the extrema window can include the shoulder that
                            // precedes the resonance valley.
                            avg_reg      <= event_baseline;
                        end else begin
                            assert_count <= assert_count + 1'b1;
                        end
                    end else begin
                        assert_count <= 16'd0;
                        // A broad resonance can move slowly enough that its
                        // point-to-baseline deviation never reaches the strong
                        // threshold. Accept a half-threshold departure when it
                        // persists for several settled DAC steps. Minor motion
                        // between the clear and weak thresholds holds, rather
                        // than erases, the accumulated evidence.
                        if (detection_metric >= WEAK_THRESHOLD) begin
                            if (weak_count >= WEAK_ASSERT_SAMPLES - 1) begin
                                wave_found <= 1'b1;
                                armed      <= 1'b0;
                                weak_count <= 16'd0;
                                avg_reg    <= event_baseline;
                            end else begin
                                weak_count <= weak_count + 1'b1;
                            end
                        end else if (deviation <= CLEAR_THRESHOLD) begin
                            weak_count <= 16'd0;
                        end
                    end
                end else begin
                    assert_count <= 16'd0;
                    weak_count   <= 16'd0;
                    // A quiet return rearms quickly. A bounded retry interval
                    // also rearms on a long shoulder, so one early departure
                    // cannot suppress a later, genuine resonance in the same
                    // sweep. The controller still requires a real reversal,
                    // valid range and scan-to-scan consistency before locking.
                    if (((deviation <= CLEAR_THRESHOLD) &&
                         (clear_count >= CLEAR_SAMPLES - 1)) ||
                        (retrigger_count >= RETRIGGER_SAMPLES - 1)) begin
                        armed           <= 1'b1;
                        clear_count     <= 16'd0;
                        retrigger_count <= 16'd0;
                        anchor_high     <= adc_in;
                        anchor_low      <= adc_in;
                    end else begin
                        retrigger_count <= retrigger_count + 1'b1;
                        if (deviation <= CLEAR_THRESHOLD) begin
                            clear_count <= clear_count + 1'b1;
                        end else begin
                            clear_count <= 16'd0;
                        end
                    end
                end
            end
        end
    end
end

endmodule
