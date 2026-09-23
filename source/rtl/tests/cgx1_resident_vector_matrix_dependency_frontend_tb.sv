// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_resident_vector_matrix_dependency_frontend_tb;
 localparam integer SLOTS=4,SLOT_WIDTH=2;
 logic clk=0,reset_n=0;logic[SLOTS-1:0]request_valid;logic[(SLOTS*4)-1:0]request_opcode;logic[(SLOTS*8)-1:0]request_source0,request_source1,request_destination;logic[(SLOTS*32)-1:0]request_lane_mask;logic[(SLOTS*256)-1:0]matrix_source_pending_flat,matrix_destination_pending_flat;logic[SLOTS-1:0]dependency_ready,raw_hazard,waw_hazard,war_hazard,request_accepted;logic selected_valid;logic[SLOT_WIDTH-1:0]selected_wave_slot;logic[3:0]selected_opcode;logic[7:0]selected_source0,selected_source1,selected_destination;logic[31:0]selected_lane_mask;logic selected_ready;
 always #5 clk=~clk;
 cgx1_resident_vector_matrix_dependency_frontend #(.RESIDENT_WAVE_SLOTS(SLOTS),.WAVE_SLOT_WIDTH(SLOT_WIDTH)) dut(.*);
 initial begin request_valid='0;request_opcode='0;request_source0='0;request_source1='0;request_destination='0;request_lane_mask='0;matrix_source_pending_flat='0;matrix_destination_pending_flat='0;selected_ready=0;repeat(2)@(posedge clk);@(negedge clk);reset_n=1;
  request_valid[0]=1;request_valid[1]=1;request_opcode[0+:4]=4'h2;request_opcode[4+:4]=4'h4;request_source0[0+:8]=32;request_source1[0+:8]=2;request_destination[0+:8]=3;request_lane_mask[0+:32]=32'h0000ffff;request_source0[8+:8]=10;request_source1[8+:8]=11;request_destination[8+:8]=12;request_lane_mask[32+:32]=32'hffff0000;matrix_destination_pending_flat[32]=1;#1;
  if(!selected_valid||selected_wave_slot!=1||selected_opcode!=4'h4||selected_destination!=12)$fatal(1,"dependency frontend selected/routed wrong wave");selected_ready=1;#1;if(!request_accepted[1]||request_accepted[0])$fatal(1,"dependency frontend accepted wrong wave");@(posedge clk);#1;@(negedge clk);selected_ready=0;matrix_destination_pending_flat[32]=0;request_valid[1]=0;#1;if(!selected_valid||selected_wave_slot!=0||selected_opcode!=4'h2)$fatal(1,"dependency frontend did not recover wave0");
  $display("[pass] CGX 1 resident vector matrix-dependency frontend checks passed.");$finish;
 end
endmodule
