// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_resident_vector_dependency_scheduler #(
 parameter integer RESIDENT_WAVE_SLOTS=16,
 parameter integer WAVE_SLOT_WIDTH=(RESIDENT_WAVE_SLOTS<=1)?1:$clog2(RESIDENT_WAVE_SLOTS)
)(
 input logic clk,reset_n,
 input logic[RESIDENT_WAVE_SLOTS-1:0]request_valid,
 input logic[(RESIDENT_WAVE_SLOTS*8)-1:0]request_source0,request_source1,request_destination,
 input logic[(RESIDENT_WAVE_SLOTS*256)-1:0]matrix_source_pending_flat,matrix_destination_pending_flat,
 output logic[RESIDENT_WAVE_SLOTS-1:0]dependency_ready,raw_hazard,waw_hazard,war_hazard,
 output logic selected_valid,
 output logic[WAVE_SLOT_WIDTH-1:0]selected_wave_slot,
 input logic selected_accepted
);
 cgx1_vector_matrix_dependency_ready_array #(.RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS)) dependencies(
  .request_valid(request_valid),.request_source0(request_source0),.request_source1(request_source1),.request_destination(request_destination),
  .matrix_source_pending_flat(matrix_source_pending_flat),.matrix_destination_pending_flat(matrix_destination_pending_flat),
  .raw_hazard(raw_hazard),.waw_hazard(waw_hazard),.war_hazard(war_hazard),.dependency_ready(dependency_ready));
 cgx1_vector_resident_wave_scheduler #(.RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),.WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)) scheduler(
  .clk(clk),.reset_n(reset_n),.request_valid(request_valid),.dependency_ready(dependency_ready),.selected_valid(selected_valid),.selected_wave_slot(selected_wave_slot),.selected_accepted(selected_accepted));
endmodule
