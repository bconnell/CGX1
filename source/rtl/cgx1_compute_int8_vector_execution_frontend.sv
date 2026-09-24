// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Candidate mixed resident-wave execution boundary: signed INT8 matrix + INT32 vector over one pooled VGPR subsystem.
module cgx1_compute_int8_vector_execution_frontend #(
 parameter integer PHYSICAL_ROWS=128,
 parameter integer RESIDENT_WAVE_SLOTS=16,
 parameter integer ROW_WIDTH=(PHYSICAL_ROWS<=1)?1:$clog2(PHYSICAL_ROWS),
 parameter integer WAVE_SLOT_WIDTH=(RESIDENT_WAVE_SLOTS<=1)?1:$clog2(RESIDENT_WAVE_SLOTS),
 parameter integer MATRIX_BURST_LIMIT=4
)(
 input logic clk, reset_n,
 input logic reserve_valid, input logic[WAVE_SLOT_WIDTH-1:0]reserve_wave_slot, input logic[8:0]reserve_register_count, output logic reserve_ready,reserve_accepted,
 input logic activate_valid, input logic[WAVE_SLOT_WIDTH-1:0]activate_wave_slot, output logic activate_ready,activate_accepted,
 input logic release_valid, input logic[WAVE_SLOT_WIDTH-1:0]release_wave_slot, input logic release_quiescent, output logic release_ready,release_accepted,
 input logic restore_valid, input logic[WAVE_SLOT_WIDTH-1:0]restore_wave_slot, input logic[7:0]restore_register, input logic[1023:0]restore_data, output logic restore_ready,
 input logic[RESIDENT_WAVE_SLOTS-1:0]matrix_request_valid,matrix_request_full_wave_active,
 input logic[(RESIDENT_WAVE_SLOTS*8)-1:0]matrix_request_d_base,matrix_request_a_base,matrix_request_b_base,
 output logic[RESIDENT_WAVE_SLOTS-1:0]matrix_request_ready,matrix_request_accepted,
 output logic matrix_illegal_issue, output logic[WAVE_SLOT_WIDTH-1:0]matrix_illegal_wave_slot,
 input logic[RESIDENT_WAVE_SLOTS-1:0]vector_request_valid,
 input logic[(RESIDENT_WAVE_SLOTS*4)-1:0]vector_request_opcode,
 input logic[(RESIDENT_WAVE_SLOTS*8)-1:0]vector_request_source0,vector_request_source1,vector_request_destination,
 input logic[(RESIDENT_WAVE_SLOTS*32)-1:0]vector_request_lane_mask,
 output logic[RESIDENT_WAVE_SLOTS-1:0]vector_request_accepted,
 output logic vector_complete_valid, output logic[WAVE_SLOT_WIDTH-1:0]vector_complete_wave_slot,
 output logic vector_illegal_opcode,vector_address_fault,vector_uninitialized_fault,
 output logic[RESIDENT_WAVE_SLOTS-1:0]matrix_resident_wave_busy,
 output logic vector_busy
);
 logic[RESIDENT_WAVE_SLOTS-1:0]preflight_ready,preflight_gated;
 logic[(RESIDENT_WAVE_SLOTS*256)-1:0]matrix_source_pending_flat,matrix_destination_pending_flat;
 logic[RESIDENT_WAVE_SLOTS-1:0]vector_dependency_ready,vector_dep_raw,vector_dep_waw,vector_dep_war;
 logic[RESIDENT_WAVE_SLOTS-1:0]layout_legal,matrix_vector_ready,engine_matrix_valid,engine_matrix_ready;
 logic[RESIDENT_WAVE_SLOTS-1:0]matrix_raw,matrix_waw,matrix_war;
 genvar w;
 generate for(w=0;w<RESIDENT_WAVE_SLOTS;w=w+1) begin:layout
   cgx1_matrix_vgpr_allocation_guard guard(.allocation_active(1'b1),.allocation_register_count(9'd256),.destination_base(matrix_request_d_base[(w*8)+:8]),.source_a_base(matrix_request_a_base[(w*8)+:8]),.source_b_base(matrix_request_b_base[(w*8)+:8]),.layout_legal(layout_legal[w]),.allocation_range_legal(),.matrix_vgpr_legal());
 end endgenerate

 logic vec_selected_valid; logic[WAVE_SLOT_WIDTH-1:0]vec_selected_wave; logic[3:0]vec_selected_opcode;logic[7:0]vec_selected_s0,vec_selected_s1,vec_selected_d;logic[31:0]vec_selected_mask;logic vec_selected_ready;
 cgx1_resident_vector_matrix_dependency_frontend #(.RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),.WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)) vsched(
  .clk(clk),.reset_n(reset_n),.request_valid(vector_request_valid),.request_opcode(vector_request_opcode),.request_source0(vector_request_source0),.request_source1(vector_request_source1),.request_destination(vector_request_destination),.request_lane_mask(vector_request_lane_mask),
  .matrix_source_pending_flat(matrix_source_pending_flat),.matrix_destination_pending_flat(matrix_destination_pending_flat),
  .dependency_ready(vector_dependency_ready),.raw_hazard(vector_dep_raw),.waw_hazard(vector_dep_waw),.war_hazard(vector_dep_war),
  .request_accepted(vector_request_accepted),.selected_valid(vec_selected_valid),.selected_wave_slot(vec_selected_wave),.selected_opcode(vec_selected_opcode),.selected_source0(vec_selected_s0),.selected_source1(vec_selected_s1),.selected_destination(vec_selected_d),.selected_lane_mask(vec_selected_mask),.selected_ready(vec_selected_ready));

 logic vec_source_locks,vec_dest_lock;logic[WAVE_SLOT_WIDTH-1:0]vec_live_wave;logic[7:0]vec_live_s0,vec_live_s1,vec_live_d;
 cgx1_matrix_vector_hazard_array #(.RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),.WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)) xhaz(.matrix_layout_legal(layout_legal),.matrix_d_base(matrix_request_d_base),.matrix_a_base(matrix_request_a_base),.matrix_b_base(matrix_request_b_base),.vector_busy(vector_busy),.vector_wave_slot(vec_live_wave),.vector_source_locks_live(vec_source_locks),.vector_destination_lock_live(vec_dest_lock),.vector_source0(vec_live_s0),.vector_source1(vec_live_s1),.vector_destination(vec_live_d),.matrix_runtime_ready(matrix_vector_ready),.matrix_raw_hazard(matrix_raw),.matrix_waw_hazard(matrix_waw),.matrix_war_hazard(matrix_war));

 integer mi;
 always_comb begin
   engine_matrix_valid='0;matrix_request_ready='0;
   for(mi=0;mi<RESIDENT_WAVE_SLOTS;mi=mi+1) begin
     engine_matrix_valid[mi]=matrix_request_valid[mi] && (!matrix_request_full_wave_active[mi] || !layout_legal[mi] || (allow_legal_matrix_issue&&preflight_ready[mi]&&matrix_vector_ready[mi]));
     matrix_request_ready[mi]=engine_matrix_ready[mi] && (!matrix_request_full_wave_active[mi] || !layout_legal[mi] || (allow_legal_matrix_issue&&preflight_ready[mi]&&matrix_vector_ready[mi]));
   end
 end

 logic mrf_read_valid,mrf_write_valid;logic[7:0]mrf_addr0,mrf_addr1,mrf_waddr;logic[WAVE_SLOT_WIDTH-1:0]mrf_read_wave,mrf_write_wave;logic[1023:0]mrf_data0,mrf_data1,mrf_wdata;logic mrf_read_ready,mrf_write_ready,mrf_init0,mrf_init1;
 logic matrix_ordinary_raw,matrix_ordinary_waw,matrix_ordinary_war,matrix_ordinary_rpc,matrix_ordinary_wpc,matrix_ordinary_ready,matrix_ordinary_accepted;
 logic[255:0]vec_read_mask,vec_write_mask;logic any_matrix_accepted,matrix_fire_now,vector_issue_to_matrix_scoreboard;
 logic legal_matrix_accepted,allow_legal_matrix_issue,service_window_active;
 logic restore_service_waiting,restore_service_accepted;
 integer accepted_scan;
 always_comb begin
   vec_read_mask='0;vec_write_mask='0;
   if(vec_selected_valid) begin vec_read_mask[vec_selected_s0]=1'b1;vec_read_mask[vec_selected_s1]=1'b1;vec_write_mask[vec_selected_d]=1'b1;end
   any_matrix_accepted=|matrix_request_accepted;
   matrix_fire_now=|(engine_matrix_valid & engine_matrix_ready);
   legal_matrix_accepted=1'b0;
   for(accepted_scan=0;accepted_scan<RESIDENT_WAVE_SLOTS;accepted_scan=accepted_scan+1)
     if(matrix_request_accepted[accepted_scan]&&matrix_request_full_wave_active[accepted_scan]&&layout_legal[accepted_scan])
       legal_matrix_accepted=1'b1;
   vector_issue_to_matrix_scoreboard=vec_selected_valid&&!matrix_fire_now;
 end

 cgx1_compute_mixed_service_policy #(.MATRIX_BURST_LIMIT(MATRIX_BURST_LIMIT)) service_policy(
  .clk(clk),.reset_n(reset_n),.legal_matrix_accepted(legal_matrix_accepted),
  .vector_waiting(vec_selected_valid),.vector_accepted(vector_issue_accepted),
  .restore_waiting(restore_service_waiting),.restore_accepted(restore_service_accepted),
  .allow_legal_matrix_issue(allow_legal_matrix_issue),.service_window_active(service_window_active));

 cgx1_matrix_int8_resident_engine #(.RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),.WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)) matrix_engine(
  .clk(clk),.reset_n(reset_n),.matrix_request_valid(engine_matrix_valid),.matrix_request_full_wave_active(matrix_request_full_wave_active),.matrix_request_d_base(matrix_request_d_base),.matrix_request_a_base(matrix_request_a_base),.matrix_request_b_base(matrix_request_b_base),.matrix_request_ready(engine_matrix_ready),.matrix_request_accepted(matrix_request_accepted),.illegal_issue(matrix_illegal_issue),.illegal_wave_slot(matrix_illegal_wave_slot),.rf_read_valid(mrf_read_valid),.rf_read_addr0(mrf_addr0),.rf_read_addr1(mrf_addr1),.rf_read_wave_slot(mrf_read_wave),.rf_read_data0(mrf_data0),.rf_read_data1(mrf_data1),.rf_write_valid(mrf_write_valid),.rf_write_addr(mrf_waddr),.rf_write_wave_slot(mrf_write_wave),.rf_write_data(mrf_wdata),.ordinary_issue_valid(vector_issue_to_matrix_scoreboard),.ordinary_wave_slot(vec_selected_wave),.ordinary_read_mask(vec_read_mask),.ordinary_write_mask(vec_write_mask),.ordinary_uses_read_ports(1'b1),.ordinary_uses_write_port(1'b1),.ordinary_raw_hazard(matrix_ordinary_raw),.ordinary_waw_hazard(matrix_ordinary_waw),.ordinary_war_hazard(matrix_ordinary_war),.ordinary_read_port_conflict(matrix_ordinary_rpc),.ordinary_write_port_conflict(matrix_ordinary_wpc),.ordinary_ready(matrix_ordinary_ready),.ordinary_issue_accepted(matrix_ordinary_accepted),.matrix_source_pending_mask_flat(matrix_source_pending_flat),.matrix_destination_pending_mask_flat(matrix_destination_pending_flat),.resident_wave_busy(matrix_resident_wave_busy));

 logic vread_valid,vwrite_valid;logic[WAVE_SLOT_WIDTH-1:0]vread_wave,vwrite_wave;logic[7:0]vread_s0,vread_s1,vwrite_d;logic[31:0]vwrite_mask;logic[1023:0]vread_d0,vread_d1,vwrite_data;logic vread_response,vread_af,vread_uninit,vwrite_ready,vwrite_af,vector_issue_ready,vector_issue_accepted;
 assign vec_selected_ready=vector_issue_ready&&matrix_ordinary_ready&&!matrix_fire_now;
 cgx1_vector_int32_pipeline #(.WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)) vector_pipe(.clk(clk),.reset_n(reset_n),.issue_valid(vec_selected_valid&&matrix_ordinary_ready&&!matrix_fire_now),.issue_wave_slot(vec_selected_wave),.issue_opcode(vec_selected_opcode),.issue_source0(vec_selected_s0),.issue_source1(vec_selected_s1),.issue_destination(vec_selected_d),.issue_lane_mask(vec_selected_mask),.issue_ready(vector_issue_ready),.issue_accepted(vector_issue_accepted),.read_valid(vread_valid),.read_wave_slot(vread_wave),.read_source0(vread_s0),.read_source1(vread_s1),.read_response_valid(vread_response),.read_address_fault(vread_af),.read_uninitialized(vread_uninit),.read_data0(vread_d0),.read_data1(vread_d1),.write_valid(vwrite_valid),.write_wave_slot(vwrite_wave),.write_destination(vwrite_d),.write_lane_mask(vwrite_mask),.write_data(vwrite_data),.write_ready(vwrite_ready),.write_address_fault(vwrite_af),.complete_valid(vector_complete_valid),.complete_wave_slot(vector_complete_wave_slot),.illegal_opcode(vector_illegal_opcode),.address_fault(vector_address_fault),.uninitialized_fault(vector_uninitialized_fault),.busy(vector_busy),.live_wave_slot(vec_live_wave),.live_source0(vec_live_s0),.live_source1(vec_live_s1),.live_destination(vec_live_d),.source_locks_live(vec_source_locks),.destination_lock_live(vec_dest_lock));

 logic[RESIDENT_WAVE_SLOTS-1:0]vector_busy_bitmap;
 always_comb begin vector_busy_bitmap='0;if(vector_busy&&($unsigned(vec_live_wave)<RESIDENT_WAVE_SLOTS))vector_busy_bitmap[vec_live_wave]=1'b1;end
 cgx1_pooled_vgpr_execution_subsystem #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),.ROW_WIDTH(ROW_WIDTH),.WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)) pooled(
  .clk(clk),.reset_n(reset_n),.reserve_valid(reserve_valid),.reserve_wave_slot(reserve_wave_slot),.reserve_register_count(reserve_register_count),.reserve_ready(reserve_ready),.reserve_accepted(reserve_accepted),.activate_valid(activate_valid),.activate_wave_slot(activate_wave_slot),.activate_ready(activate_ready),.activate_accepted(activate_accepted),.release_valid(release_valid),.release_wave_slot(release_wave_slot),.release_quiescent(release_quiescent),.release_ready(release_ready),.release_accepted(release_accepted),.matrix_execution_busy(matrix_resident_wave_busy),.vector_execution_busy(vector_busy_bitmap),.restore_valid(restore_valid),.restore_wave_slot(restore_wave_slot),.restore_register(restore_register),.restore_data(restore_data),.restore_ready(restore_ready),.matrix_request_valid(matrix_request_valid),.matrix_request_d_base(matrix_request_d_base),.matrix_request_a_base(matrix_request_a_base),.matrix_request_b_base(matrix_request_b_base),.matrix_request_preflight_ready(preflight_ready),.matrix_request_gated_valid(preflight_gated),.matrix_rf_read_valid(mrf_read_valid),.matrix_rf_read_wave_slot(mrf_read_wave),.matrix_rf_read_addr0(mrf_addr0),.matrix_rf_read_addr1(mrf_addr1),.matrix_rf_read_ready(mrf_read_ready),.matrix_rf_read0_initialized(mrf_init0),.matrix_rf_read_data0(mrf_data0),.matrix_rf_read1_initialized(mrf_init1),.matrix_rf_read_data1(mrf_data1),.matrix_rf_write_valid(mrf_write_valid),.matrix_rf_write_wave_slot(mrf_write_wave),.matrix_rf_write_addr(mrf_waddr),.matrix_rf_write_data(mrf_wdata),.matrix_rf_write_ready(mrf_write_ready),.ordinary_read_valid(vread_valid),.ordinary_read_wave_slot(vread_wave),.ordinary_read_source0(vread_s0),.ordinary_read_source1(vread_s1),.ordinary_read_response_valid(vread_response),.ordinary_read_address_fault(vread_af),.ordinary_read_uninitialized(vread_uninit),.ordinary_read_data0(vread_d0),.ordinary_read_data1(vread_d1),.ordinary_write_valid(vwrite_valid),.ordinary_write_wave_slot(vwrite_wave),.ordinary_write_destination(vwrite_d),.ordinary_write_lane_mask(vwrite_mask),.ordinary_write_data(vwrite_data),.ordinary_write_ready(vwrite_ready),.ordinary_write_address_fault(vwrite_af),
  .restore_service_waiting(restore_service_waiting),.restore_service_accepted(restore_service_accepted));
`ifndef SYNTHESIS
 always_ff @(posedge clk) begin
  if(reset_n && matrix_fire_now && vector_issue_accepted) $fatal(1,"matrix and vector instructions were accepted on the same issue edge");
 end
`endif
endmodule
