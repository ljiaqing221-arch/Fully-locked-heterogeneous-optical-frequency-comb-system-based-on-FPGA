`timescale 1ns/1ps
module tb_pi2d;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,en=0,beat=1,quality=1;reg telemetry_done=0;
 reg [15:0] measurement=29990;
 wire [15:0] out;wire signed [17:0] err;
 wire lock,sat,tick;wire [2:0] st,fault;wire signed [63:0] i1,i2,d;
 aux_pzt_lock_controller #(.PZT_INIT(32000),.PZT_MIN(30000),.PZT_MAX(34000),
 .UPDATE_CYCLES(20),.SAMPLE_TIMEOUT(100),.KP_Q16(65536),.KI_Q16(32768),
 .KII_Q16(16384),.KD_Q16(65536),.D_FILTER_SHIFT(2),.STEP_MAX(2000)) dut(
 .clk(clk),.rst_n(rst),.enable(en),.reference_valid(1'b1),.comb_valid(1'b1),
 .beat_valid(beat),.auxiliary_valid(1'b1),.pzt_interface_ready(1'b1),.adc_quality(quality),
 .sample_valid(1'b1),.fv_voltage_code(measurement),.target_voltage_code(16'd30000),
 .polarity_reverse(1'b0),.search_request(1'b0),.manual_pzt_code(16'd32000),
 .aux_pzt_code(out),.voltage_error(err),.locked(lock),.state(st),.fault(fault),
 .saturated(sat),.update_pulse(tick),.integral_q16(i1),.integral2_q16(i2),.derivative_q16(d));
 task cycles(input integer n);repeat(n) @(negedge clk);endtask
 task next_update;begin @(negedge clk);while(!tick) @(negedge clk);end endtask
 longint s1=0,s2=0,df=0,prev=0,e,expect_i,expect_ii,expect_d,raw;
 integer k;reg history=0;
 initial begin
 cycles(4);rst=1;cycles(4);en=1;cycles(3);
 for(k=0;k<20;k=k+1) begin
   measurement=29990-k;
   e=10+k;s1=s1+e;s2=s2+s1;
   if(history) df=df+(((e-prev)*65536-df)>>>2);else df=0;
   expect_i=s1*32768;expect_ii=s2*16384;expect_d=df;
   raw=(32000*65536+e*65536+expect_i+expect_ii+expect_d)>>>16;
   next_update();
   if(i1!==expect_i||i2!==expect_ii||d!==expect_d||out!==raw[15:0])
    $fatal(1,"PI2D recurrence k=%0d I=%0d/%0d II=%0d/%0d D=%0d/%0d out=%0d/%0d",k,i1,expect_i,i2,expect_ii,d,expect_d,out,raw);
   history=1;prev=e;
 end
 $display("PASS exact P+I+I2+filtered-D recurrence, signed Q16");
 beat=0;cycles(3);if(i1!=0||i2!=0||d!=0||lock||fault!=1) $fatal(1,"invalid input did not clear histories");
 beat=1;measurement=29990;cycles(3);next_update();
 if(d!=0||i1!=10*32768||i2!=10*16384) $fatal(1,"restart derivative kick or integration reset failed");
 $display("PASS invalid-beat recovery without stale D history");
 measurement=0;cycles(3);next_update();
 if(out!=34000||!sat) $fatal(1,"range clamp failed");
 expect_i=i1;expect_ii=i2;
 repeat(40) begin next_update();if(i1!=expect_i||i2!=expect_ii) $fatal(1,"dual-integrator antiwindup failed");end
 $display("PASS both integrators freeze at the actuator rail");
 wait(telemetry_done);$display("PI2D AND TELEMETRY TESTS PASSED");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
 
 reg [15:0] fv=0,pzt=100,target=200;wire [15:0] sfv,spzt,starget;
 wire signed [17:0] serr;wire [31:0] seq;wire [63:0] ticks;
 wire signed [63:0] si,sii,sd;wire [7:0] flags;
 telemetry_snapshot #(.PERIOD_CYCLES(5)) ts(.clk(clk),.rst_n(rst),.fv(fv),.pzt(pzt),.target(target),
 .error(-18'sd7),.state(3'd2),.fault(3'd0),.locked(1'b0),.saturated(1'b0),
 .i_term(-64'sd123),.ii_term(64'sd456),.d_term(-64'sd789),.flags(8'ha5),
 .fv_snapshot(sfv),.pzt_snapshot(spzt),.target_snapshot(starget),.error_snapshot(serr),
 .i_snapshot(si),.ii_snapshot(sii),.d_snapshot(sd),.flags_snapshot(flags),.sequence_id(seq),.ticks_snapshot(ticks));
 reg [31:0] lastseq=0;reg [15:0] lastfv=0;reg [63:0] lastticks=0;
 integer n;
 initial begin
 wait(rst);for(n=0;n<100;n=n+1) begin
  @(negedge clk);
  if(seq!=lastseq) begin
   if(spzt-sfv!=100||starget-sfv!=200||serr!=-7||si!=-123||sii!=456||sd!=-789||flags!=8'ha5) $fatal(1,"non-atomic telemetry");
   if(lastseq!=0&&ticks-lastticks!=5) $fatal(1,"snapshot timestamp cadence");
   lastseq=seq;lastfv=sfv;lastticks=ticks;
  end else if(sfv!=lastfv) $fatal(1,"snapshot changed between strobes");
  fv=fv+1;pzt=pzt+1;target=target+1;
 end
 telemetry_done=1;$display("PASS atomic snapshot, signed fields, monotonic sequence/timestamp");
 end
endmodule

module tb_pi2d_plant;
 tb_aux_pzt_lock #(.II_GAIN(1),.D_GAIN(128)) regression();
endmodule

