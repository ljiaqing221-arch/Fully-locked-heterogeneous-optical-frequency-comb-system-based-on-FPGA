`timescale 1ns/1ps
module sweep_qualifier #(
 parameter integer WIDTH=16, MIN_VALID_STEPS=64, MAX_INVALID_STEPS=16,
 parameter integer MIN_CONSISTENT_SWEEPS=2,
 parameter [WIDTH-1:0] RANGE_MIN=1024, RANGE_MAX=12288,
 parameter [WIDTH-1:0] CENTER_TOLERANCE=1024, RANGE_TOLERANCE_MIN=1024
)(
 input wire clk,rst_n,sweep_done,shape_seen,
 input wire [WIDTH-1:0] min_value,max_value,best_code,
 input wire [31:0] valid_steps,invalid_steps,
 output reg qualified,
 output reg [WIDTH-1:0] target,initial_code
);
reg previous_valid;
reg [31:0] consistent_count;
reg [WIDTH-1:0] previous_min,previous_max,previous_center,previous_range;
wire [WIDTH-1:0] scan_range=max_value-min_value;
wire [WIDTH-1:0] center=min_value+(scan_range>>1);
wire [WIDTH-1:0] center_diff=(center>=previous_center)?center-previous_center:previous_center-center;
wire [WIDTH-1:0] range_diff=(scan_range>=previous_range)?scan_range-previous_range:previous_range-scan_range;
wire [WIDTH-1:0] range_tol=((previous_range>>2)>RANGE_TOLERANCE_MIN)?(previous_range>>2):RANGE_TOLERANCE_MIN;
wire [WIDTH:0] min_sum={1'b0,min_value}+{1'b0,previous_min};
wire [WIDTH:0] max_sum={1'b0,max_value}+{1'b0,previous_max};
wire [WIDTH-1:0] accepted_min=min_sum[WIDTH:1],accepted_max=max_sum[WIDTH:1];
wire valid_sweep=shape_seen&&(max_value>=min_value)&&
 (valid_steps>=MIN_VALID_STEPS)&&(invalid_steps<=MAX_INVALID_STEPS)&&
 (scan_range>=RANGE_MIN)&&(scan_range<=RANGE_MAX);
wire consistent=previous_valid&&(center_diff<=CENTER_TOLERANCE)&&(range_diff<=range_tol);
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
  previous_valid<=0; consistent_count<=0; qualified<=0; target<=0; initial_code<=0;
  previous_min<=0; previous_max<=0; previous_center<=0; previous_range<=0;
 end else begin
  qualified<=0;
  if(sweep_done) begin
   if(!valid_sweep) begin previous_valid<=0; consistent_count<=0; end
   else begin
    previous_valid<=1; previous_min<=min_value; previous_max<=max_value;
    previous_center<=center; previous_range<=scan_range;
    if(consistent) begin
     if(consistent_count<MIN_CONSISTENT_SWEEPS) consistent_count<=consistent_count+1'b1;
     if(consistent_count>=MIN_CONSISTENT_SWEEPS-1) begin
      qualified<=1; target<=accepted_min+((accepted_max-accepted_min)>>1); initial_code<=best_code;
     end
    end else consistent_count<=1;
   end
  end
 end
end
// synthesis translate_off
initial if (WIDTH<1 || MIN_VALID_STEPS<1 || MAX_INVALID_STEPS<0 || MIN_CONSISTENT_SWEEPS<2 || RANGE_MIN>RANGE_MAX) $fatal(1,"parameter error: qualifier statistics");
// synthesis translate_on
endmodule
