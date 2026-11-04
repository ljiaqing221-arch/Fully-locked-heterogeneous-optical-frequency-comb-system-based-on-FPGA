`timescale 1ns/1ps
// PZT tunes auxiliary laser frequency; cavity heating then changes microcomb repetition rate.
// Fixed NONZERO F/V setpoint on ONE calibrated monotonic IF branch.
// polarity_reverse=0: increasing PZT code increases measured F/V voltage.
// No resonance-extrema target estimation and no phase-lock claim.
module aux_pzt_lock_controller #(
 parameter [15:0] PZT_INIT=16'h8000,PZT_MIN=16'h7000,PZT_MAX=16'h9000,
 parameter integer UPDATE_CYCLES=25000000,SAMPLE_TIMEOUT=5000000,
 parameter integer KP_Q16=4096,KI_Q16=256,KII_Q16=1,KD_Q16=128,D_FILTER_SHIFT=2,
 parameter integer SUM_LIMIT=16777216,STEP_MAX=64,SCAN_STEP=64,
 parameter integer LOCK_TOL=64,UNLOCK_TOL=256,LOCK_CONFIRM=8,UNLOCK_CONFIRM=3
)(
 input wire clk,rst_n,enable,reference_valid,comb_valid,beat_valid,auxiliary_valid,pzt_interface_ready,adc_quality,
 input wire sample_valid,input wire [15:0] fv_voltage_code,target_voltage_code,
 input wire polarity_reverse,search_request,input wire [15:0] manual_pzt_code,
 output reg [15:0] aux_pzt_code, output reg signed [17:0] voltage_error,
 output reg locked,output reg [2:0] state,fault,
 output reg saturated,output reg update_pulse,
 output reg signed [63:0] integral_q16,integral2_q16,derivative_q16
);
 localparam DISABLED=0,WAIT_VALID=1,TRACK=2,LOCKED=3,SEARCH=4,SEARCH_FAILED=5,SEARCH_PREP=6;
 reg [31:0] timer,age;
 reg seen_sample,search_d,polarity_d;
 reg [15:0] measured,last_scan_voltage,target_d;
 reg scan_history;
 reg [15:0] bias_code;
 reg [15:0] lock_count,unlock_count;
 reg signed [63:0] error_calc,p_term,i_delta,i_candidate,raw_q16,desired,requested,actual,step;
 reg signed [31:0] sum_error,sum_error2,s1_candidate,s2_candidate;
 reg signed [63:0] previous_error,d_filtered,d_target,d_candidate,i_term,ii_term;
 reg signed [63:0] integration_change;
 reg derivative_history;
 function signed [31:0] clip_sum;
  input signed [63:0] x;
  begin
   if(x>SUM_LIMIT) clip_sum=SUM_LIMIT;
   else if(x< -SUM_LIMIT) clip_sum= -SUM_LIMIT;
   else clip_sum=x[31:0];
  end
 endfunction
 reg [17:0] abs_error;
 reg slope_good,crossed;
 reg [3:0] calc_stage;
 reg [17:0] abs_error_latched;
 reg signed [63:0] raw_pipeline,requested_pipeline,actual_pipeline;
 reg saturation_pipeline;
 wire usable=reference_valid&&comb_valid&&beat_valid&&auxiliary_valid&&adc_quality&&seen_sample&&(age<SAMPLE_TIMEOUT);
 function [15:0] clip_code;
  input [15:0] x;
  begin if(x<PZT_MIN) clip_code=PZT_MIN;else if(x>PZT_MAX) clip_code=PZT_MAX;else clip_code=x;end
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   aux_pzt_code<=PZT_INIT;voltage_error<=0;locked<=0;state<=DISABLED;fault<=0;
   saturated<=0;update_pulse<=0;integral_q16<=0;sum_error<=0;sum_error2<=0;integral2_q16<=0;derivative_q16<=0;d_filtered<=0;previous_error<=0;derivative_history<=0;timer<=0;age<=SAMPLE_TIMEOUT;
   seen_sample<=0;measured<=0;search_d<=0;polarity_d<=0;target_d<=0;
   bias_code<=PZT_INIT;lock_count<=0;unlock_count<=0;scan_history<=0;last_scan_voltage<=0;
   calc_stage<=0;abs_error_latched<=0;p_term<=0;i_delta<=0;i_candidate<=0;
   s1_candidate<=0;s2_candidate<=0;i_term<=0;ii_term<=0;d_target<=0;d_candidate<=0;integration_change<=0;
   raw_pipeline<=0;requested_pipeline<=0;actual_pipeline<=0;saturation_pipeline<=0;
  end else begin
   update_pulse<=0;search_d<=search_request;target_d<=target_voltage_code;polarity_d<=polarity_reverse;
   if(sample_valid) begin measured<=fv_voltage_code;seen_sample<=1;age<=0;end
   else if(age<SAMPLE_TIMEOUT) age<=age+1;
   if(!pzt_interface_ready) begin
    // No manual or closed-loop motion before analogue interface calibration.
    state<=WAIT_VALID;fault<=4;locked<=0;timer<=0;integral_q16<=0;sum_error<=0;sum_error2<=0;integral2_q16<=0;derivative_q16<=0;d_filtered<=0;previous_error<=0;derivative_history<=0;
    lock_count<=0;unlock_count<=0;calc_stage<=0;scan_history<=0;saturated<=0;
   end else if(!enable) begin
    state<=DISABLED;fault<=0;locked<=0;timer<=0;integral_q16<=0;sum_error<=0;sum_error2<=0;integral2_q16<=0;derivative_q16<=0;d_filtered<=0;previous_error<=0;derivative_history<=0;lock_count<=0;unlock_count<=0;calc_stage<=0;
    // Manual mode also obeys the code range and per-update slew limit.
    if(timer==0) begin
     desired=$signed({1'b0,clip_code(manual_pzt_code)})-$signed({1'b0,aux_pzt_code});
     if(desired>STEP_MAX) desired=STEP_MAX;else if(desired< -STEP_MAX) desired= -STEP_MAX;
     aux_pzt_code<=aux_pzt_code+desired;update_pulse<=1;
    end
    if(timer>=UPDATE_CYCLES-1) timer<=0;else timer<=timer+1;
   end else if(!usable) begin
    // Hold the LAST output, never treat a missing beat as zero frequency error.
    state<=WAIT_VALID;locked<=0;timer<=0;integral_q16<=0;sum_error<=0;sum_error2<=0;integral2_q16<=0;derivative_q16<=0;d_filtered<=0;previous_error<=0;derivative_history<=0;lock_count<=0;unlock_count<=0;scan_history<=0;calc_stage<=0;
    if(!reference_valid||!comb_valid||!beat_valid||!auxiliary_valid) fault<=1;
    else if(!adc_quality) fault<=2;else fault<=3;
   end else if(state==DISABLED||state==WAIT_VALID||polarity_d!=polarity_reverse||target_d!=target_voltage_code) begin
    state<=TRACK;bias_code<=aux_pzt_code;integral_q16<=0;sum_error<=0;sum_error2<=0;integral2_q16<=0;derivative_q16<=0;d_filtered<=0;previous_error<=0;derivative_history<=0;timer<=0;
    locked<=0;lock_count<=0;unlock_count<=0;fault<=0;saturated<=0;calc_stage<=0;
   end else if(search_request&&!search_d) begin
    // Operator first verifies this whole scan interval preserves the comb.
    state<=SEARCH_PREP;timer<=0;scan_history<=0;locked<=0;integral_q16<=0;sum_error<=0;sum_error2<=0;integral2_q16<=0;derivative_q16<=0;d_filtered<=0;previous_error<=0;derivative_history<=0;fault<=0;calc_stage<=0;
   end else if(calc_stage!=0) begin
    // PI^2D in discrete sample units. Ki/Kii/Kd include the chosen update period.
    // Eight registered stages. Both sums freeze when they would drive further into a limit.
    case(calc_stage)
     1: begin
      p_term<=error_calc*KP_Q16;
      s1_candidate<=clip_sum($signed(sum_error)+error_calc);
      if(derivative_history) d_target<=(error_calc-previous_error)*KD_Q16;
      else d_target<=0;
      calc_stage<=2;
     end
     2: begin
      s2_candidate<=clip_sum($signed(sum_error2)+$signed(s1_candidate));
      i_term<=$signed(s1_candidate)*KI_Q16;
      d_candidate<=d_filtered+((d_target-d_filtered)>>>D_FILTER_SHIFT);
      calc_stage<=3;
     end
     3: begin ii_term<=$signed(s2_candidate)*KII_Q16;calc_stage<=4;end
     4: begin
      raw_pipeline<=($signed({1'b0,bias_code})*64'sd65536)+p_term+i_term+ii_term+d_candidate;
      integration_change<=i_term+ii_term-integral_q16-integral2_q16;
      calc_stage<=5;
     end
     5: begin requested_pipeline<=raw_pipeline>>>16;calc_stage<=6;end
     6: begin
      if(requested_pipeline>PZT_MAX) desired<=PZT_MAX;
      else if(requested_pipeline<PZT_MIN) desired<=PZT_MIN;
      else desired<=requested_pipeline;
      saturation_pipeline<=requested_pipeline>PZT_MAX||requested_pipeline<PZT_MIN;
      calc_stage<=7;
     end
     7: begin
      step=desired-$signed({1'b0,aux_pzt_code});
      if(step>STEP_MAX) step=STEP_MAX;else if(step< -STEP_MAX) step= -STEP_MAX;
      actual_pipeline<=$signed({1'b0,aux_pzt_code})+step;calc_stage<=8;
     end
     8: begin
      if(!((requested_pipeline>actual_pipeline&&integration_change>0)||(requested_pipeline<actual_pipeline&&integration_change<0))) begin
       sum_error<=s1_candidate;sum_error2<=s2_candidate;
       integral_q16<=i_term;integral2_q16<=ii_term;
      end
      d_filtered<=d_candidate;derivative_q16<=d_candidate;
      previous_error<=error_calc;derivative_history<=1;
      aux_pzt_code<=actual_pipeline[15:0];saturated<=saturation_pipeline;update_pulse<=1;calc_stage<=0;
      if(!locked) begin
       state<=TRACK;
       if(abs_error_latched<=LOCK_TOL&&!saturation_pipeline) begin
        if(lock_count<LOCK_CONFIRM) lock_count<=lock_count+1;
        if(lock_count>=LOCK_CONFIRM-1) begin locked<=1;state<=LOCKED;end
       end else lock_count<=0;
      end else if(abs_error_latched>UNLOCK_TOL||saturation_pipeline) begin
       if(unlock_count<UNLOCK_CONFIRM) unlock_count<=unlock_count+1;
       if(unlock_count>=UNLOCK_CONFIRM-1) begin locked<=0;state<=TRACK;lock_count<=0;end
      end else unlock_count<=0;
     end
     default:calc_stage<=0;
    endcase
   end else if(state!=SEARCH_FAILED) begin
    if(timer>=UPDATE_CYCLES-1) begin
     timer<=0;update_pulse<=1;
     error_calc=$signed({1'b0,target_voltage_code})-$signed({1'b0,measured});
     abs_error=(error_calc<0)?-error_calc:error_calc;
     if(polarity_reverse) error_calc=-error_calc;
     voltage_error<=error_calc;
     if(state==SEARCH_PREP) begin
      if(aux_pzt_code<=PZT_MIN+STEP_MAX) begin aux_pzt_code<=PZT_MIN;state<=SEARCH;end
      else aux_pzt_code<=aux_pzt_code-STEP_MAX;
     end else if(state==SEARCH) begin
      // Capture only a target crossing on the calibrated monotonic beat branch.
      slope_good=polarity_reverse ? (last_scan_voltage>measured+4) : (measured>last_scan_voltage+4);
      crossed=polarity_reverse ? (last_scan_voltage>=target_voltage_code&&measured<=target_voltage_code) :
                                (last_scan_voltage<=target_voltage_code&&measured>=target_voltage_code);
      if(scan_history&&slope_good&&crossed) begin
       state<=TRACK;bias_code<=aux_pzt_code;integral_q16<=0;sum_error<=0;sum_error2<=0;integral2_q16<=0;derivative_q16<=0;d_filtered<=0;previous_error<=0;derivative_history<=0;lock_count<=0;unlock_count<=0;
      end else if(aux_pzt_code>=PZT_MAX) begin state<=SEARCH_FAILED;fault<=5;end
      else begin
       if(aux_pzt_code>PZT_MAX-SCAN_STEP) aux_pzt_code<=PZT_MAX;
       else aux_pzt_code<=aux_pzt_code+SCAN_STEP;
       scan_history<=1;last_scan_voltage<=measured;
      end
     end else begin
      abs_error_latched<=abs_error;calc_stage<=1;update_pulse<=0;
     end
    end else timer<=timer+1;
   end
  end
 end
endmodule
