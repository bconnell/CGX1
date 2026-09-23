// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_resident_vector_matrix_dependency_frontend #(
 parameter integer RESIDENT_WAVE_SLOTS=16,
 parameter integer WAVE_SLOT_WIDTH=(RESIDENT_WAVE_SLOTS<=1)?1:$clog2(RESIDENT_WAVE_SLOTS)
)(
 input logic clk,reset_n,
 input logic[RESIDENT_WAVE_SLOTS-1:0]request_valid,
 input logic[(RESIDENT_WAVE_SLOTS*4)-1:0]request_opcode,
 input logic[(RESIDENT_WAVE_SLOTS*8)-1:0]request_source0,request_source1,request_destination,
 input logic[(RESIDENT_WAVE_SLOTS*32)-1:0]request_lane_mask,
 input logic[(RESIDENT_WAVE_SLOTS*256)-1:0]matrix_source_pending_flat,matrix_destination_pending_flat,
 output logic[RESIDENT_WAVE_SLOTS-1:0]dependency_ready,raw_hazard,waw_hazard,war_hazard,request_accepted,
 output logic selected_valid,
 output logic[WAVE_SLOT_WIDTH-1:0]selected_wave_slot,
 output logic[3:0]selected_opcode,
 output logic[7:0]selected_source0,selected_source1,selected_destination,
 output logic[31:0]selected_lane_mask,
 input logic selected_ready
);
 logic selected_accepted;
 cgx1_resident_vector_dependency_scheduler #(.RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),.WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)) dependency_scheduler(
  .clk(clk),.reset_n(reset_n),.request_valid(request_valid),.request_source0(request_source0),.request_source1(request_source1),.request_destination(request_destination),
  .matrix_source_pending_flat(matrix_source_pending_flat),.matrix_destination_pending_flat(matrix_destination_pending_flat),
  .dependency_ready(dependency_ready),.raw_hazard(raw_hazard),.waw_hazard(waw_hazard),.war_hazard(war_hazard),
  .selected_valid(selected_valid),.selected_wave_slot(selected_wave_slot),.selected_accepted(selected_accepted));
 always_comb begin
  selected_opcode='0;selected_source0='0;selected_source1='0;selected_destination='0;selected_lane_mask='0;request_accepted='0;
  if(selected_valid) begin
   selected_opcode=request_opcode[($unsigned(selected_wave_slot)*4)+:4];
   selected_source0=request_source0[($unsigned(selected_wave_slot)*8)+:8];
   selected_source1=request_source1[($unsigned(selected_wave_slot)*8)+:8];
   selected_destination=request_destination[($unsigned(selected_wave_slot)*8)+:8];
   selected_lane_mask=request_lane_mask[($unsigned(selected_wave_slot)*32)+:32];
   if(selected_ready) request_accepted[selected_wave_slot]=1'b1;
  end
  selected_accepted=selected_valid&&selected_ready;
 end
endmodule
