// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_matrix_vector_hazard_guard (
 input logic same_wave,
 input logic matrix_layout_legal,
 input logic [7:0] matrix_d_base, matrix_a_base, matrix_b_base,
 input logic vector_source_locks_live, vector_destination_lock_live,
 input logic [7:0] vector_source0, vector_source1, vector_destination,
 output logic raw_hazard, waw_hazard, war_hazard, matrix_runtime_ready
);
 function automatic logic overlap(input logic [7:0] lbase,input integer lcount,input logic [7:0] rbase,input integer rcount);
   integer lend,rend; begin lend=$unsigned(lbase)+lcount; rend=$unsigned(rbase)+rcount; overlap=($unsigned(lbase)<rend)&&($unsigned(rbase)<lend); end
 endfunction
 always_comb begin
   raw_hazard=0; waw_hazard=0; war_hazard=0;
   if(same_wave && matrix_layout_legal) begin
     if(vector_destination_lock_live) begin
       raw_hazard=overlap(matrix_a_base,4,vector_destination,1)||overlap(matrix_b_base,4,vector_destination,1)||overlap(matrix_d_base,8,vector_destination,1);
       waw_hazard=overlap(matrix_d_base,8,vector_destination,1);
     end
     if(vector_source_locks_live) war_hazard=overlap(matrix_d_base,8,vector_source0,1)||overlap(matrix_d_base,8,vector_source1,1);
   end
   matrix_runtime_ready=!matrix_layout_legal || !(raw_hazard||waw_hazard||war_hazard);
 end
endmodule
