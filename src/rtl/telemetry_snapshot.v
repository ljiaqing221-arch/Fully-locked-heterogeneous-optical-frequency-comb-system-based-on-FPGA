`timescale 1ns/1ps
module telemetry_snapshot #(parameter integer PERIOD_CYCLES=5000000)(
 input wire clk,rst_n,input wire [15:0] fv,pzt,target,input wire signed [17:0] error,
 input wire [2:0] state,fault,input wire locked,saturated,
 input wire signed [63:0] i_term,ii_term,d_term,input wire [7:0] flags,
 output reg [15:0] fv_snapshot,pzt_snapshot,target_snapshot,output reg signed [17:0] error_snapshot,
 output reg [2:0] state_snapshot,fault_snapshot,output reg locked_snapshot,saturated_snapshot,
 output reg signed [63:0] i_snapshot,ii_snapshot,d_snapshot,output reg [7:0] flags_snapshot,
 output reg [31:0] sequence_id,output reg [63:0] ticks_snapshot
);
 reg [31:0] divider;reg [63:0] ticks;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   divider<=0;ticks<=0;sequence_id<=0;ticks_snapshot<=0;
   fv_snapshot<=0;pzt_snapshot<=0;target_snapshot<=0;error_snapshot<=0;
   state_snapshot<=0;fault_snapshot<=0;locked_snapshot<=0;saturated_snapshot<=0;
   i_snapshot<=0;ii_snapshot<=0;d_snapshot<=0;flags_snapshot<=0;
  end else begin
   ticks<=ticks+1;
   if(divider>=PERIOD_CYCLES-1) begin
    divider<=0;sequence_id<=sequence_id+1;ticks_snapshot<=ticks;
    fv_snapshot<=fv;pzt_snapshot<=pzt;target_snapshot<=target;error_snapshot<=error;
    state_snapshot<=state;fault_snapshot<=fault;locked_snapshot<=locked;saturated_snapshot<=saturated;
    i_snapshot<=i_term;ii_snapshot<=ii_term;d_snapshot<=d_term;flags_snapshot<=flags;
   end else divider<=divider+1;
  end
 end
endmodule
