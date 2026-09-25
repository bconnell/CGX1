// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_vector_resident_wave_scheduler #(
 parameter integer RESIDENT_WAVE_SLOTS=16,
 parameter integer WAVE_SLOT_WIDTH=(RESIDENT_WAVE_SLOTS<=1)?1:$clog2(RESIDENT_WAVE_SLOTS)
)(
 input logic clk, reset_n,
 input logic [RESIDENT_WAVE_SLOTS-1:0] request_valid,
 input logic [RESIDENT_WAVE_SLOTS-1:0] dependency_ready,
 output logic selected_valid,
 output logic [WAVE_SLOT_WIDTH-1:0] selected_wave_slot,
 input logic selected_accepted
);
 logic [WAVE_SLOT_WIDTH-1:0] next_q; integer off,idx; logic found;
 always_comb begin selected_valid=0; selected_wave_slot='0; found=0;
   for(off=0;off<RESIDENT_WAVE_SLOTS;off=off+1) begin idx=$unsigned(next_q)+off; if(idx>=RESIDENT_WAVE_SLOTS) idx=idx-RESIDENT_WAVE_SLOTS;
     if(!found&&request_valid[idx]&&dependency_ready[idx]) begin found=1; selected_valid=1; selected_wave_slot=idx[WAVE_SLOT_WIDTH-1:0]; end
   end
 end
 always_ff @(posedge clk or negedge reset_n) begin
   if(!reset_n) next_q<='0;
   else if(selected_valid&&selected_accepted) begin if($unsigned(selected_wave_slot)==RESIDENT_WAVE_SLOTS-1) next_q<='0; else next_q<=selected_wave_slot+1'b1; end
 end
`ifndef SYNTHESIS
 initial begin
   if(RESIDENT_WAVE_SLOTS<1) $fatal(1,"resident vector scheduler requires at least one slot");
   if((1<<WAVE_SLOT_WIDTH)<RESIDENT_WAVE_SLOTS) $fatal(1,"resident vector scheduler wave-slot width is too small");
 end
`endif
endmodule
