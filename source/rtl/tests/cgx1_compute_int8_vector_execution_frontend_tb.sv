// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_compute_int8_vector_execution_frontend_tb;
 localparam integer ROWS=32,SLOTS=2,ROW_WIDTH=5,SLOT_WIDTH=1;
 logic clk=0,reset_n=0;
 logic reserve_valid;logic[SLOT_WIDTH-1:0]reserve_wave_slot;logic[8:0]reserve_register_count;logic reserve_ready,reserve_accepted;
 logic activate_valid;logic[SLOT_WIDTH-1:0]activate_wave_slot;logic activate_ready,activate_accepted;
 logic release_valid;logic[SLOT_WIDTH-1:0]release_wave_slot;logic release_quiescent,release_ready,release_accepted;
 logic restore_valid;logic[SLOT_WIDTH-1:0]restore_wave_slot;logic[7:0]restore_register;logic[1023:0]restore_data;logic restore_ready;
 logic[SLOTS-1:0]matrix_request_valid,matrix_request_full_wave_active;logic[(SLOTS*8)-1:0]matrix_request_d_base,matrix_request_a_base,matrix_request_b_base;logic[SLOTS-1:0]matrix_request_ready,matrix_request_accepted;logic matrix_illegal_issue;logic[SLOT_WIDTH-1:0]matrix_illegal_wave_slot;
 logic[SLOTS-1:0]vector_request_valid,vector_dependency_ready;logic[(SLOTS*4)-1:0]vector_request_opcode;logic[(SLOTS*8)-1:0]vector_request_source0,vector_request_source1,vector_request_destination;logic[(SLOTS*32)-1:0]vector_request_lane_mask;logic[SLOTS-1:0]vector_request_accepted;
 logic vector_complete_valid;logic[SLOT_WIDTH-1:0]vector_complete_wave_slot;logic vector_illegal_opcode,vector_address_fault,vector_uninitialized_fault;logic[SLOTS-1:0]matrix_resident_wave_busy;logic vector_busy;
 integer timeout,register_index;
 always #5 clk=~clk;
 cgx1_compute_int8_vector_execution_frontend #(.PHYSICAL_ROWS(ROWS),.RESIDENT_WAVE_SLOTS(SLOTS),.ROW_WIDTH(ROW_WIDTH),.WAVE_SLOT_WIDTH(SLOT_WIDTH)) dut(.*);
 function automatic[1023:0]wave_pattern(input logic[31:0]base);integer lane;begin wave_pattern='0;for(lane=0;lane<32;lane=lane+1)wave_pattern[(lane*32)+:32]=base+lane;end endfunction
 task automatic reserve_wave(input logic[SLOT_WIDTH-1:0]slot,input logic[8:0]count);begin @(negedge clk);reserve_wave_slot=slot;reserve_register_count=count;reserve_valid=1;#1;if(!reserve_ready||!reserve_accepted)$fatal(1,"mixed frontend reserve handshake failed");@(posedge clk);#1;@(negedge clk);reserve_valid=0;timeout=0;while(!dut.pooled.alloc_sanitized[slot])begin @(posedge clk);#1;timeout=timeout+1;if(timeout>48)$fatal(1,"mixed frontend allocation sanitization timed out");end end endtask
 task automatic restore_word(input logic[SLOT_WIDTH-1:0]slot,input logic[7:0]register_number,input logic[1023:0]value);begin @(negedge clk);restore_wave_slot=slot;restore_register=register_number;restore_data=value;restore_valid=1;timeout=0;#1;while(!restore_ready)begin @(posedge clk);#1;timeout=timeout+1;if(timeout>32)$fatal(1,"mixed frontend restore never became ready");end @(posedge clk);#1;@(negedge clk);restore_valid=0;end endtask
 task automatic activate_wave(input logic[SLOT_WIDTH-1:0]slot);begin @(negedge clk);activate_wave_slot=slot;activate_valid=1;#1;if(!activate_ready||!activate_accepted)$fatal(1,"mixed frontend activation handshake failed");@(posedge clk);#1;@(negedge clk);activate_valid=0;end endtask
 task automatic issue_vector(input logic[SLOT_WIDTH-1:0]slot,input logic[3:0]opcode,input logic[7:0]source0,input logic[7:0]source1,input logic[7:0]destination);begin vector_request_opcode[(slot*4)+:4]=opcode;vector_request_source0[(slot*8)+:8]=source0;vector_request_source1[(slot*8)+:8]=source1;vector_request_destination[(slot*8)+:8]=destination;vector_request_lane_mask[(slot*32)+:32]=32'hffffffff;vector_request_valid[slot]=1;timeout=0;while(!vector_request_accepted[slot])begin @(negedge clk);#1;timeout=timeout+1;if(timeout>32)$fatal(1,"mixed frontend vector request was never accepted");end @(posedge clk);#1;@(negedge clk);vector_request_valid[slot]=0;end endtask
 task automatic wait_vector_complete(input logic[SLOT_WIDTH-1:0]slot);begin timeout=0;while(!vector_complete_valid)begin @(posedge clk);#1;timeout=timeout+1;if(timeout>48)$fatal(1,"mixed frontend vector operation did not complete");end if(vector_complete_wave_slot!=slot)$fatal(1,"mixed frontend vector completion carried wrong wave slot");if(vector_illegal_opcode||vector_address_fault||vector_uninitialized_fault)$fatal(1,"mixed frontend legal vector operation completed with a fault");end endtask
 initial begin
  reserve_valid=0;reserve_wave_slot='0;reserve_register_count='0;activate_valid=0;activate_wave_slot='0;release_valid=0;release_wave_slot='0;release_quiescent=0;restore_valid=0;restore_wave_slot='0;restore_register='0;restore_data='0;matrix_request_valid='0;matrix_request_full_wave_active='1;matrix_request_d_base='0;matrix_request_a_base='0;matrix_request_b_base='0;vector_request_valid='0;vector_dependency_ready='1;vector_request_opcode='0;vector_request_source0='0;vector_request_source1='0;vector_request_destination='0;vector_request_lane_mask='0;
  repeat(3)@(posedge clk);@(negedge clk);reset_n=1;
  reserve_wave(0,9'd72);restore_word(0,8'd0,wave_pattern(32'd10));restore_word(0,8'd1,wave_pattern(32'd3));
  for(register_index=32;register_index<40;register_index=register_index+1)restore_word(0,register_index[7:0],wave_pattern(32'h1000+register_index));
  for(register_index=64;register_index<72;register_index=register_index+1)restore_word(0,register_index[7:0],'0);
  activate_wave(0);
  fork
    issue_vector(0,4'h0,8'd0,8'd1,8'd2);
    begin wait(vector_busy);@(negedge clk);release_wave_slot=0;release_quiescent=1;release_valid=1;#1;if(release_ready||release_accepted)$fatal(1,"mixed frontend release ignored live vector execution");release_valid=0;release_quiescent=0;end
  join
  wait_vector_complete(0);
  if(dut.pooled.storage.data[0][2][31:0]!==32'd13)$fatal(1,"mixed frontend vector ADD did not write pooled VGPR destination");
  vector_request_opcode[0+:4]=4'h0;vector_request_source0[0+:8]=8'd0;vector_request_source1[0+:8]=8'd1;vector_request_destination[0+:8]=8'd64;vector_request_lane_mask[0+:32]=32'hffffffff;vector_request_valid[0]=1;timeout=0;while(!vector_request_accepted[0])begin @(negedge clk);#1;timeout=timeout+1;if(timeout>32)$fatal(1,"hazard setup vector request was not accepted");end @(posedge clk);#1;@(negedge clk);vector_request_valid[0]=0;
  matrix_request_d_base[0+:8]=8'd32;matrix_request_a_base[0+:8]=8'd64;matrix_request_b_base[0+:8]=8'd68;matrix_request_valid[0]=1;#1;if(vector_busy&&dut.vec_dest_lock&&matrix_request_ready[0])$fatal(1,"matrix request ignored live vector destination hazard");
  timeout=0;while(!matrix_request_ready[0])begin @(negedge clk);#1;timeout=timeout+1;if(timeout>64)$fatal(1,"matrix request did not recover after vector hazard cleared");end
  vector_request_opcode[0+:4]=4'h0;vector_request_source0[0+:8]=8'd0;vector_request_source1[0+:8]=8'd1;vector_request_destination[0+:8]=8'd3;vector_request_valid[0]=1;#1;if(matrix_request_accepted[0]&&vector_request_accepted[0])$fatal(1,"matrix and vector requests were accepted on the same issue edge");@(posedge clk);#1;@(negedge clk);matrix_request_valid[0]=0;vector_request_valid[0]=0;
  $display("[pass] CGX 1 mixed resident INT8/vector execution frontend checks passed.");$finish;
 end
endmodule
