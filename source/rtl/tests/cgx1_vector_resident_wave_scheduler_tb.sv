// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_vector_resident_wave_scheduler_tb;
 logic clk=0,reset_n=0;logic[3:0]request_valid,dependency_ready;logic selected_valid;logic[1:0]selected_wave_slot;logic selected_accepted;integer i;
 always #5 clk=~clk;
 cgx1_vector_resident_wave_scheduler #(.RESIDENT_WAVE_SLOTS(4),.WAVE_SLOT_WIDTH(2)) dut(.*);
 initial begin request_valid=4'b1111;dependency_ready=4'b1111;selected_accepted=0;repeat(2)@(posedge clk);@(negedge clk);reset_n=1;
  for(i=0;i<8;i=i+1)begin #1;if(!selected_valid||selected_wave_slot!=(i%4))$fatal(1,"round-robin scheduler mismatch at %0d",i);selected_accepted=1;@(posedge clk);#1;@(negedge clk);selected_accepted=0;end
  dependency_ready=4'b1011;dut.next_q=2;#1;if(selected_wave_slot!=3)$fatal(1,"scheduler did not skip dependency-blocked wave");
  request_valid=0;#1;if(selected_valid)$fatal(1,"scheduler selected an empty request set");
  $display("[pass] CGX 1 resident vector scheduler checks passed.");$finish;
 end
endmodule
