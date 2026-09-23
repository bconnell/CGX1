// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_vector_matrix_dependency_ready_array #(
 parameter integer RESIDENT_WAVE_SLOTS=16
)(
 input logic[RESIDENT_WAVE_SLOTS-1:0]request_valid,
 input logic[(RESIDENT_WAVE_SLOTS*8)-1:0]request_source0,request_source1,request_destination,
 input logic[(RESIDENT_WAVE_SLOTS*256)-1:0]matrix_source_pending_flat,matrix_destination_pending_flat,
 output logic[RESIDENT_WAVE_SLOTS-1:0]raw_hazard,waw_hazard,war_hazard,dependency_ready
);
 integer wave,s0i,s1i,di;
 always_comb begin
  raw_hazard='0;waw_hazard='0;war_hazard='0;dependency_ready='0;
  for(wave=0;wave<RESIDENT_WAVE_SLOTS;wave=wave+1) begin
   s0i=(wave*256)+request_source0[(wave*8)+:8];
   s1i=(wave*256)+request_source1[(wave*8)+:8];
   di=(wave*256)+request_destination[(wave*8)+:8];
   raw_hazard[wave]=request_valid[wave]&&(matrix_destination_pending_flat[s0i]||matrix_destination_pending_flat[s1i]);
   waw_hazard[wave]=request_valid[wave]&&matrix_destination_pending_flat[di];
   war_hazard[wave]=request_valid[wave]&&matrix_source_pending_flat[di];
   dependency_ready[wave]=!request_valid[wave]||!(raw_hazard[wave]||waw_hazard[wave]||war_hazard[wave]);
  end
 end
endmodule
