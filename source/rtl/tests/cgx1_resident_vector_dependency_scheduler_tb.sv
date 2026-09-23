// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_resident_vector_dependency_scheduler_tb;
 localparam integer SLOTS=4,SLOT_WIDTH=2;
 logic clk=0,reset_n=0;logic[SLOTS-1:0]request_valid;logic[(SLOTS*8)-1:0]request_source0,request_source1,request_destination;logic[(SLOTS*256)-1:0]matrix_source_pending_flat,matrix_destination_pending_flat;logic[SLOTS-1:0]dependency_ready,raw_hazard,waw_hazard,war_hazard;logic selected_valid;logic[SLOT_WIDTH-1:0]selected_wave_slot;logic selected_accepted;
 always #5 clk=~clk;
 cgx1_resident_vector_dependency_scheduler #(.RESIDENT_WAVE_SLOTS(SLOTS),.WAVE_SLOT_WIDTH(SLOT_WIDTH)) dut(.*);
 initial begin request_valid='0;request_source0='0;request_source1='0;request_destination='0;matrix_source_pending_flat='0;matrix_destination_pending_flat='0;selected_accepted=0;repeat(2)@(posedge clk);@(negedge clk);reset_n=1;
  request_valid[0]=1;request_valid[2]=1;request_source0[0+:8]=32;request_source1[0+:8]=7;request_destination[0+:8]=9;request_source0[(2*8)+:8]=10;request_source1[(2*8)+:8]=11;request_destination[(2*8)+:8]=12;matrix_destination_pending_flat[32]=1;#1;
  if(!raw_hazard[0]||dependency_ready[0])$fatal(1,"wave0 RAW dependency missing");if(!dependency_ready[2])$fatal(1,"wave2 falsely blocked");if(!selected_valid||selected_wave_slot!=2)$fatal(1,"blocked wave0 head-of-line blocked wave2");
  selected_accepted=1;@(posedge clk);#1;@(negedge clk);selected_accepted=0;matrix_destination_pending_flat[32]=0;matrix_source_pending_flat[9]=1;#1;if(!war_hazard[0])$fatal(1,"wave0 WAR dependency missing");matrix_source_pending_flat[9]=0;matrix_destination_pending_flat[9]=1;#1;if(!waw_hazard[0])$fatal(1,"wave0 WAW dependency missing");
  $display("[pass] CGX 1 resident vector dependency scheduler checks passed.");$finish;
 end
endmodule
