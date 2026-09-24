// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_ordinary_shared_control_tb;
 logic clk=0,reset_n=0;
 logic mr,mw,orr,orw,rr;
 logic gmr,gmw,gor,gow,gr,accepted;
 logic extq,mb,vb,mrf,vrf,split,restore_same,release_safe;
 logic request_valid,legal,controller_ready,competition,forward_valid,request_ready,service_window;
 always #5 clk=~clk;
 cgx1_pooled_vgpr_shared_port_arbiter arb(.clk(clk),.reset_n(reset_n),.matrix_read_valid(mr),.matrix_write_valid(mw),.ordinary_read_eligible(orr),.ordinary_write_eligible(orw),.restore_eligible(rr),.grant_matrix_read(gmr),.grant_matrix_write(gmw),.grant_ordinary_read(gor),.grant_ordinary_write(gow),.grant_restore(gr),.transfer_accepted(accepted));
 cgx1_pooled_vgpr_release_guard guard(.external_quiescent(extq),.matrix_busy(mb),.vector_busy(vb),.matrix_rf_active(mrf),.vector_rf_active(vrf),.split_read_pending(split),.restore_same_wave(restore_same),.release_safe(release_safe));
 cgx1_matrix_mixed_workload_admission #(.MATRIX_BURST_LIMIT(2)) admission(.clk(clk),.reset_n(reset_n),.request_valid(request_valid),.request_architecturally_legal(legal),.controller_ready(controller_ready),.competing_non_matrix_work(competition),.request_forward_valid(forward_valid),.request_ready(request_ready),.service_window(service_window));
 initial begin
  mr=0;mw=0;orr=0;orw=0;rr=0;accepted=0;extq=1;mb=0;vb=0;mrf=0;vrf=0;split=0;restore_same=0;request_valid=0;legal=1;controller_ready=1;competition=0;
  repeat(2) @(posedge clk); @(negedge clk); reset_n=1;
  mr=1;orr=1;rr=1;#1;if(!gmr||gor||gr)$fatal(1,"matrix read did not retain fixed-cycle priority");mr=0;
  mw=1;#1;if(!gmw||gor||gr)$fatal(1,"matrix write did not retain fixed-cycle priority");mw=0;
  orr=1;rr=1;#1;if(!gor||gr)$fatal(1,"ordinary/restore initial fairness grant mismatch");accepted=1;@(posedge clk);#1;@(negedge clk);accepted=0;#1;if(!gr||gor)$fatal(1,"restore did not receive bounded fairness turn");
  orr=0;rr=0;mb=1;#1;if(release_safe)$fatal(1,"matrix busy failed to block release");mb=0;split=1;#1;if(release_safe)$fatal(1,"split read failed to block release");split=0;#1;if(!release_safe)$fatal(1,"quiescent release was blocked");
  competition=1;
  @(negedge clk);
  request_valid=1;#1;if(!request_ready||!forward_valid)$fatal(1,"first matrix request unexpectedly throttled");
  @(posedge clk);#1;@(negedge clk);request_valid=0;#1;
  request_valid=1;#1;if(!request_ready||!forward_valid)$fatal(1,"second matrix request unexpectedly throttled");
  @(posedge clk);#1;@(negedge clk);request_valid=0;#1;
  if(!service_window||request_ready)$fatal(1,"mixed-load service window was not created after two accepted matrix requests");
  request_valid=1;legal=0;#1;if(!request_ready||!forward_valid)$fatal(1,"illegal matrix request was swallowed by workload throttle");
  $display("[pass] CGX 1 ordinary/shared control checks passed.");$finish;
 end
endmodule
