`timescale 1ns/1ps
`include "aux_pzt_config.vh"
module top_aux_pzt_lock(
 input wire reset_n,sys_clk,adc_otr,adc_dco,input wire [15:0] adc_data,
 output wire adc_clk,adc_oeb,adc_pwdn,adc_sclk,adc_csb,adc_sdio,
 output wire pzt_dac_sync,pzt_dac_sclk,pzt_dac_mosi,
 output wire mixer_lo_out,mixer_lo_monitor);
 wire [15:0] raw_a,raw_b;
 wire adc_ready;
 (* ASYNC_REG="TRUE" *) reg [1:0] ready_sync;
 reg otr_a;
 // Reset asynchronously asserts and synchronously releases in each clock domain.
 (* ASYNC_REG="TRUE" *) reg [1:0] rst_sys,rst_dco;
 always @(posedge sys_clk or negedge reset_n) if(!reset_n)rst_sys<=0;else rst_sys<={rst_sys[0],1'b1};
 always @(posedge adc_dco or negedge reset_n) if(!reset_n)rst_dco<=0;else rst_dco<={rst_dco[0],1'b1};
 always @(posedge adc_dco or negedge rst_dco[1]) begin
  if(!rst_dco[1]) begin ready_sync<=0;otr_a<=1;end
  else begin ready_sync<={ready_sync[0],adc_ready};otr_a<=adc_otr;end
 end
 AD9269 u_adc(.SYS_CLK(sys_clk),.SYS_RST(rst_sys[1]),.DATA_RST_N(rst_dco[1]),.OTR(adc_otr),.DCO(adc_dco),.DB15_0(adc_data),
  .AD_CLK(adc_clk),.OEB(adc_oeb),.PDWM(adc_pwdn),.SCLK(adc_sclk),.CSB(adc_csb),.SDIO(adc_sdio),
  .ADC_READY(adc_ready),.AD_DATA_A(raw_a),.AD_DATA_B(raw_b));
 wire [15:0] fv_code;
 wire fv_sample_valid,adc_quality;
 fv_adc_average u_fv_adc(.clk(adc_dco),.rst_n(rst_dco[1]),.ready(ready_sync[1]),.otr(otr_a),
  .raw_code(raw_a),.voltage_code(fv_code),.sample_valid(fv_sample_valid),.quality_ok(adc_quality));
 wire auxiliary_valid_cmd,pzt_ready_cmd,lo_path_ready_cmd;
 // The clock runs at a constant frequency; this status never gates it.
 (* DONT_TOUCH="TRUE" *) fixed_lo_clock #(.DIVIDE(`LO_DIVIDE)) u_lo(.clk(sys_clk),.rst_n(rst_sys[1]),.lo_out(mixer_lo_out));
 // Second adjacent package pin is a same-frequency observation output, NOT ground.
 // Each forwarded clock must own an ODDR/OBUF; an ODDR cannot fan out to two pads.
 (* DONT_TOUCH="TRUE" *) fixed_lo_clock #(.DIVIDE(`LO_DIVIDE)) u_lo_monitor(.clk(sys_clk),.rst_n(rst_sys[1]),.lo_out(mixer_lo_monitor));
 wire enable_cmd,ref_valid_cmd,comb_valid_cmd,beat_valid_cmd,reverse_cmd,search_cmd;
 wire [15:0] target_cmd,manual_cmd;
 wire [15:0] aux_pzt_code;
 wire signed [17:0] voltage_error;
 wire locked,saturated,update_pulse;
 wire [2:0] state,fault;
 wire signed [63:0] integral_q16,integral2_q16,derivative_q16;
 // VIO validity inputs are OPERATOR CONFIRMATIONS, not automatic optical sensors.
 // Replace them with real status inputs before claiming unattended fault detection.
 vio_aux_controls u_vio(.clk(adc_dco),
  .probe_out0(enable_cmd),.probe_out1(ref_valid_cmd),.probe_out2(comb_valid_cmd),.probe_out3(beat_valid_cmd),
  .probe_out4(target_cmd),.probe_out5(manual_cmd),.probe_out6(reverse_cmd),.probe_out7(search_cmd),.probe_out8(auxiliary_valid_cmd),.probe_out9(pzt_ready_cmd),.probe_out10(lo_path_ready_cmd));
 aux_pzt_lock_controller #(.PZT_INIT(`PZT_INIT_CODE),.PZT_MIN(`PZT_MIN_CODE),.PZT_MAX(`PZT_MAX_CODE),
  .UPDATE_CYCLES(`UPDATE_CYCLES),.SAMPLE_TIMEOUT(`SAMPLE_TIMEOUT_CYCLES),.KP_Q16(`KP_Q16),.KI_Q16(`KI_Q16),.KII_Q16(`KII_Q16),.KD_Q16(`KD_Q16),.D_FILTER_SHIFT(`D_FILTER_SHIFT),
  .STEP_MAX(`PZT_STEP_MAX),.SCAN_STEP(`SCAN_STEP),.LOCK_TOL(`LOCK_TOL),.UNLOCK_TOL(`UNLOCK_TOL),
  .LOCK_CONFIRM(`LOCK_CONFIRM),.UNLOCK_CONFIRM(`UNLOCK_CONFIRM)) u_controller(
  .clk(adc_dco),.rst_n(rst_dco[1]),.enable(enable_cmd),.reference_valid(ref_valid_cmd),
  .comb_valid(comb_valid_cmd),.beat_valid(beat_valid_cmd && lo_path_ready_cmd),.auxiliary_valid(auxiliary_valid_cmd),
  .pzt_interface_ready(pzt_ready_cmd),.adc_quality(adc_quality),
  .sample_valid(fv_sample_valid),.fv_voltage_code(fv_code),.target_voltage_code(target_cmd),
  .polarity_reverse(reverse_cmd),.search_request(search_cmd),.manual_pzt_code(manual_cmd),
  .aux_pzt_code(aux_pzt_code),.voltage_error(voltage_error),.locked(locked),.state(state),.fault(fault),
  .saturated(saturated),.update_pulse(update_pulse),.integral_q16(integral_q16),.integral2_q16(integral2_q16),.derivative_q16(derivative_q16));
 wire dac_busy;
 aux_pzt_dac u_pzt_dac(.clk(adc_dco),.rst_n(rst_dco[1]),.pzt_code(aux_pzt_code),
  .spi_sync(pzt_dac_sync),.spi_sclk(pzt_dac_sclk),.spi_mosi(pzt_dac_mosi),.busy(dac_busy));
 // Atomic 10 Hz debug snapshots, independent of PI updates and host polling.
 wire [15:0] telemetry_fv,telemetry_pzt,telemetry_target;
 wire signed [17:0] telemetry_error;
 wire [2:0] telemetry_state,telemetry_fault;
 wire telemetry_locked,telemetry_saturated;
 wire signed [63:0] telemetry_i,telemetry_ii,telemetry_d;
 wire [31:0] telemetry_sequence;
 wire [63:0] telemetry_ticks;
 wire [7:0] telemetry_flags;
 telemetry_snapshot #(.PERIOD_CYCLES(`TELEMETRY_CYCLES)) u_telemetry(
  .clk(adc_dco),.rst_n(rst_dco[1]),.fv(fv_code),.pzt(aux_pzt_code),.target(target_cmd),.error(voltage_error),
  .state(state),.fault(fault),.locked(locked),.saturated(saturated),
  .i_term(integral_q16),.ii_term(integral2_q16),.d_term(derivative_q16),
  .flags({ready_sync[1],adc_quality,lo_path_ready_cmd,pzt_ready_cmd,auxiliary_valid_cmd,beat_valid_cmd,comb_valid_cmd,ref_valid_cmd}),
  .fv_snapshot(telemetry_fv),.pzt_snapshot(telemetry_pzt),.target_snapshot(telemetry_target),.error_snapshot(telemetry_error),
  .state_snapshot(telemetry_state),.fault_snapshot(telemetry_fault),.locked_snapshot(telemetry_locked),.saturated_snapshot(telemetry_saturated),
  .i_snapshot(telemetry_i),.ii_snapshot(telemetry_ii),.d_snapshot(telemetry_d),.flags_snapshot(telemetry_flags),
  .sequence_id(telemetry_sequence),.ticks_snapshot(telemetry_ticks));
 ila_aux_debug u_ila(.clk(adc_dco),.probe0(raw_a),.probe1(telemetry_fv),.probe2(telemetry_error),
  .probe3(telemetry_pzt),.probe4(telemetry_state),.probe5(telemetry_locked),.probe6(telemetry_fault),.probe7(telemetry_saturated),
  .probe8(fv_sample_valid),.probe9(adc_quality),.probe10(update_pulse),.probe11(dac_busy),.probe12(telemetry_i),
  .probe13(telemetry_ii),.probe14(telemetry_d),.probe15(telemetry_target),.probe16(telemetry_sequence),.probe17(telemetry_ticks),.probe18(telemetry_flags));
endmodule
