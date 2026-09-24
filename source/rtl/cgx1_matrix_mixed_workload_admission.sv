// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_matrix_mixed_workload_admission #(
 parameter integer MATRIX_BURST_LIMIT=4,
 parameter integer COUNT_WIDTH=(MATRIX_BURST_LIMIT<=1)?1:$clog2(MATRIX_BURST_LIMIT+1)
)(
 input logic clk,reset_n,
 input logic request_valid,request_architecturally_legal,controller_ready,competing_non_matrix_work,
 output logic request_forward_valid,request_ready,service_window
);
 logic [COUNT_WIDTH-1:0] burst_q;
 logic service_pending_q,skipped_ready_seen_q,accepted_legal;
 always_comb begin
  service_window=competing_non_matrix_work&&service_pending_q;
  request_forward_valid=request_valid&&(!request_architecturally_legal||!service_window);
  request_ready=controller_ready&&(!request_architecturally_legal||!service_window);
  accepted_legal=request_valid&&request_architecturally_legal&&request_ready;
 end
 always_ff @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin burst_q<='0;service_pending_q<=0;skipped_ready_seen_q<=0;end
  else if(!competing_non_matrix_work) begin burst_q<='0;service_pending_q<=0;skipped_ready_seen_q<=0;end
  else if(service_pending_q) begin
   if(controller_ready) skipped_ready_seen_q<=1;
   if(skipped_ready_seen_q&&!controller_ready) begin burst_q<='0;service_pending_q<=0;skipped_ready_seen_q<=0;end
  end else if(accepted_legal) begin
   if(burst_q >= (MATRIX_BURST_LIMIT-1)) begin
    burst_q <= MATRIX_BURST_LIMIT[COUNT_WIDTH-1:0];
    service_pending_q <= 1'b1;
    skipped_ready_seen_q <= 1'b0;
   end else begin
    burst_q <= burst_q + {{(COUNT_WIDTH-1){1'b0}},1'b1};
   end
  end
 end
`ifndef SYNTHESIS
 initial if(MATRIX_BURST_LIMIT<1) $fatal(1,"matrix mixed-workload burst limit must be at least one");
`endif
endmodule
