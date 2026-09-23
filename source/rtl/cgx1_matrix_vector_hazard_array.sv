// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_matrix_vector_hazard_array #(
 parameter integer RESIDENT_WAVE_SLOTS=16,
 parameter integer WAVE_SLOT_WIDTH=(RESIDENT_WAVE_SLOTS<=1)?1:$clog2(RESIDENT_WAVE_SLOTS)
)(
 input logic [RESIDENT_WAVE_SLOTS-1:0] matrix_layout_legal,
 input logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_d_base,matrix_a_base,matrix_b_base,
 input logic vector_busy,
 input logic [WAVE_SLOT_WIDTH-1:0] vector_wave_slot,
 input logic vector_source_locks_live,vector_destination_lock_live,
 input logic [7:0] vector_source0,vector_source1,vector_destination,
 output logic [RESIDENT_WAVE_SLOTS-1:0] matrix_runtime_ready,
 output logic [RESIDENT_WAVE_SLOTS-1:0] matrix_raw_hazard,matrix_waw_hazard,matrix_war_hazard
);
 genvar w;
 generate for(w=0;w<RESIDENT_WAVE_SLOTS;w=w+1) begin:g
   localparam logic [WAVE_SLOT_WIDTH-1:0] SLOT=w;
   cgx1_matrix_vector_hazard_guard guard(
    .same_wave(vector_busy&&(vector_wave_slot==SLOT)),.matrix_layout_legal(matrix_layout_legal[w]),
    .matrix_d_base(matrix_d_base[(w*8)+:8]),.matrix_a_base(matrix_a_base[(w*8)+:8]),.matrix_b_base(matrix_b_base[(w*8)+:8]),
    .vector_source_locks_live(vector_source_locks_live),.vector_destination_lock_live(vector_destination_lock_live),
    .vector_source0(vector_source0),.vector_source1(vector_source1),.vector_destination(vector_destination),
    .raw_hazard(matrix_raw_hazard[w]),.waw_hazard(matrix_waw_hazard[w]),.war_hazard(matrix_war_hazard[w]),.matrix_runtime_ready(matrix_runtime_ready[w]));
 end endgenerate
endmodule
