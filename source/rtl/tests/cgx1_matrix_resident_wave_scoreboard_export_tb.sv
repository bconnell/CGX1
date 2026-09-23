// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_matrix_resident_wave_scoreboard_export_tb;
 localparam integer SLOTS=4,SLOT_WIDTH=2;
 logic clk=0,reset_n=0,matrix_issue_accepted;logic[SLOT_WIDTH-1:0]matrix_issue_wave_slot;logic[7:0]matrix_accepted_d_base,matrix_accepted_a_base,matrix_accepted_b_base;
 logic matrix_source_release_valid;logic[SLOT_WIDTH-1:0]matrix_source_release_wave_slot;logic[7:0]matrix_source_release_a_base,matrix_source_release_b_base;
 logic matrix_destination_complete_valid;logic[SLOT_WIDTH-1:0]matrix_destination_complete_wave_slot;logic[7:0]matrix_destination_complete_base;
 logic matrix_rf_read_valid,matrix_rf_write_valid,ordinary_issue_valid;logic[SLOT_WIDTH-1:0]ordinary_wave_slot;logic[255:0]ordinary_read_mask,ordinary_write_mask;logic ordinary_uses_read_ports,ordinary_uses_write_port;
 logic ordinary_raw_hazard,ordinary_waw_hazard,ordinary_war_hazard,ordinary_read_port_conflict,ordinary_write_port_conflict,ordinary_ready,ordinary_issue_accepted;
 logic[255:0]selected_source_pending_mask,selected_destination_pending_mask;logic[(SLOTS*256)-1:0]resident_source_pending_mask_flat,resident_destination_pending_mask_flat;logic[SLOTS-1:0]resident_wave_busy;integer i;
 always #5 clk=~clk;
 cgx1_matrix_resident_wave_scoreboard #(.RESIDENT_WAVE_SLOTS(SLOTS),.WAVE_SLOT_WIDTH(SLOT_WIDTH)) dut(.*);
 initial begin
  matrix_issue_accepted=0;matrix_issue_wave_slot=0;matrix_accepted_d_base=0;matrix_accepted_a_base=0;matrix_accepted_b_base=0;matrix_source_release_valid=0;matrix_source_release_wave_slot=0;matrix_source_release_a_base=0;matrix_source_release_b_base=0;matrix_destination_complete_valid=0;matrix_destination_complete_wave_slot=0;matrix_destination_complete_base=0;matrix_rf_read_valid=0;matrix_rf_write_valid=0;ordinary_issue_valid=0;ordinary_wave_slot=0;ordinary_read_mask='0;ordinary_write_mask='0;ordinary_uses_read_ports=0;ordinary_uses_write_port=0;
  repeat(2)@(posedge clk);@(negedge clk);reset_n=1;
  matrix_issue_wave_slot=2;matrix_accepted_d_base=32;matrix_accepted_a_base=64;matrix_accepted_b_base=68;matrix_issue_accepted=1;@(posedge clk);#1;@(negedge clk);matrix_issue_accepted=0;#1;
  for(i=0;i<4;i=i+1)begin if(!resident_source_pending_mask_flat[(2*256)+64+i])$fatal(1,"wave2 A snapshot missing");if(!resident_source_pending_mask_flat[(2*256)+68+i])$fatal(1,"wave2 B snapshot missing");end
  for(i=0;i<8;i=i+1)if(!resident_destination_pending_mask_flat[(2*256)+32+i])$fatal(1,"wave2 destination snapshot missing");
  if(|resident_source_pending_mask_flat[0+:512]|| |resident_destination_pending_mask_flat[0+:512] || |resident_source_pending_mask_flat[(3*256)+:256] || |resident_destination_pending_mask_flat[(3*256)+:256])$fatal(1,"snapshot leaked across waves");
  matrix_source_release_wave_slot=2;matrix_source_release_a_base=64;matrix_source_release_b_base=68;matrix_source_release_valid=1;@(posedge clk);#1;@(negedge clk);matrix_source_release_valid=0;#1;if(|resident_source_pending_mask_flat[(2*256)+:256])$fatal(1,"source snapshot did not clear");if(!(|resident_destination_pending_mask_flat[(2*256)+:256]))$fatal(1,"destination cleared too early");
  matrix_destination_complete_wave_slot=2;matrix_destination_complete_base=32;matrix_destination_complete_valid=1;@(posedge clk);#1;@(negedge clk);matrix_destination_complete_valid=0;#1;if(|resident_destination_pending_mask_flat[(2*256)+:256])$fatal(1,"destination snapshot did not clear");
  $display("[pass] CGX 1 resident matrix scoreboard flattened-export checks passed.");$finish;
 end
endmodule
