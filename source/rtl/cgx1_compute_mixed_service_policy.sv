// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_compute_mixed_service_policy #(
 parameter integer MATRIX_BURST_LIMIT=4,
 parameter integer COUNT_WIDTH=(MATRIX_BURST_LIMIT<=1)?1:$clog2(MATRIX_BURST_LIMIT+1)
)(
 input logic clk,reset_n,
 input logic legal_matrix_accepted,
 input logic vector_waiting,vector_accepted,
 input logic restore_waiting,restore_accepted,
 output logic allow_legal_matrix_issue,service_window_active
);
 logic[COUNT_WIDTH-1:0]burst_q;logic service_pending_q,competition,non_matrix_progress;
 always_comb begin competition=vector_waiting||restore_waiting;non_matrix_progress=vector_accepted||restore_accepted;service_window_active=competition&&service_pending_q;allow_legal_matrix_issue=!service_window_active;end
 always_ff @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin burst_q<='0;service_pending_q<=0;end
  else if(!competition) begin burst_q<='0;service_pending_q<=0;end
  else if(service_pending_q) begin if(non_matrix_progress) begin burst_q<='0;service_pending_q<=0;end end
  else if(legal_matrix_accepted) begin if((burst_q+1'b1)>=MATRIX_BURST_LIMIT) begin burst_q<=MATRIX_BURST_LIMIT;service_pending_q<=1;end else burst_q<=burst_q+1'b1;end
 end
`ifndef SYNTHESIS
 initial if(MATRIX_BURST_LIMIT<1) $fatal(1,"mixed compute matrix burst limit must be at least one");
`endif
endmodule
