// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_vector_int32_pipeline_tb;
 logic clk=0,reset_n=0,issue_valid;logic[1:0]issue_wave_slot;logic[3:0]issue_opcode;logic[7:0]issue_source0,issue_source1,issue_destination;logic[31:0]issue_lane_mask;logic issue_ready,issue_accepted;
 logic read_valid;logic[1:0]read_wave_slot;logic[7:0]read_source0,read_source1;logic read_response_valid,read_address_fault,read_uninitialized;logic[1023:0]read_data0,read_data1;
 logic write_valid;logic[1:0]write_wave_slot;logic[7:0]write_destination;logic[31:0]write_lane_mask;logic[1023:0]write_data;logic write_ready,write_address_fault;
 logic complete_valid;logic[1:0]complete_wave_slot;logic illegal_opcode,address_fault,uninitialized_fault,busy;logic[7:0]live_source0,live_source1,live_destination;logic source_locks_live,destination_lock_live;
 always #5 clk=~clk;
 cgx1_vector_int32_pipeline #(.WAVE_SLOT_WIDTH(2)) dut(.*);
 task automatic issue(input logic[3:0]op);begin @(negedge clk);issue_opcode=op;issue_valid=1;#1;if(!issue_ready||!issue_accepted)$fatal(1,"vector issue handshake failed");@(posedge clk);#1;@(negedge clk);issue_valid=0;end endtask
 initial begin
  issue_valid=0;issue_wave_slot=2;issue_opcode=0;issue_source0=8'd1;issue_source1=8'd2;issue_destination=8'd3;issue_lane_mask=32'hffffffff;read_response_valid=0;read_address_fault=0;read_uninitialized=0;read_data0='0;read_data1='0;write_ready=0;write_address_fault=0;
  read_data0[31:0]=10;read_data1[31:0]=3;
  repeat(2)@(posedge clk);@(negedge clk);reset_n=1;
  issue(4'h0);#1;if(!read_valid||!source_locks_live||!destination_lock_live)$fatal(1,"vector read stage locks are incorrect");read_response_valid=1;@(posedge clk);#1;@(negedge clk);read_response_valid=0;@(posedge clk);#1;@(negedge clk);#1;if(!write_valid||write_data[31:0]!=13)$fatal(1,"vector ADD did not reach writeback");write_ready=1;@(posedge clk);#1;@(negedge clk);write_ready=0;#1;if(!complete_valid||address_fault||uninitialized_fault||illegal_opcode)$fatal(1,"normal vector completion flags incorrect");@(posedge clk);#1;@(negedge clk);
  issue(4'h0);read_response_valid=1;read_address_fault=1;@(posedge clk);#1;@(negedge clk);read_response_valid=0;read_address_fault=0;#1;if(!complete_valid||!address_fault)$fatal(1,"read address fault was not latched");@(posedge clk);#1;@(negedge clk);
  issue(4'h0);read_response_valid=1;@(posedge clk);#1;@(negedge clk);read_response_valid=0;@(posedge clk);#1;@(negedge clk);write_address_fault=1;#1;if(!write_valid)$fatal(1,"vector write stage missing before destination fault");@(posedge clk);#1;@(negedge clk);write_address_fault=0;#1;if(!complete_valid||!address_fault)$fatal(1,"write address fault was not latched");@(posedge clk);#1;@(negedge clk);
  issue(4'h8);read_response_valid=1;@(posedge clk);#1;@(negedge clk);read_response_valid=0;@(posedge clk);#1;@(negedge clk);#1;if(!complete_valid||!illegal_opcode||write_valid)$fatal(1,"illegal vector opcode did not terminate before writeback");
  $display("[pass] CGX 1 vector INT32 pipeline checks passed.");$finish;
 end
endmodule
