// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_pooled_vgpr_ordinary_read_sequencer #(
 parameter integer ROW_WIDTH=7,
 parameter integer WAVE_SLOT_WIDTH=4
)(
 input logic clk, reset_n,
 input logic request_valid,
 input logic [WAVE_SLOT_WIDTH-1:0] request_wave_slot,
 input logic [7:0] request_source0, request_source1,
 input logic [ROW_WIDTH-1:0] source0_row, source1_row,
 input logic [2:0] source0_bank, source1_bank,
 input logic source0_valid, source1_valid, exact_alias, distinct_same_bank,
 output logic service_valid,
 output logic [ROW_WIDTH-1:0] service_row0, service_row1,
 output logic [2:0] service_bank0, service_bank1,
 output logic service_single,
 input logic service_ready,
 input logic service0_initialized, service1_initialized,
 input logic [1023:0] service0_data, service1_data,
 output logic response_valid,
 output logic response_address_fault,
 output logic response_uninitialized,
 output logic [1023:0] response0_data, response1_data,
 output logic split_pending,
 output logic [WAVE_SLOT_WIDTH-1:0] split_wave_slot
);
 logic split_q;
 logic [WAVE_SLOT_WIDTH-1:0] wave_q;
 logic [7:0] src0_q,src1_q;
 logic [ROW_WIDTH-1:0] row1_q;
 logic [2:0] bank1_q;
 logic [1023:0] first_data_q;
 logic first_init_q;
 always_comb begin
   split_pending=split_q; split_wave_slot=wave_q;
   service_valid=0; service_row0='0; service_row1='0; service_bank0='0; service_bank1='0; service_single=0;
   response_valid=0; response_address_fault=0; response_uninitialized=0; response0_data='0; response1_data='0;
   if(!split_q) begin
     if(request_valid && (!source0_valid || !source1_valid)) begin response_valid=1; response_address_fault=1; end
     else if(request_valid && exact_alias) begin
       service_valid=1; service_row0=source0_row; service_row1=source0_row; service_bank0=source0_bank; service_bank1=source0_bank;
       if(service_ready) begin response_valid=1; response_uninitialized=!service0_initialized; response0_data=service0_data; response1_data=service0_data; end
     end else if(request_valid && distinct_same_bank) begin
       service_valid=1; service_single=1; service_row0=source0_row; service_row1=source0_row; service_bank0=source0_bank; service_bank1=source0_bank;
     end else if(request_valid) begin
       service_valid=1; service_row0=source0_row; service_row1=source1_row; service_bank0=source0_bank; service_bank1=source1_bank;
       if(service_ready) begin response_valid=1; response_uninitialized=!(service0_initialized&&service1_initialized); response0_data=service0_data; response1_data=service1_data; end
     end
   end else begin
     service_valid=1; service_single=1; service_row0=row1_q; service_row1=row1_q; service_bank0=bank1_q; service_bank1=bank1_q;
     if(service_ready) begin
       response_valid=request_valid && request_wave_slot==wave_q && request_source0==src0_q && request_source1==src1_q;
       response_uninitialized=!(first_init_q&&service0_initialized);
       response0_data=first_data_q; response1_data=service0_data;
     end
   end
 end
 always_ff @(posedge clk or negedge reset_n) begin
   if(!reset_n) begin split_q<=0; wave_q<='0; src0_q<='0; src1_q<='0; row1_q<='0; bank1_q<='0; first_data_q<='0; first_init_q<=0; end
   else begin
     if(!split_q && request_valid && distinct_same_bank && source0_valid && source1_valid && service_ready) begin
       split_q<=1; wave_q<=request_wave_slot; src0_q<=request_source0; src1_q<=request_source1; row1_q<=source1_row; bank1_q<=source1_bank; first_data_q<=service0_data; first_init_q<=service0_initialized;
     end else if(split_q && service_ready && request_valid && request_wave_slot==wave_q && request_source0==src0_q && request_source1==src1_q) begin split_q<=0; end
   end
 end
endmodule
