// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_pooled_vgpr_shared_port_arbiter(
 input logic clk, reset_n,
 input logic matrix_read_valid, matrix_write_valid,
 input logic ordinary_read_eligible, ordinary_write_eligible, restore_eligible,
 output logic grant_matrix_read, grant_matrix_write, grant_ordinary_read, grant_ordinary_write, grant_restore,
 input logic transfer_accepted
);
 logic prefer_restore_q;
 always_comb begin
   grant_matrix_read=0; grant_matrix_write=0; grant_ordinary_read=0; grant_ordinary_write=0; grant_restore=0;
   if(matrix_read_valid && !matrix_write_valid) grant_matrix_read=1;
   else if(matrix_write_valid && !matrix_read_valid) grant_matrix_write=1;
   else if(!matrix_read_valid && !matrix_write_valid) begin
     if((ordinary_read_eligible||ordinary_write_eligible) && restore_eligible) begin
       if(prefer_restore_q) grant_restore=1;
       else if(ordinary_read_eligible) grant_ordinary_read=1;
       else grant_ordinary_write=1;
     end else if(ordinary_read_eligible) grant_ordinary_read=1;
     else if(ordinary_write_eligible) grant_ordinary_write=1;
     else if(restore_eligible) grant_restore=1;
   end
 end
 always_ff @(posedge clk or negedge reset_n) begin
   if(!reset_n) prefer_restore_q<=1'b0;
   else if(transfer_accepted && ((grant_ordinary_read||grant_ordinary_write)&&restore_eligible)) prefer_restore_q<=1'b1;
   else if(transfer_accepted && grant_restore && (ordinary_read_eligible||ordinary_write_eligible)) prefer_restore_q<=1'b0;
 end
endmodule
