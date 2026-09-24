// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Candidate unified pooled VGPR subsystem for matrix, ordinary-vector, and privileged restore traffic.
module cgx1_pooled_vgpr_execution_subsystem #(
 parameter integer PHYSICAL_ROWS=128,
 parameter integer RESIDENT_WAVE_SLOTS=16,
 parameter integer ROW_WIDTH=(PHYSICAL_ROWS<=1)?1:$clog2(PHYSICAL_ROWS),
 parameter integer WAVE_SLOT_WIDTH=(RESIDENT_WAVE_SLOTS<=1)?1:$clog2(RESIDENT_WAVE_SLOTS)
)(
 input logic clk, reset_n,
 input logic reserve_valid, input logic [WAVE_SLOT_WIDTH-1:0] reserve_wave_slot, input logic [8:0] reserve_register_count, output logic reserve_ready,reserve_accepted,
 input logic activate_valid, input logic [WAVE_SLOT_WIDTH-1:0] activate_wave_slot, output logic activate_ready,activate_accepted,
 input logic release_valid, input logic [WAVE_SLOT_WIDTH-1:0] release_wave_slot, input logic release_quiescent, output logic release_ready,release_accepted,
 input logic [RESIDENT_WAVE_SLOTS-1:0] matrix_execution_busy, vector_execution_busy,
 input logic restore_valid, input logic [WAVE_SLOT_WIDTH-1:0] restore_wave_slot, input logic [7:0] restore_register, input logic [1023:0] restore_data, output logic restore_ready,
 input logic [RESIDENT_WAVE_SLOTS-1:0] matrix_request_valid,
 input logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_d_base,matrix_request_a_base,matrix_request_b_base,
 output logic [RESIDENT_WAVE_SLOTS-1:0] matrix_request_preflight_ready,matrix_request_gated_valid,
 input logic matrix_rf_read_valid, input logic [WAVE_SLOT_WIDTH-1:0] matrix_rf_read_wave_slot, input logic [7:0] matrix_rf_read_addr0,matrix_rf_read_addr1,
 output logic matrix_rf_read_ready,matrix_rf_read0_initialized,matrix_rf_read1_initialized, output logic [1023:0] matrix_rf_read_data0,matrix_rf_read_data1,
 input logic matrix_rf_write_valid, input logic [WAVE_SLOT_WIDTH-1:0] matrix_rf_write_wave_slot, input logic [7:0] matrix_rf_write_addr, input logic [1023:0] matrix_rf_write_data, output logic matrix_rf_write_ready,
 input logic ordinary_read_valid, input logic [WAVE_SLOT_WIDTH-1:0] ordinary_read_wave_slot, input logic [7:0] ordinary_read_source0,ordinary_read_source1,
 output logic ordinary_read_response_valid,ordinary_read_address_fault,ordinary_read_uninitialized, output logic [1023:0] ordinary_read_data0,ordinary_read_data1,
 input logic ordinary_write_valid, input logic [WAVE_SLOT_WIDTH-1:0] ordinary_write_wave_slot, input logic [7:0] ordinary_write_destination, input logic [31:0] ordinary_write_lane_mask, input logic [1023:0] ordinary_write_data,
 output logic ordinary_write_ready, ordinary_write_address_fault,
 output logic restore_service_waiting, restore_service_accepted
);
 logic invalidate_valid,invalidate_ready; logic [ROW_WIDTH-1:0] invalidate_row;
 logic [RESIDENT_WAVE_SLOTS-1:0] alloc_reserved,alloc_active,alloc_sanitized;
 logic [(RESIDENT_WAVE_SLOTS*ROW_WIDTH)-1:0] alloc_base_flat; logic [(RESIDENT_WAVE_SLOTS*9)-1:0] alloc_count_flat;
 logic [WAVE_SLOT_WIDTH-1:0] query_slot; logic qres,qact,qsan; logic [ROW_WIDTH-1:0] qbase; logic [ROW_WIDTH:0] qrows; logic [8:0] qcount;
 assign query_slot='0;
 logic release_slot_valid,restore_same_wave,matrix_rf_same_wave,ordinary_rf_same_wave,split_same_wave;
 logic release_guard_safe, allocator_release_ready,allocator_release_accepted,allocator_activate_ready,allocator_activate_accepted;
 logic allocator_release_valid,allocator_activate_valid;
 logic [WAVE_SLOT_WIDTH-1:0] split_wave_slot; logic split_pending;

 cgx1_pooled_vgpr_release_guard release_guard(.external_quiescent(release_quiescent),
  .matrix_busy(release_slot_valid?matrix_execution_busy[release_wave_slot]:1'b0),
  .vector_busy(release_slot_valid?vector_execution_busy[release_wave_slot]:1'b0),
  .matrix_rf_active(matrix_rf_same_wave),.vector_rf_active(ordinary_rf_same_wave),.split_read_pending(split_same_wave),.restore_same_wave(restore_same_wave),.release_safe(release_guard_safe));

 always_comb begin
  release_slot_valid=$unsigned(release_wave_slot)<RESIDENT_WAVE_SLOTS;
  restore_same_wave=release_slot_valid&&restore_valid&&($unsigned(restore_wave_slot)<RESIDENT_WAVE_SLOTS)&&(restore_wave_slot==release_wave_slot);
  matrix_rf_same_wave=release_slot_valid&&((matrix_rf_read_valid&&matrix_rf_read_wave_slot==release_wave_slot)||(matrix_rf_write_valid&&matrix_rf_write_wave_slot==release_wave_slot));
  ordinary_rf_same_wave=release_slot_valid&&((ordinary_read_valid&&ordinary_read_wave_slot==release_wave_slot)||(ordinary_write_valid&&ordinary_write_wave_slot==release_wave_slot));
  split_same_wave=release_slot_valid&&split_pending&&(split_wave_slot==release_wave_slot);
  allocator_release_valid=release_valid&&!restore_same_wave;
  release_ready=allocator_release_valid&&allocator_release_ready; release_accepted=allocator_release_accepted;
  allocator_activate_valid=activate_valid&&!(restore_valid&&restore_wave_slot==activate_wave_slot);
  activate_ready=allocator_activate_valid&&allocator_activate_ready; activate_accepted=allocator_activate_accepted;
 end

 cgx1_resident_wave_vgpr_allocator #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),.ROW_WIDTH(ROW_WIDTH),.WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)) allocator(
  .clk(clk),.reset_n(reset_n),.reserve_valid(reserve_valid),.reserve_wave_slot(reserve_wave_slot),.reserve_register_count(reserve_register_count),.reserve_ready(reserve_ready),.reserve_accepted(reserve_accepted),
  .activate_valid(allocator_activate_valid),.activate_wave_slot(activate_wave_slot),.activate_ready(allocator_activate_ready),.activate_accepted(allocator_activate_accepted),
  .release_valid(allocator_release_valid),.release_wave_slot(release_wave_slot),.release_quiescent(release_guard_safe),.release_ready(allocator_release_ready),.release_accepted(allocator_release_accepted),
  .invalidate_valid(invalidate_valid),.invalidate_row(invalidate_row),.invalidate_ready(invalidate_ready),.query_wave_slot(query_slot),.query_reserved(qres),.query_active(qact),.query_sanitized(qsan),.query_row_base(qbase),.query_row_count(qrows),.query_register_count(qcount),
  .allocation_reserved_bitmap(alloc_reserved),.allocation_active_bitmap(alloc_active),.allocation_sanitized_bitmap(alloc_sanitized),.allocation_row_base_flat(alloc_base_flat),.allocation_register_count_flat(alloc_count_flat));

 logic [(PHYSICAL_ROWS*8)-1:0] valid_bitmap;
 logic [RESIDENT_WAVE_SLOTS-1:0] preflight_ready_raw,gated_raw;
 cgx1_matrix_request_preflight_array #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),.ROW_WIDTH(ROW_WIDTH)) preflight(
  .request_valid(matrix_request_valid),.allocation_active(alloc_active),.allocation_row_base(alloc_base_flat),.allocation_register_count(alloc_count_flat),.valid_bitmap(valid_bitmap),
  .destination_base(matrix_request_d_base),.source_a_base(matrix_request_a_base),.source_b_base(matrix_request_b_base),.request_layout_legal(),.request_allocation_legal(),.request_initialized(),.request_preflight_ready(preflight_ready_raw),.gated_request_valid(gated_raw));
 always_comb begin matrix_request_preflight_ready=preflight_ready_raw; matrix_request_gated_valid=gated_raw; if(release_valid&&release_slot_valid) begin matrix_request_preflight_ready[release_wave_slot]=0; matrix_request_gated_valid[release_wave_slot]=0; end end

 function automatic logic slot_valid(input logic [WAVE_SLOT_WIDTH-1:0] slot); slot_valid=($unsigned(slot)<RESIDENT_WAVE_SLOTS); endfunction

 logic restore_slot_valid_sel,restore_reserved_sel,restore_sanitized_sel;
 logic matrix_read_slot_valid_sel,matrix_read_active_sel,matrix_write_slot_valid_sel,matrix_write_active_sel;
 logic ordinary_read_slot_valid_sel,ordinary_read_active_sel,ordinary_write_slot_valid_sel,ordinary_write_active_sel;
 logic [ROW_WIDTH-1:0] restore_base_sel,matrix_read_base_sel,matrix_write_base_sel,ordinary_read_base_sel,ordinary_write_base_sel;
 logic [8:0] restore_count_sel,matrix_read_count_sel,matrix_write_count_sel,ordinary_read_count_sel,ordinary_write_count_sel;

 always_comb begin
  restore_slot_valid_sel=slot_valid(restore_wave_slot);
  matrix_read_slot_valid_sel=slot_valid(matrix_rf_read_wave_slot);
  matrix_write_slot_valid_sel=slot_valid(matrix_rf_write_wave_slot);
  ordinary_read_slot_valid_sel=slot_valid(ordinary_read_wave_slot);
  ordinary_write_slot_valid_sel=slot_valid(ordinary_write_wave_slot);

  restore_reserved_sel=1'b0; restore_sanitized_sel=1'b0; restore_base_sel='0; restore_count_sel='0;
  matrix_read_active_sel=1'b0; matrix_read_base_sel='0; matrix_read_count_sel='0;
  matrix_write_active_sel=1'b0; matrix_write_base_sel='0; matrix_write_count_sel='0;
  ordinary_read_active_sel=1'b0; ordinary_read_base_sel='0; ordinary_read_count_sel='0;
  ordinary_write_active_sel=1'b0; ordinary_write_base_sel='0; ordinary_write_count_sel='0;

  if(restore_slot_valid_sel) begin
   restore_reserved_sel=alloc_reserved[restore_wave_slot];
   restore_sanitized_sel=alloc_sanitized[restore_wave_slot];
   restore_base_sel=alloc_base_flat[($unsigned(restore_wave_slot)*ROW_WIDTH)+:ROW_WIDTH];
   restore_count_sel=alloc_count_flat[($unsigned(restore_wave_slot)*9)+:9];
  end
  if(matrix_read_slot_valid_sel) begin
   matrix_read_active_sel=alloc_active[matrix_rf_read_wave_slot];
   matrix_read_base_sel=alloc_base_flat[($unsigned(matrix_rf_read_wave_slot)*ROW_WIDTH)+:ROW_WIDTH];
   matrix_read_count_sel=alloc_count_flat[($unsigned(matrix_rf_read_wave_slot)*9)+:9];
  end
  if(matrix_write_slot_valid_sel) begin
   matrix_write_active_sel=alloc_active[matrix_rf_write_wave_slot];
   matrix_write_base_sel=alloc_base_flat[($unsigned(matrix_rf_write_wave_slot)*ROW_WIDTH)+:ROW_WIDTH];
   matrix_write_count_sel=alloc_count_flat[($unsigned(matrix_rf_write_wave_slot)*9)+:9];
  end
  if(ordinary_read_slot_valid_sel) begin
   ordinary_read_active_sel=alloc_active[ordinary_read_wave_slot];
   ordinary_read_base_sel=alloc_base_flat[($unsigned(ordinary_read_wave_slot)*ROW_WIDTH)+:ROW_WIDTH];
   ordinary_read_count_sel=alloc_count_flat[($unsigned(ordinary_read_wave_slot)*9)+:9];
  end
  if(ordinary_write_slot_valid_sel) begin
   ordinary_write_active_sel=alloc_active[ordinary_write_wave_slot];
   ordinary_write_base_sel=alloc_base_flat[($unsigned(ordinary_write_wave_slot)*ROW_WIDTH)+:ROW_WIDTH];
   ordinary_write_count_sel=alloc_count_flat[($unsigned(ordinary_write_wave_slot)*9)+:9];
  end
 end

 logic restore_map_valid; logic [ROW_WIDTH-1:0] restore_row; logic [2:0] restore_bank;
 cgx1_pooled_vgpr_restore_mapper #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) restore_mapper(.allocation_reserved(restore_reserved_sel),.allocation_sanitized(restore_sanitized_sel),.allocation_row_base(restore_base_sel),.allocation_register_count(restore_count_sel),.architectural_register(restore_register),.restore_address_valid(restore_map_valid),.physical_row(restore_row),.bank_class(restore_bank));

 logic m0v,m1v,mwv; logic [ROW_WIDTH-1:0] m0r,m1r,mwr; logic [2:0] m0b,m1b,mwb;
 cgx1_pooled_vgpr_mapper #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) mm0(.allocation_active(matrix_read_active_sel),.allocation_row_base(matrix_read_base_sel),.allocation_register_count(matrix_read_count_sel),.architectural_register(matrix_rf_read_addr0),.address_valid(m0v),.physical_row(m0r),.bank_class(m0b));
 cgx1_pooled_vgpr_mapper #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) mm1(.allocation_active(matrix_read_active_sel),.allocation_row_base(matrix_read_base_sel),.allocation_register_count(matrix_read_count_sel),.architectural_register(matrix_rf_read_addr1),.address_valid(m1v),.physical_row(m1r),.bank_class(m1b));
 cgx1_pooled_vgpr_mapper #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) mmw(.allocation_active(matrix_write_active_sel),.allocation_row_base(matrix_write_base_sel),.allocation_register_count(matrix_write_count_sel),.architectural_register(matrix_rf_write_addr),.address_valid(mwv),.physical_row(mwr),.bank_class(mwb));

 logic os0v,os1v,odv; logic [ROW_WIDTH-1:0] os0r,os1r,odr; logic [2:0] os0b,os1b,odb; logic oalias,osame;
 cgx1_pooled_vgpr_ordinary_frontend #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) ofront(.allocation_active(ordinary_read_active_sel),.allocation_row_base(ordinary_read_base_sel),.allocation_register_count(ordinary_read_count_sel),.source0(ordinary_read_source0),.source1(ordinary_read_source1),.destination(8'd0),.source0_valid(os0v),.source1_valid(os1v),.destination_valid(),.source0_row(os0r),.source1_row(os1r),.destination_row(),.source0_bank(os0b),.source1_bank(os1b),.destination_bank(),.exact_alias(oalias),.distinct_same_bank(osame));
 cgx1_pooled_vgpr_mapper #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) omw(.allocation_active(ordinary_write_active_sel),.allocation_row_base(ordinary_write_base_sel),.allocation_register_count(ordinary_write_count_sel),.architectural_register(ordinary_write_destination),.address_valid(odv),.physical_row(odr),.bank_class(odb));

 logic ord_service_valid,ord_service_single,ord_service_ready; logic [ROW_WIDTH-1:0] ord_sr0,ord_sr1; logic [2:0] ord_sb0,ord_sb1;
 logic storage_r0_init,storage_r1_init; logic [1023:0] storage_r0_data,storage_r1_data;
 cgx1_pooled_vgpr_ordinary_read_sequencer #(.ROW_WIDTH(ROW_WIDTH),.WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)) oseq(
  .clk(clk),.reset_n(reset_n),.request_valid(ordinary_read_valid),.request_wave_slot(ordinary_read_wave_slot),.request_source0(ordinary_read_source0),.request_source1(ordinary_read_source1),
  .source0_row(os0r),.source1_row(os1r),.source0_bank(os0b),.source1_bank(os1b),.source0_valid(os0v),.source1_valid(os1v),.exact_alias(oalias),.distinct_same_bank(osame),
  .service_valid(ord_service_valid),.service_row0(ord_sr0),.service_row1(ord_sr1),.service_bank0(ord_sb0),.service_bank1(ord_sb1),.service_single(ord_service_single),.service_ready(ord_service_ready),
  .service0_initialized(storage_r0_init),.service1_initialized(storage_r1_init),.service0_data(storage_r0_data),.service1_data(storage_r1_data),
  .response_valid(ordinary_read_response_valid),.response_address_fault(ordinary_read_address_fault),.response_uninitialized(ordinary_read_uninitialized),.response0_data(ordinary_read_data0),.response1_data(ordinary_read_data1),.split_pending(split_pending),.split_wave_slot(split_wave_slot));

 logic gmr,gmw,gor,gow,gr; logic transfer_accepted;
 logic ordinary_write_eligible,restore_eligible;
 assign ordinary_write_eligible=ordinary_write_valid&&odv;
 assign ordinary_write_address_fault=ordinary_write_valid&&!odv;
 assign restore_eligible=restore_valid&&restore_map_valid&&!(release_accepted&&restore_wave_slot==release_wave_slot);
 cgx1_pooled_vgpr_shared_port_arbiter arb(.clk(clk),.reset_n(reset_n),.matrix_read_valid(matrix_rf_read_valid&&m0v&&m1v),.matrix_write_valid(matrix_rf_write_valid&&mwv),.ordinary_read_eligible(ord_service_valid),.ordinary_write_eligible(ordinary_write_eligible),.restore_eligible(restore_eligible),.grant_matrix_read(gmr),.grant_matrix_write(gmw),.grant_ordinary_read(gor),.grant_ordinary_write(gow),.grant_restore(gr),.transfer_accepted(transfer_accepted));

 logic storage_read_valid,storage_write_valid,storage_read_ready,storage_write_ready,storage_conflict; logic [ROW_WIDTH-1:0] sr0,sr1,swrow; logic [2:0] sb0,sb1,swbank; logic [31:0] swmask; logic [1023:0] swdata;
 always_comb begin
  storage_read_valid=gmr||gor; sr0=gmr?m0r:ord_sr0; sr1=gmr?m1r:ord_sr1; sb0=gmr?m0b:ord_sb0; sb1=gmr?m1b:ord_sb1;
  storage_write_valid=gmw||gow||gr; swrow='0; swbank='0; swmask='0; swdata='0;
  if(gmw) begin swrow=mwr; swbank=mwb; swmask=32'hffffffff; swdata=matrix_rf_write_data; end
  else if(gow) begin swrow=odr; swbank=odb; swmask=ordinary_write_lane_mask; swdata=ordinary_write_data; end
  else if(gr) begin swrow=restore_row; swbank=restore_bank; swmask=32'hffffffff; swdata=restore_data; end
  matrix_rf_read_ready=gmr&&storage_read_ready; matrix_rf_read0_initialized=gmr&&storage_r0_init; matrix_rf_read1_initialized=gmr&&storage_r1_init; matrix_rf_read_data0=storage_r0_data; matrix_rf_read_data1=storage_r1_data;
  matrix_rf_write_ready=gmw&&storage_write_ready; ord_service_ready=gor&&storage_read_ready; ordinary_write_ready=(ordinary_write_address_fault)||(gow&&storage_write_ready); restore_ready=gr&&storage_write_ready;
  restore_service_waiting=restore_eligible;
  restore_service_accepted=gr&&storage_write_ready;
  transfer_accepted=(gmr&&storage_read_ready)||(gmw&&storage_write_ready)||(gor&&storage_read_ready)||(gow&&storage_write_ready)||(gr&&storage_write_ready);
 end
 cgx1_pooled_vgpr_storage #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) storage(.clk(clk),.reset_n(reset_n),.invalidate_valid(invalidate_valid),.invalidate_row(invalidate_row),.invalidate_ready(invalidate_ready),.read_valid(storage_read_valid),.read0_row(sr0),.read0_bank(sb0),.read1_row(sr1),.read1_bank(sb1),.read_ready(storage_read_ready),.read_bank_conflict(storage_conflict),.read0_initialized(storage_r0_init),.read0_data(storage_r0_data),.read1_initialized(storage_r1_init),.read1_data(storage_r1_data),.write_valid(storage_write_valid),.write_row(swrow),.write_bank(swbank),.write_lane_mask(swmask),.write_data(swdata),.write_ready(storage_write_ready),.valid_bitmap(valid_bitmap));
`ifndef SYNTHESIS
 always_ff @(posedge clk) begin
  if(reset_n&&matrix_rf_read_valid&&!matrix_rf_read_ready) $fatal(1,"matrix fixed-cycle read was not serviceable");
  if(reset_n&&matrix_rf_write_valid&&!matrix_rf_write_ready) $fatal(1,"matrix fixed-cycle write was not serviceable");
  if(reset_n&&storage_conflict&&gmr) $fatal(1,"matrix read produced a bank conflict");
 end
`endif
endmodule
