// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_compute_mixed_service_policy_tb;
 logic clk=0,reset_n=0,legal_matrix_accepted,vector_waiting,vector_accepted,restore_waiting,restore_accepted,allow_legal_matrix_issue,service_window_active;
 always #5 clk=~clk;
 cgx1_compute_mixed_service_policy #(.MATRIX_BURST_LIMIT(2)) dut(.*);
 task automatic pulse_matrix;begin @(negedge clk);legal_matrix_accepted=1;@(posedge clk);#1;@(negedge clk);legal_matrix_accepted=0;end endtask
 initial begin legal_matrix_accepted=0;vector_waiting=0;vector_accepted=0;restore_waiting=0;restore_accepted=0;repeat(2)@(posedge clk);@(negedge clk);reset_n=1;vector_waiting=1;pulse_matrix();pulse_matrix();#1;if(allow_legal_matrix_issue||!service_window_active)$fatal(1,"service window did not open");repeat(20)begin @(posedge clk);#1;if(allow_legal_matrix_issue)$fatal(1,"service debt disappeared without progress");end @(negedge clk);vector_accepted=1;@(posedge clk);#1;@(negedge clk);vector_accepted=0;#1;if(!allow_legal_matrix_issue)$fatal(1,"vector progress did not release debt");vector_waiting=0;restore_waiting=1;pulse_matrix();pulse_matrix();#1;if(allow_legal_matrix_issue)$fatal(1,"restore pressure did not create debt");restore_accepted=1;@(posedge clk);#1;@(negedge clk);restore_accepted=0;#1;if(!allow_legal_matrix_issue)$fatal(1,"restore progress did not release debt");$display("[pass] CGX 1 mixed compute service-progress policy checks passed.");$finish;end
endmodule
