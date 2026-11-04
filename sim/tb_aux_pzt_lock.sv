`timescale 1ns/1ps
module tb_aux_pzt_lock #(parameter integer II_GAIN=0,D_GAIN=0);
 reg clk=0;always #5 clk=~clk;
 reg adc_test_done=0,spi_test_done=0;
 reg rst=0,enable=0,rv=1,cv=1,bv=1,quality=1,sv=1,reverse=0,search=0;
 reg aux_ok=1,pzt_ready=1;
 reg [15:0] measurement=30000,target=30500,manual=32000;
 wire [15:0] pzt_code;
 wire signed [17:0] error_code;
 wire locked,sat,tick;
 wire [2:0] state,fault;
 wire signed [63:0] integral;
 aux_pzt_lock_controller #(.PZT_INIT(32000),.PZT_MIN(30000),.PZT_MAX(34000),
  .UPDATE_CYCLES(20),.SAMPLE_TIMEOUT(60),.KP_Q16(32768),.KI_Q16(16384),.KII_Q16(II_GAIN),.KD_Q16(D_GAIN),.STEP_MAX(100),
  .SCAN_STEP(100),.LOCK_TOL(10),.UNLOCK_TOL(80),.LOCK_CONFIRM(5),.UNLOCK_CONFIRM(3)) dut(
  .clk(clk),.rst_n(rst),.enable(enable),.reference_valid(rv),.comb_valid(cv),.beat_valid(bv),
  .auxiliary_valid(aux_ok),.pzt_interface_ready(pzt_ready),
  .adc_quality(quality),.sample_valid(sv),.fv_voltage_code(measurement),.target_voltage_code(target),
  .polarity_reverse(reverse),.search_request(search),.manual_pzt_code(manual),
  .aux_pzt_code(pzt_code),.voltage_error(error_code),.locked(locked),.state(state),.fault(fault),
  .saturated(sat),.update_pulse(tick),.integral_q16(integral));
 reg plant=1;
 real thermal_value=30000.0;
 integer disturbance=0;
 integer plant_value;
 always @(negedge clk) if(plant) begin
  plant_value=reverse ? 30000-(integer'(pzt_code)-32000) : 30000+(integer'(pzt_code)-32000);
  thermal_value=thermal_value+(plant_value+disturbance-thermal_value)/8.0;
  measurement=$rtoi(thermal_value);
 end
 integer previous=32000,delta;
 always @(negedge clk) if(rst) begin
  delta=integer'(pzt_code)-previous;
  if(delta>100||delta< -100) $fatal(1,"slew limit violated %0d",delta);
  if(pzt_code<30000||pzt_code>34000) $fatal(1,"range violation");
  previous=pzt_code;
 end else previous=32000;
 task wait_cycles(input integer n);repeat(n) @(negedge clk);endtask
 task fresh;
 begin rst=0;enable=0;aux_ok=1;pzt_ready=1;disturbance=0;thermal_value=30000.0;rv=1;cv=1;bv=1;quality=1;sv=1;search=0;plant=1;manual=32000;wait_cycles(4);rst=1;wait_cycles(50);end
 endtask
 task expect_locked;
 begin wait_cycles(6000);if(!locked) $fatal(1,"did not lock: state=%d pzt=%d input=%d",state,pzt_code,measurement);
  if(measurement<target-10||measurement>target+10) $fatal(1,"wrong target");end
 endtask
 integer held;
 initial begin
  reverse=0;fresh();
  pzt_ready=0;manual=33000;held=pzt_code;wait_cycles(300);
  if(pzt_code!=held||fault!=4||locked) $fatal(1,"PZT interface gate must hold manual mode");
  enable=1;wait_cycles(100);if(pzt_code!=held||fault!=4) $fatal(1,"PZT gate must hold closed loop");
  manual=32000;pzt_ready=1;expect_locked();
  $display("PASS PZT interface calibration gate in manual and closed loop");
  disturbance=120;expect_locked();disturbance=0;expect_locked();
  $display("PASS thermal-lag plant disturbance rejection");
  held=pzt_code;aux_ok=0;wait_cycles(80);if(locked||pzt_code!=held||fault!=1) $fatal(1,"auxiliary invalid hold");
  aux_ok=1;expect_locked();$display("PASS auxiliary valid freeze and recovery");
  held=pzt_code;pzt_ready=0;wait_cycles(80);if(locked||pzt_code!=held||fault!=4) $fatal(1,"PZT ready withdrawn");
  pzt_ready=1;expect_locked();$display("PASS positive slope and nonzero setpoint");
  target=30600;expect_locked();$display("PASS target change with controlled transfer");
  held=pzt_code;bv=0;wait_cycles(80);if(locked||pzt_code!=held||state!=1) $fatal(1,"invalid beat not held");
  bv=1;expect_locked();$display("PASS beat invalid freeze and recovery");
  held=pzt_code;quality=0;wait_cycles(80);if(locked||pzt_code!=held) $fatal(1,"ADC quality hold");
  quality=1;expect_locked();held=pzt_code;sv=0;wait_cycles(100);
  if(locked||state!=1||fault!=3) $fatal(1,"stale samples not detected");sv=1;expect_locked();
  $display("PASS ADC quality and stale-sample watchdog");
  reverse=1;target=30500;fresh();enable=1;expect_locked();$display("PASS negative slope");
  plant=0;measurement=0;target=65000;reverse=0;wait_cycles(10000);
  if(pzt_code!=34000||!sat||locked) $fatal(1,"rail saturation failure");
  if(integral>64'sd4294901760||integral< -64'sd4294901760) $fatal(1,"integral overflow");
  plant=1;target=30500;fresh();enable=1;wait_cycles(30);search=1;wait_cycles(2);search=0;expect_locked();
  $display("PASS bounded search and capture");
  target=50000;wait_cycles(30);search=1;wait_cycles(2);search=0;wait_cycles(4000);
  if(state!=5||fault!=5||locked) $fatal(1,"search must stop when target absent");
  $display("PASS search exhaustion stops without false lock");
  enable=0;manual=31000;wait_cycles(1200);if(pzt_code!=31000) $fatal(1,"manual control failed");
  $display("PASS manual code mode");
  wait(adc_test_done&&spi_test_done);$display("ALL TESTS PASSED");$finish;
 end
 initial begin #3000000;$fatal(1,"simulation timeout");end

 // ADC encoding and invalid-window rejection.
 reg ar=0,aq_otr=0;
 reg [15:0] adcraw=16'h0000;
 wire [15:0] avg;
 wire av,aq;
 fv_adc_average #(.LOG2(2)) af(.clk(clk),.rst_n(ar),.ready(1'b1),.otr(aq_otr),
  .raw_code(adcraw),.voltage_code(avg),.sample_valid(av),.quality_ok(aq));
 initial begin
  wait_cycles(3);ar=1;wait_cycles(12);if(avg!=16'h8000||!aq) $fatal(1,"ADC sign encoding");
  adcraw=16'hF000;wait_cycles(12);if(avg!=16'h7000) $fatal(1,"negative ADC voltage mapping");
  aq_otr=1;wait_cycles(8);if(aq||av) $fatal(1,"OTR not rejected");
  aq_otr=0;wait_cycles(12);if(!aq) $fatal(1,"ADC did not recover");adc_test_done=1;
  $display("PASS ADC encoding and overrange rejection");
 end
 // Capture words using the ACTUAL DAC sampling edge, not internal debug values.
 wire sync_n,sclk,mosi,busy;
 reg [23:0] received=0;
 integer bits=0,frames=0;
 aux_pzt_dac #(.HALF_PERIOD(2),.B_PARK(16'h8000)) pd(.clk(clk),.rst_n(ar),.pzt_code(16'hA55A),
  .spi_sync(sync_n),.spi_sclk(sclk),.spi_mosi(mosi),.busy(busy));
 always @(negedge sync_n) begin received=0;bits=0;end
 always @(negedge sclk) if(!sync_n&&ar) begin received={received[22:0],mosi};bits=bits+1;end
 always @(posedge sync_n) if(ar&&bits>0) begin
  if(bits!=24) $fatal(1,"DAC frame truncated %d",bits);
  if((frames%2)==0&&received!==24'h30A55A) $fatal(1,"DAC A word %h",received);
  if((frames%2)==1&&received!==24'h348000) $fatal(1,"DAC B word %h",received);
  frames=frames+1;if(frames==4) begin spi_test_done=1;$display("PASS DAC falling-edge 24-bit SPI frames");end
 end
endmodule
