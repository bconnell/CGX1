// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_vector_int32_pipeline #(
 parameter integer WAVE_SLOT_WIDTH=4
)(
 input logic clk, reset_n,
 input logic issue_valid,
 input logic [WAVE_SLOT_WIDTH-1:0] issue_wave_slot,
 input logic [3:0] issue_opcode,
 input logic [7:0] issue_source0, issue_source1, issue_destination,
 input logic [31:0] issue_lane_mask,
 output logic issue_ready, issue_accepted,
 output logic read_valid,
 output logic [WAVE_SLOT_WIDTH-1:0] read_wave_slot,
 output logic [7:0] read_source0, read_source1,
 input logic read_response_valid, read_address_fault, read_uninitialized,
 input logic [1023:0] read_data0, read_data1,
 output logic write_valid,
 output logic [WAVE_SLOT_WIDTH-1:0] write_wave_slot,
 output logic [7:0] write_destination,
 output logic [31:0] write_lane_mask,
 output logic [1023:0] write_data,
 input logic write_ready,
 input logic write_address_fault,
 output logic complete_valid,
 output logic [WAVE_SLOT_WIDTH-1:0] complete_wave_slot,
 output logic illegal_opcode,
 output logic address_fault,
 output logic uninitialized_fault,
 output logic busy,
 output logic [WAVE_SLOT_WIDTH-1:0] live_wave_slot,
 output logic [7:0] live_source0, live_source1, live_destination,
 output logic source_locks_live, destination_lock_live
);
 localparam logic [2:0] IDLE=0,READ=1,EXEC=2,WRITE=3,DONE=4;
 logic [2:0] state_q;
 logic [3:0] opcode_q;
 logic [WAVE_SLOT_WIDTH-1:0] wave_q;
 logic [7:0] s0_q,s1_q,d_q;
 logic [31:0] mask_q;
 logic [1023:0] a_q,b_q,result;
 logic alu_illegal;
 logic illegal_opcode_q;
 logic address_fault_q, uninitialized_fault_q;
 cgx1_vector_int32_alu alu(.opcode(opcode_q),.source0_data(a_q),.source1_data(b_q),.lane_mask(mask_q),.result_data(result),.illegal_opcode(alu_illegal));
 always_comb begin
   issue_ready=(state_q==IDLE); issue_accepted=issue_valid&&issue_ready;
   read_valid=(state_q==READ); read_wave_slot=wave_q; read_source0=s0_q; read_source1=s1_q;
   write_valid=(state_q==WRITE); write_wave_slot=wave_q; write_destination=d_q; write_lane_mask=mask_q; write_data=result;
   complete_valid=(state_q==DONE); complete_wave_slot=wave_q; busy=(state_q!=IDLE);
   live_wave_slot=wave_q; live_source0=s0_q; live_source1=s1_q; live_destination=d_q;
   source_locks_live=(state_q==READ); destination_lock_live=(state_q==READ)||(state_q==EXEC)||(state_q==WRITE);
   illegal_opcode=(state_q==DONE)&&illegal_opcode_q; address_fault=(state_q==DONE)&&address_fault_q; uninitialized_fault=(state_q==DONE)&&uninitialized_fault_q;
 end
 always_ff @(posedge clk or negedge reset_n) begin
   if(!reset_n) begin state_q<=IDLE; opcode_q<='0; wave_q<='0; s0_q<='0; s1_q<='0; d_q<='0; mask_q<='0; a_q<='0; b_q<='0; illegal_opcode_q<=1'b0; address_fault_q<=1'b0; uninitialized_fault_q<=1'b0; end
   else case(state_q)
     IDLE: if(issue_accepted) begin state_q<=(issue_opcode>4'd7)?DONE:READ; opcode_q<=issue_opcode; wave_q<=issue_wave_slot; s0_q<=issue_source0; s1_q<=issue_source1; d_q<=issue_destination; mask_q<=issue_lane_mask; illegal_opcode_q<=(issue_opcode>4'd7); address_fault_q<=1'b0; uninitialized_fault_q<=1'b0; end
     READ: if(read_response_valid) begin a_q<=read_data0; b_q<=read_data1; address_fault_q<=read_address_fault; uninitialized_fault_q<=read_uninitialized; if(read_address_fault||read_uninitialized) state_q<=DONE; else state_q<=EXEC; end
     EXEC: state_q<=alu_illegal?DONE:WRITE;
     WRITE: if(write_address_fault) begin address_fault_q<=1'b1; state_q<=DONE; end else if(write_ready) state_q<=DONE;
     DONE: state_q<=IDLE;
     default: state_q<=IDLE;
   endcase
 end
endmodule
