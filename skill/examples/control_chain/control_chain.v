`timescale 1ns/1ps
// Demonstrates composition only. ADC pins, analog plant and CDC are external.
module control_chain(input wire clk,rst_n,sample_valid,
 input wire [15:0] measurement,target,
 output wire [15:0] control_word,
 output wire spi_cs_n,spi_sclk,spi_mosi);
wire filtered_valid;wire [15:0] filtered;
reg [15:0] held_measurement;reg ready_for_control;
median5_valid #(.WIDTH(16)) filter(clk,rst_n,sample_valid,measurement,filtered_valid,filtered);
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin held_measurement<=0;ready_for_control<=0;end
 else if(filtered_valid) begin held_measurement<=filtered;ready_for_control<=1;end
end
wire signed [17:0] error_value=$signed({2'b00,target})-$signed({2'b00,held_measurement});
// Reset is held until a full five-sample median is available.
pid_error_lock #(.PID_DIV(4)) controller(clk,rst_n & ready_for_control,error_value,control_word);
wire tx_ready,tx_busy,tx_done;
wire [23:0] frame={8'h30,control_word}; // Source-derived DAC8552 channel-A example.
spi_frame_tx #(.FRAME_BITS(24),.HALF_PERIOD(2),.CPOL(0),.CPHA(1)) tx(
 clk,rst_n,ready_for_control,frame,tx_ready,tx_busy,tx_done,spi_cs_n,spi_sclk,spi_mosi);
endmodule
