// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_pooled_vgpr_execution_subsystem_tb;
 localparam integer ROWS=16,SLOTS=2,ROW_WIDTH=4,SLOT_WIDTH=1;
 logic clk=0,reset_n=0;
 logic reserve_valid;logic[SLOT_WIDTH-1:0]reserve_wave_slot;logic[8:0]reserve_register_count;logic reserve_ready,reserve_accepted;
 logic activate_valid;logic[SLOT_WIDTH-1:0]activate_wave_slot;logic activate_ready,activate_accepted;
 logic release_valid;logic[SLOT_WIDTH-1:0]release_wave_slot;logic release_quiescent,release_ready,release_accepted;logic[SLOTS-1:0]matrix_execution_busy,vector_execution_busy;
 logic restore_valid;logic[SLOT_WIDTH-1:0]restore_wave_slot;logic[7:0]restore_register;logic[1023:0]restore_data;logic restore_ready;
 logic[SLOTS-1:0]matrix_request_valid;logic[(SLOTS*8)-1:0]matrix_request_d_base,matrix_request_a_base,matrix_request_b_base;logic[SLOTS-1:0]matrix_request_preflight_ready,matrix_request_gated_valid;
 logic matrix_rf_read_valid;logic[SLOT_WIDTH-1:0]matrix_rf_read_wave_slot;logic[7:0]matrix_rf_read_addr0,matrix_rf_read_addr1;logic matrix_rf_read_ready,matrix_rf_read0_initialized,matrix_rf_read1_initialized;logic[1023:0]matrix_rf_read_data0,matrix_rf_read_data1;
 logic matrix_rf_write_valid;logic[SLOT_WIDTH-1:0]matrix_rf_write_wave_slot;logic[7:0]matrix_rf_write_addr;logic[1023:0]matrix_rf_write_data;logic matrix_rf_write_ready;
 logic ordinary_read_valid;logic[SLOT_WIDTH-1:0]ordinary_read_wave_slot;logic[7:0]ordinary_read_source0,ordinary_read_source1;logic ordinary_read_response_valid,ordinary_read_address_fault,ordinary_read_uninitialized;logic[1023:0]ordinary_read_data0,ordinary_read_data1;
 logic ordinary_write_valid;logic[SLOT_WIDTH-1:0]ordinary_write_wave_slot;logic[7:0]ordinary_write_destination;logic[31:0]ordinary_write_lane_mask;logic[1023:0]ordinary_write_data;logic ordinary_write_ready,ordinary_write_address_fault;
 logic restore_service_waiting,restore_service_accepted;
 integer timeout;
 always #5 clk=~clk;
 cgx1_pooled_vgpr_execution_subsystem #(.PHYSICAL_ROWS(ROWS),.RESIDENT_WAVE_SLOTS(SLOTS),.ROW_WIDTH(ROW_WIDTH),.WAVE_SLOT_WIDTH(SLOT_WIDTH)) dut(.*);
 function automatic[1023:0]pat(input logic[31:0]base);integer i;begin pat='0;for(i=0;i<32;i=i+1)pat[(i*32)+:32]=base+i;end endfunction
 task automatic restore_word(input logic[7:0]register_index,input logic[1023:0]value);begin @(negedge clk);restore_register=register_index;restore_data=value;restore_valid=1;timeout=0;#1;while(!restore_ready)begin @(negedge clk);#1;timeout=timeout+1;if(timeout>20)$fatal(1,
  "restore never became ready: reserved=%0b sanitized=%0b map=%0b grant=%0b storage_write_ready=%0b invalidate_valid=%0b invalidate_row=%0d restore_row=%0d count=%0d base=%0d",
  dut.alloc_reserved[restore_wave_slot],
  dut.alloc_sanitized[restore_wave_slot],
  dut.restore_map_valid,
  dut.gr,
  dut.storage_write_ready,
  dut.invalidate_valid,
  dut.invalidate_row,
  dut.restore_row,
  dut.restore_count_sel,
  dut.restore_base_sel);end @(posedge clk);#1;@(negedge clk);restore_valid=0;end endtask
 initial begin
  reserve_valid=0;reserve_wave_slot=0;reserve_register_count=0;activate_valid=0;activate_wave_slot=0;release_valid=0;release_wave_slot=0;release_quiescent=0;matrix_execution_busy=0;vector_execution_busy=0;restore_valid=0;restore_wave_slot=0;restore_register=0;restore_data=0;matrix_request_valid=0;matrix_request_d_base=0;matrix_request_a_base=0;matrix_request_b_base=0;matrix_rf_read_valid=0;matrix_rf_read_wave_slot=0;matrix_rf_read_addr0=0;matrix_rf_read_addr1=0;matrix_rf_write_valid=0;matrix_rf_write_wave_slot=0;matrix_rf_write_addr=0;matrix_rf_write_data=0;ordinary_read_valid=0;ordinary_read_wave_slot=0;ordinary_read_source0=0;ordinary_read_source1=0;ordinary_write_valid=0;ordinary_write_wave_slot=0;ordinary_write_destination=0;ordinary_write_lane_mask=0;ordinary_write_data=0;
  repeat(3)@(posedge clk);@(negedge clk);reset_n=1;
  reserve_wave_slot=0;reserve_register_count=9'd16;reserve_valid=1;#1;if(!reserve_ready||!reserve_accepted)$fatal(1,"reserve handshake failed");@(posedge clk);#1;@(negedge clk);reserve_valid=0;
  timeout=0;while(!dut.alloc_sanitized[0])begin @(posedge clk);#1;timeout=timeout+1;if(timeout>20)$fatal(1,"allocation sanitization did not complete");end
  restore_word(0,pat(32'h1000));restore_word(1,pat(32'h2000));restore_word(8,pat(32'h8000));
  activate_wave_slot=0;activate_valid=1;#1;if(!activate_ready||!activate_accepted)$fatal(1,"activate handshake failed");@(posedge clk);#1;@(negedge clk);activate_valid=0;
  ordinary_read_wave_slot=0;ordinary_read_source0=0;ordinary_read_source1=1;ordinary_read_valid=1;#1;if(!ordinary_read_response_valid||ordinary_read_address_fault||ordinary_read_uninitialized)$fatal(1,"ordinary read pair failed");if(ordinary_read_data0!==pat(32'h1000)||ordinary_read_data1!==pat(32'h2000))$fatal(1,"ordinary read data mismatch");ordinary_read_valid=0;
  ordinary_read_source0=0;ordinary_read_source1=8;ordinary_read_valid=1;#1;if(ordinary_read_response_valid)$fatal(1,"same-bank split completed in one service");@(posedge clk);#1;@(negedge clk);#1;if(!ordinary_read_response_valid||ordinary_read_data0!==pat(32'h1000)||ordinary_read_data1!==pat(32'h8000))$fatal(1,"same-bank split read failed");@(posedge clk);#1;if(dut.split_pending)$fatal(1,"same-bank split did not retire after response acceptance");@(negedge clk);ordinary_read_valid=0;
  ordinary_write_wave_slot=0;ordinary_write_destination=2;ordinary_write_lane_mask=32'hffffffff;ordinary_write_data=pat(32'h3000);ordinary_write_valid=1;#1;if(!ordinary_write_ready||ordinary_write_address_fault)$fatal(1,"ordinary write failed");@(posedge clk);#1;@(negedge clk);ordinary_write_valid=0;
  ordinary_read_source0=2;ordinary_read_source1=2;ordinary_read_valid=1;#1;if(!ordinary_read_response_valid||ordinary_read_data0!==pat(32'h3000)||ordinary_read_data1!==pat(32'h3000))$fatal(1,"ordinary write/readback failed");
  release_wave_slot=0;release_quiescent=1;release_valid=1;#1;if(release_ready||release_accepted)$fatal(1,"release was accepted during visible ordinary RF activity");release_valid=0;release_quiescent=0;ordinary_read_valid=0;
  ordinary_write_destination=20;ordinary_write_valid=1;#1;if(!ordinary_write_address_fault||!ordinary_write_ready)$fatal(1,"invalid destination did not terminate as address fault");ordinary_write_valid=0;
  $display("[pass] CGX 1 unified pooled execution subsystem checks passed.");$finish;
 end
endmodule
