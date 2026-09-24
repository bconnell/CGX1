// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Candidate mixed-workload admission policy. Legal matrix requests may be
// deliberately deferred only after MATRIX_BURST_LIMIT accepted legal issues
// while non-matrix work is waiting. Illegal requests always reach the
// controller-owned legality path.
module cgx1_matrix_mixed_workload_admission #(
 parameter integer MATRIX_BURST_LIMIT=4,
 parameter integer COUNT_WIDTH=(MATRIX_BURST_LIMIT<=1)?1:$clog2(MATRIX_BURST_LIMIT)
)(
 input logic clk,reset_n,
 input logic request_valid,request_architecturally_legal,controller_ready,competing_non_matrix_work,
 output logic request_forward_valid,request_ready,service_window
);
 logic [COUNT_WIDTH-1:0] accepted_count_q;
 logic service_debt_q;
 logic ready_opportunity_seen_q;
 logic accepted_legal;

 always_comb begin
  service_window = competing_non_matrix_work && service_debt_q;
  request_forward_valid = request_valid
      && (!request_architecturally_legal || !service_window);
  request_ready = controller_ready
      && (!request_architecturally_legal || !service_window);
  accepted_legal = request_valid
      && request_architecturally_legal
      && request_ready;
 end

 always_ff @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin
   accepted_count_q <= '0;
   service_debt_q <= 1'b0;
   ready_opportunity_seen_q <= 1'b0;
  end else if(!competing_non_matrix_work) begin
   accepted_count_q <= '0;
   service_debt_q <= 1'b0;
   ready_opportunity_seen_q <= 1'b0;
  end else if(service_debt_q) begin
   // The debt represents one controller-ready matrix opportunity that must
   // be left unused so lower-priority work receives a service window.
   if(controller_ready) begin
    ready_opportunity_seen_q <= 1'b1;
   end
   if(ready_opportunity_seen_q && !controller_ready) begin
    accepted_count_q <= '0;
    service_debt_q <= 1'b0;
    ready_opportunity_seen_q <= 1'b0;
   end
  end else if(accepted_legal) begin
   if(accepted_count_q == MATRIX_BURST_LIMIT-1) begin
    accepted_count_q <= accepted_count_q;
    service_debt_q <= 1'b1;
    ready_opportunity_seen_q <= 1'b0;
   end else begin
    accepted_count_q <= accepted_count_q + 1'b1;
   end
  end
 end

`ifndef SYNTHESIS
 initial begin
  if(MATRIX_BURST_LIMIT<1) $fatal(1,"matrix mixed-workload burst limit must be at least one");
 end
`endif
endmodule
