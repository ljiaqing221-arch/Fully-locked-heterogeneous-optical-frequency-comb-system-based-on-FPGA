`timescale 1ns/1ps
module tb_control_chain;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,valid=0;reg[15:0] measurement=20000,target=21000;
wire[15:0] u;wire cs,sclk,mosi;integer frames=0,bits=0;reg[23:0] captured=0;
control_chain dut(clk,rst_n,valid,measurement,target,u,cs,sclk,mosi);
always @(negedge cs) begin bits=0;captured=0;end
always @(negedge sclk) if(!cs) begin captured={captured[22:0],mosi};bits=bits+1;end
always @(posedge cs) if(rst_n && bits>0) begin
 if(bits!=24||captured[23:16]!==8'h30) $fatal(1,"integration SPI frame invalid");frames=frames+1;
end
initial begin
 #1;rst_n=0;repeat(3) @(negedge clk);rst_n=1;
 repeat(12) @(negedge clk);if(u!==16'h8000) $fatal(1,"controller ran before filter warm-up");
 valid=1;repeat(250) @(negedge clk);
 if(u<=16'h8000||u>16'hA000||frames<1) $fatal(1,"integration forward path failed");
 measurement=22000;repeat(1500) @(negedge clk);
 if(u>=16'h8000||u<16'h6000) $fatal(1,"integration negative error failed");
 $display("PASS_CONTROL_CHAIN");$finish;
end
initial begin #1000000;$fatal(1,"watchdog");end
endmodule
