// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_matrix_mixed_workload_admission_cadence_tb;
 logic clk=0,reset_n=0,request_valid,request_architecturally_legal,controller_ready,competing_non_matrix_work,request_forward_valid,request_ready,service_window;integer cycle,accepted_count;
 always #5 clk=~clk;
 cgx1_matrix_mixed_workload_admission #(.MATRIX_BURST_LIMIT(2)) dut(.*);
 initial begin request_valid=1;request_architecturally_legal=1;controller_ready=0;competing_non_matrix_work=1;accepted_count=0;repeat(2)@(posedge clk);@(negedge clk);reset_n=1;
  for(cycle=0;cycle<=49;cycle=cycle+1)begin controller_ready=(cycle==0||cycle==16||cycle==32||cycle==48);#1;if(request_ready)accepted_count=accepted_count+1;if(cycle==32&&request_ready)$fatal(1,"third issue opportunity was not skipped");if(cycle>16&&cycle<=32&&!service_window)$fatal(1,"service debt was lost while controller_ready was low");@(posedge clk);#1;@(negedge clk);end
  if(accepted_count!=3)$fatal(1,"expected accepts at 0,16,48; count=%0d",accepted_count);dut.service_pending_q=1;dut.burst_q=2;request_architecturally_legal=0;controller_ready=1;#1;if(!request_forward_valid||!request_ready)$fatal(1,"illegal matrix request was swallowed");
  $display("[pass] CGX 1 cadence-accurate matrix admission checks passed.");$finish;
 end
endmodule
