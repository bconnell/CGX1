// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_ordinary_read_sequencer_tb;
 logic clk=0,reset_n=0,request_valid;logic[1:0]request_wave_slot;logic[7:0]request_source0,request_source1;logic[3:0]source0_row,source1_row;logic[2:0]source0_bank,source1_bank;logic source0_valid,source1_valid,exact_alias,distinct_same_bank;
 logic service_valid;logic[3:0]service_row0,service_row1;logic[2:0]service_bank0,service_bank1;logic service_single,service_ready,service0_initialized,service1_initialized;logic[1023:0]service0_data,service1_data;logic response_valid,response_address_fault,response_uninitialized;logic[1023:0]response0_data,response1_data;logic split_pending;logic[1:0]split_wave_slot;
 always #5 clk=~clk;
 cgx1_pooled_vgpr_ordinary_read_sequencer #(.ROW_WIDTH(4),.WAVE_SLOT_WIDTH(2)) dut(.*);
 initial begin
  request_valid=0;request_wave_slot=0;request_source0=0;request_source1=0;source0_row=0;source1_row=0;source0_bank=0;source1_bank=0;source0_valid=0;source1_valid=0;exact_alias=0;distinct_same_bank=0;service_ready=0;service0_initialized=1;service1_initialized=1;service0_data='h11;service1_data='h22;
  repeat(2)@(posedge clk);@(negedge clk);reset_n=1;
  request_valid=1;source0_valid=0;source1_valid=1;#1;if(!response_valid||!response_address_fault)$fatal(1,"invalid ordinary read did not terminate with address fault");
  source0_valid=1;exact_alias=1;source0_row=2;source0_bank=3;service_ready=1;service0_data='h1234;#1;if(!response_valid||response0_data!=='h1234||response1_data!=='h1234)$fatal(1,"exact alias did not broadcast");
  exact_alias=0;distinct_same_bank=1;request_wave_slot=2;request_source0=8'd4;request_source1=8'd12;source0_row=1;source1_row=2;source0_bank=4;source1_bank=4;service0_data='hAAAA;#1;if(!service_valid||!service_single)$fatal(1,"same-bank pair did not request first serialized read");@(posedge clk);#1;@(negedge clk);#1;if(!split_pending||split_wave_slot!=2||service_row0!=2)$fatal(1,"split read did not retain second physical address");service0_data='hBBBB;#1;if(!response_valid||response0_data!=='hAAAA||response1_data!=='hBBBB)$fatal(1,"split read did not reassemble operands");
  request_source1=8'd13;#1;if(response_valid)$fatal(1,"split completion acknowledged a changed request identity");
  $display("[pass] CGX 1 ordinary same-bank read sequencing checks passed.");$finish;
 end
endmodule
