// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_matrix_mixed_workload_admission #(
 parameter integer MATRIX_BURST_LIMIT=4,
 parameter integer COUNT_WIDTH=(MATRIX_BURST_LIMIT<=1)?1:$clog2(MATRIX_BURST_LIMIT+1)
)(
 input logic clk, reset_n,
 input logic request_valid, request_architecturally_legal, controller_ready,
 input logic competing_non_matrix_work,
 output logic request_forward_valid, request_ready, service_window
);
 logic [COUNT_WIDTH-1:0] burst_q;
 logic throttle;
 always_comb begin
   throttle=request_architecturally_legal && competing_non_matrix_work && (burst_q>=MATRIX_BURST_LIMIT);
   service_window=throttle;
   request_forward_valid=request_valid && (!request_architecturally_legal || !throttle);
   request_ready=controller_ready && (!request_architecturally_legal || !throttle);
 end
 always_ff @(posedge clk or negedge reset_n) begin
   if(!reset_n) burst_q<='0;
   else if(!competing_non_matrix_work || !controller_ready) burst_q<='0;
   else if(throttle) burst_q<='0;
   else if(request_valid && request_ready && request_architecturally_legal) burst_q<=burst_q+1'b1;
 end
endmodule
