// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Complete-workgroup admission and issue control composed with the actual pooled VGPR frontend.
module cgx1_compute_workgroup_execution_frontend #(
    parameter integer PHYSICAL_ROWS = 32,
    parameter integer RESIDENT_WAVE_SLOTS = 8,
    parameter integer MAX_WORKGROUP_CONTEXTS = 4,
    parameter integer SCALAR_PREDICATE_STATE_UNITS = 128,
    parameter integer SHARED_LOCAL_MEMORY_BYTES = 4096,
    parameter integer OTHER_WORKGROUP_STATE_UNITS = 128,
    parameter integer WORKGROUP_ID_WIDTH = 16,
    parameter integer ROW_WIDTH = (PHYSICAL_ROWS <= 1) ? 1 : $clog2(PHYSICAL_ROWS),
    parameter integer WAVE_SLOT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS),
    parameter integer WAVE_COUNT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS + 1),
    parameter integer MAX_MATRIX_BURST = 4
) (
    input logic clk,
    input logic reset_n,

    input logic dispatch_valid,
    output logic dispatch_ready,
    input logic [WORKGROUP_ID_WIDTH-1:0] dispatch_workgroup_id,
    input logic [WAVE_COUNT_WIDTH-1:0] dispatch_wave_count,
    input logic [(RESIDENT_WAVE_SLOTS*9)-1:0] dispatch_vgpr_register_counts_flat,
    input logic [15:0] dispatch_scalar_state_units_per_wave,
    input logic [31:0] dispatch_shared_local_bytes,
    input logic [15:0] dispatch_other_workgroup_state_units,
    output logic dispatch_result_valid,
    output logic dispatch_accepted,
    output logic [4:0] dispatch_failure,

    input logic barrier_arrive_valid,
    input logic [WORKGROUP_ID_WIDTH-1:0] barrier_arrive_workgroup_id,
    input logic [RESIDENT_WAVE_SLOTS-1:0] barrier_arrive_local_wave_mask,
    output logic barrier_arrive_ready,
    output logic barrier_arrive_accepted,
    output logic barrier_release_valid,
    output logic [WORKGROUP_ID_WIDTH-1:0] barrier_release_workgroup_id,
    output logic [31:0] barrier_release_generation,
    output logic [RESIDENT_WAVE_SLOTS-1:0] barrier_release_wave_mask,

    input logic terminate_wave_valid,
    input logic [WAVE_SLOT_WIDTH-1:0] terminate_wave_slot,
    input logic [1:0] terminate_wave_reason,
    output logic terminate_wave_ready,
    output logic terminate_wave_accepted,
    input logic workgroup_abort_valid,
    input logic [WORKGROUP_ID_WIDTH-1:0] workgroup_abort_id,
    output logic workgroup_abort_ready,
    output logic workgroup_abort_accepted,

    input logic restore_valid,
    input logic [WAVE_SLOT_WIDTH-1:0] restore_wave_slot,
    input logic [7:0] restore_register,
    input logic [1023:0] restore_data,
    output logic restore_ready,
    input logic [RESIDENT_WAVE_SLOTS-1:0] matrix_request_valid,
    input logic [RESIDENT_WAVE_SLOTS-1:0] matrix_request_full_wave_active,
    input logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_d_base,
    input logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_a_base,
    input logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_b_base,
    output logic [RESIDENT_WAVE_SLOTS-1:0] matrix_request_ready,
    output logic [RESIDENT_WAVE_SLOTS-1:0] matrix_request_accepted,
    output logic matrix_illegal_issue,
    output logic [WAVE_SLOT_WIDTH-1:0] matrix_illegal_wave_slot,
    input logic [RESIDENT_WAVE_SLOTS-1:0] vector_request_valid,
    input logic [(RESIDENT_WAVE_SLOTS*4)-1:0] vector_request_opcode,
    input logic [(RESIDENT_WAVE_SLOTS*8)-1:0] vector_request_source0,
    input logic [(RESIDENT_WAVE_SLOTS*8)-1:0] vector_request_source1,
    input logic [(RESIDENT_WAVE_SLOTS*8)-1:0] vector_request_destination,
    input logic [(RESIDENT_WAVE_SLOTS*32)-1:0] vector_request_lane_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] vector_request_accepted,
    output logic vector_complete_valid,
    output logic [WAVE_SLOT_WIDTH-1:0] vector_complete_wave_slot,
    output logic vector_illegal_opcode,
    output logic vector_address_fault,
    output logic vector_uninitialized_fault,

    input logic [31:0] memory_epoch,
    input logic [RESIDENT_WAVE_SLOTS-1:0] memory_issue_valid,
    output logic [RESIDENT_WAVE_SLOTS-1:0] memory_issue_ready,
    output logic [RESIDENT_WAVE_SLOTS-1:0] memory_issue_accepted,
    input logic [RESIDENT_WAVE_SLOTS-1:0] memory_issue_global,
    input logic [RESIDENT_WAVE_SLOTS-1:0] memory_issue_write,
    input logic [(RESIDENT_WAVE_SLOTS*8)-1:0] memory_issue_destination_flat,
    input logic [(RESIDENT_WAVE_SLOTS*32)-1:0] memory_issue_lane_mask_flat,
    input logic [(RESIDENT_WAVE_SLOTS*1024)-1:0] memory_issue_byte_addresses_flat,
    input logic [(RESIDENT_WAVE_SLOTS*1024)-1:0] memory_issue_store_data_flat,
    output logic [RESIDENT_WAVE_SLOTS-1:0] memory_waiting_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] memory_load_destination_pending_mask,
    input logic memory_completion_ready,
    output logic memory_completion_valid,
    output logic [WORKGROUP_ID_WIDTH-1:0] memory_completion_workgroup_id,
    output logic [WAVE_SLOT_WIDTH-1:0] memory_completion_wave_slot,
    output logic [63:0] memory_completion_transaction_tag,
    output logic memory_completion_write,
    input logic memory_fault_ready,
    output logic memory_fault_valid,
    output logic [WORKGROUP_ID_WIDTH-1:0] memory_fault_workgroup_id,
    output logic [WAVE_SLOT_WIDTH-1:0] memory_fault_wave_slot,
    output logic [63:0] memory_fault_transaction_tag,
    output logic [2:0] memory_fault_code,
    output logic [5:0] memory_fault_lane,

    output logic memory_global_request_valid,
    input logic memory_global_request_ready,
    output logic [WORKGROUP_ID_WIDTH-1:0] memory_global_request_workgroup_id,
    output logic [WAVE_SLOT_WIDTH-1:0] memory_global_request_wave_slot,
    output logic [31:0] memory_global_request_epoch,
    output logic [63:0] memory_global_request_transaction_tag,
    output logic memory_global_request_write,
    output logic [31:0] memory_global_request_lane_mask,
    output logic [1023:0] memory_global_request_byte_addresses_flat,
    output logic [1023:0] memory_global_request_store_data_flat,
    input logic memory_global_response_valid,
    output logic memory_global_response_ready,
    input logic [WORKGROUP_ID_WIDTH-1:0] memory_global_response_workgroup_id,
    input logic [WAVE_SLOT_WIDTH-1:0] memory_global_response_wave_slot,
    input logic [31:0] memory_global_response_epoch,
    input logic [63:0] memory_global_response_transaction_tag,
    input logic memory_global_response_write,
    input logic [31:0] memory_global_response_lane_mask,
    input logic [1023:0] memory_global_response_lane_data_flat,
    input logic [2:0] memory_global_response_fault_code,
    input logic [5:0] memory_global_response_fault_lane,

    output logic [RESIDENT_WAVE_SLOTS-1:0] allocation_reserved_bitmap,
    output logic [RESIDENT_WAVE_SLOTS-1:0] allocation_active_bitmap,
    output logic [RESIDENT_WAVE_SLOTS-1:0] allocation_sanitized_bitmap,
    output logic [(RESIDENT_WAVE_SLOTS*ROW_WIDTH)-1:0] allocation_row_base_flat,
    output logic [(RESIDENT_WAVE_SLOTS*9)-1:0] allocation_register_count_flat,
    output logic [RESIDENT_WAVE_SLOTS-1:0] matrix_execution_busy_bitmap,
    output logic [RESIDENT_WAVE_SLOTS-1:0] vector_execution_busy_bitmap,
    output logic [RESIDENT_WAVE_SLOTS-1:0] resident_wave_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] live_wave_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] barrier_waiting_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] issuable_wave_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] release_pending_wave_mask,
    output logic [MAX_WORKGROUP_CONTEXTS-1:0] workgroup_active_mask,
    output logic [WAVE_COUNT_WIDTH-1:0] resident_wave_count,
    output logic [31:0] scalar_state_units_used,
    output logic [31:0] shared_local_bytes_used,
    output logic [31:0] other_workgroup_state_units_used
);
    localparam logic [4:0] FAIL_INVALID_WAVE_COUNT = 5'd1;
    localparam logic [4:0] FAIL_WORKGROUP_WAVE_LIMIT = 5'd2;
    localparam logic [4:0] FAIL_DUPLICATE_WORKGROUP = 5'd3;
    localparam logic [4:0] FAIL_BARRIER_CONTEXTS = 5'd4;
    localparam logic [4:0] FAIL_INVALID_VGPR_DEMAND = 5'd5;
    localparam logic [4:0] FAIL_VGPR_EXCEEDS_CU = 5'd6;
    localparam logic [4:0] FAIL_WAVE_SLOTS_BUSY = 5'd7;
    localparam logic [4:0] FAIL_VGPR_ROWS_BUSY = 5'd8;
    localparam logic [4:0] FAIL_VGPR_FRAGMENTED = 5'd9;
    localparam logic [4:0] FAIL_SCALAR_STATE_EXCEEDS_CU = 5'd10;
    localparam logic [4:0] FAIL_SCALAR_STATE_BUSY = 5'd11;
    localparam logic [4:0] FAIL_SHARED_MEMORY_EXCEEDS_CU = 5'd12;
    localparam logic [4:0] FAIL_SHARED_MEMORY_BUSY = 5'd13;
    localparam logic [4:0] FAIL_OTHER_STATE_EXCEEDS_CU = 5'd14;
    localparam logic [4:0] FAIL_OTHER_STATE_BUSY = 5'd15;
    localparam logic [4:0] FAIL_SHARED_MEMORY_FRAGMENTED = 5'd16;
    localparam logic [4:0] FAIL_SHARED_MEMORY_ALLOCATION_FAILED = 5'd17;

    localparam logic [2:0] ST_IDLE = 3'd0;
    localparam logic [2:0] ST_RESERVE = 3'd1;
    localparam logic [2:0] ST_WAIT_SANITIZE = 3'd2;
    localparam logic [2:0] ST_ACTIVATE = 3'd3;
    localparam logic [2:0] ST_COMMIT = 3'd4;
    localparam logic [2:0] ST_ROLLBACK = 3'd5;
    localparam logic [2:0] ST_ALLOCATE_SHARED = 3'd6;
    localparam logic [2:0] ST_RELEASE_SHARED_ROLLBACK = 3'd7;

    logic [2:0] txn_state_q;
    logic [4:0] txn_failure_q;
    logic [WAVE_COUNT_WIDTH-1:0] txn_wave_count_q;
    logic [(RESIDENT_WAVE_SLOTS*9)-1:0] txn_register_counts_flat_q;
    logic [(RESIDENT_WAVE_SLOTS*WAVE_SLOT_WIDTH)-1:0] txn_wave_slot_map_flat_q;
    logic [WORKGROUP_ID_WIDTH-1:0] txn_workgroup_id_q;
    logic [15:0] txn_scalar_units_q;
    logic [31:0] txn_shared_bytes_q;
    logic [15:0] txn_other_units_q;
    integer txn_wave_index_q;
    integer txn_reserved_count_q;
    integer rollback_index_q;

    logic [4:0] plan_failure;
    logic [(RESIDENT_WAVE_SLOTS*WAVE_SLOT_WIDTH)-1:0] planned_slots_flat;
    logic [RESIDENT_WAVE_SLOTS-1:0] allocator_in_use;
    logic [RESIDENT_WAVE_SLOTS-1:0] scheduler_issue_mask;
    logic [RESIDENT_WAVE_SLOTS-1:0] matrix_exec_request_valid;
    logic [RESIDENT_WAVE_SLOTS-1:0] vector_exec_request_valid;
    logic [RESIDENT_WAVE_SLOTS-1:0] lsu_issue_valid;
    logic [RESIDENT_WAVE_SLOTS-1:0] lsu_issue_ready;
    logic [RESIDENT_WAVE_SLOTS-1:0] lsu_issue_accepted;
    logic [RESIDENT_WAVE_SLOTS-1:0] memory_issue_slot_available;
    logic [RESIDENT_WAVE_SLOTS-1:0] lsu_busy_mask;
    logic [(RESIDENT_WAVE_SLOTS*256)-1:0] memory_destination_pending_mask_flat;
    logic [RESIDENT_WAVE_SLOTS-1:0] busy_bitmap;
    logic [RESIDENT_WAVE_SLOTS-1:0] vector_execution_busy_bitmap_raw;
    logic [RESIDENT_WAVE_SLOTS-1:0] allocator_release_done_mask;
    logic [WORKGROUP_ID_WIDTH-1:0] query_workgroup_id;
    logic query_workgroup_found;
    logic [WAVE_COUNT_WIDTH-1:0] query_workgroup_wave_count;
    logic [RESIDENT_WAVE_SLOTS-1:0] query_workgroup_live_waves;
    logic [RESIDENT_WAVE_SLOTS-1:0] query_workgroup_arrived_waves;
    logic [31:0] query_barrier_generation;
    logic commit_ready, commit_accepted;
    logic [RESIDENT_WAVE_SLOTS-1:0] barrier_resident_mask;
    logic [RESIDENT_WAVE_SLOTS-1:0] barrier_live_mask;
    logic [RESIDENT_WAVE_SLOTS-1:0] barrier_issuable_mask;
    logic [RESIDENT_WAVE_SLOTS-1:0] lsu_fault_block_mask;
    logic [RESIDENT_WAVE_SLOTS-1:0] barrier_release_pending_mask;
    logic [WAVE_COUNT_WIDTH-1:0] barrier_resident_count;
    logic [MAX_WORKGROUP_CONTEXTS-1:0] barrier_active_mask;
    logic [RESIDENT_WAVE_SLOTS-1:0] barrier_final_wave_release_mask;
    logic [(RESIDENT_WAVE_SLOTS*WORKGROUP_ID_WIDTH)-1:0] barrier_slot_workgroup_id_flat;
    logic [31:0] barrier_scalar_used, barrier_shared_used, barrier_other_used;
    logic reserve_valid, reserve_ready, reserve_accepted;
    logic [WAVE_SLOT_WIDTH-1:0] reserve_wave_slot;
    logic [8:0] reserve_register_count;
    logic activate_valid, activate_ready, activate_accepted;
    logic [WAVE_SLOT_WIDTH-1:0] activate_wave_slot;
    logic release_valid, release_ready, release_accepted;
    logic [WAVE_SLOT_WIDTH-1:0] release_wave_slot;
    logic release_quiescent;
    logic allocator_release_valid;
    logic shared_memory_allocation_valid, shared_memory_allocation_ready;
    logic shared_memory_allocation_result_valid, shared_memory_allocation_accepted;
    logic [2:0] shared_memory_allocation_failure;
    logic [WORKGROUP_ID_WIDTH-1:0] shared_memory_allocation_workgroup_id;
    logic [31:0] shared_memory_allocation_byte_count;
    logic shared_memory_release_valid, shared_memory_release_ready;
    logic shared_memory_release_accepted;
    logic [WORKGROUP_ID_WIDTH-1:0] shared_memory_release_workgroup_id;
    logic [31:0] shared_memory_allocated_bytes;
    logic [(1 << WAVE_SLOT_WIDTH)-1:0] shared_memory_outstanding_wave_bitmap;
    logic local_memory_request_valid, local_memory_request_ready, local_memory_request_accepted;
    logic [WORKGROUP_ID_WIDTH-1:0] local_memory_request_workgroup_id;
    logic [WAVE_SLOT_WIDTH-1:0] local_memory_request_wave_id;
    logic [63:0] local_memory_request_transaction_tag;
    logic local_memory_request_write;
    logic [31:0] local_memory_request_lane_mask;
    logic [1023:0] local_memory_request_byte_addresses_flat, local_memory_request_store_data_flat;
    logic local_memory_response_valid, local_memory_response_ready;
    logic [WORKGROUP_ID_WIDTH-1:0] local_memory_response_workgroup_id;
    logic [WAVE_SLOT_WIDTH-1:0] local_memory_response_wave_id;
    logic [63:0] local_memory_response_transaction_tag;
    logic local_memory_response_write;
    logic [31:0] local_memory_response_lane_mask;
    logic [1023:0] local_memory_response_lane_data_flat;
    logic [1:0] local_memory_response_fault_code;
    logic [5:0] local_memory_response_fault_lane;
    logic local_memory_cancel_valid, local_memory_cancel_ready, local_memory_cancel_accepted;
    logic [WORKGROUP_ID_WIDTH-1:0] local_memory_cancel_workgroup_id;
    logic [WAVE_SLOT_WIDTH-1:0] local_memory_cancel_wave_id;
    logic lsu_writeback_valid, lsu_writeback_ready, lsu_writeback_address_fault;
    logic [WORKGROUP_ID_WIDTH-1:0] lsu_writeback_workgroup_id;
    logic [WAVE_SLOT_WIDTH-1:0] lsu_writeback_wave_slot;
    logic [63:0] lsu_writeback_transaction_tag;
    logic [7:0] lsu_writeback_destination;
    logic [31:0] lsu_writeback_lane_mask;
    logic [1023:0] lsu_writeback_lane_data_flat;
    logic memory_vgpr_write_ready;
    logic [(RESIDENT_WAVE_SLOTS*8)-1:0] lsu_load_destination_register_flat;
    logic lsu_fault_valid, lsu_fault_ready;
    logic [WORKGROUP_ID_WIDTH-1:0] lsu_fault_workgroup_id;
    logic [WAVE_SLOT_WIDTH-1:0] lsu_fault_wave_slot;
    logic [63:0] lsu_fault_transaction_tag;
    logic [2:0] lsu_fault_code;
    logic [5:0] lsu_fault_lane;
    logic barrier_terminate_valid, barrier_terminate_ready, barrier_terminate_accepted;
    logic [WAVE_SLOT_WIDTH-1:0] barrier_terminate_slot;
    logic [1:0] barrier_terminate_reason;
    logic memory_fault_to_barrier;
    logic shared_memory_owned_q;
    logic shared_memory_allocation_submitted_q;
    logic [RESIDENT_WAVE_SLOTS-1:0] matrix_busy_raw;
    logic vector_busy_raw;
    logic selected_release_is_final_wave;
    integer release_candidate;
    integer active_contexts;
    integer free_slots;
    integer free_rows;
    integer rows_used;
    integer requested_rows;
    integer requested_scalar;
    integer used_scalar;
    integer used_shared;
    integer used_other;
    integer plan_slot [0:RESIDENT_WAVE_SLOTS-1];
    integer comb_wave;
    integer comb_slot;
    integer comb_count;
    integer memory_pending_slot;

    always_comb begin : admission_plan
        integer row_count;
        integer scalar_demand;
        logic [63:0] shared_demand;
        integer other_demand;
        logic slot_found;
        allocator_in_use = allocation_reserved_bitmap | allocation_active_bitmap;
        planned_slots_flat = '0;
        plan_failure = 5'd0;
        active_contexts = 0;
        free_slots = 0;
        free_rows = PHYSICAL_ROWS;
        rows_used = 0;
        requested_rows = 0;
        requested_scalar = 0;
        used_scalar = barrier_scalar_used;
        used_shared = shared_local_bytes_used;
        used_other = barrier_other_used;
        scalar_demand = $unsigned(dispatch_scalar_state_units_per_wave)
            * $unsigned(dispatch_wave_count);
        shared_demand = {32'b0, dispatch_shared_local_bytes};
        other_demand = $unsigned(dispatch_other_workgroup_state_units);
        for (comb_wave = 0; comb_wave < RESIDENT_WAVE_SLOTS; comb_wave = comb_wave + 1)
            plan_slot[comb_wave] = -1;
        for (comb_slot = 0; comb_slot < RESIDENT_WAVE_SLOTS; comb_slot = comb_slot + 1) begin
            if (!allocator_in_use[comb_slot])
                free_slots = free_slots + 1;
            else begin
                row_count = ($unsigned(allocation_register_count_flat[(comb_slot*9)+:9]) + 7) / 8;
                rows_used = rows_used + row_count;
            end
        end
        free_rows = PHYSICAL_ROWS - rows_used;
        for (comb_slot = 0; comb_slot < MAX_WORKGROUP_CONTEXTS; comb_slot = comb_slot + 1)
            active_contexts = active_contexts + barrier_active_mask[comb_slot];

        for (comb_wave = 0; comb_wave < RESIDENT_WAVE_SLOTS; comb_wave = comb_wave + 1) begin
            if (comb_wave < $unsigned(dispatch_wave_count)) begin
                comb_count = $unsigned(dispatch_vgpr_register_counts_flat[(comb_wave*9)+:9]);
                if ((comb_count < 1) || (comb_count > 256))
                    plan_failure = FAIL_INVALID_VGPR_DEMAND;
                requested_rows = requested_rows + ((comb_count + 7) / 8);
            end
        end
        requested_scalar = scalar_demand;

        if (dispatch_wave_count == 0)
            plan_failure = FAIL_INVALID_WAVE_COUNT;
        else if ($unsigned(dispatch_wave_count) > RESIDENT_WAVE_SLOTS)
            plan_failure = FAIL_WORKGROUP_WAVE_LIMIT;
        else if (plan_failure == FAIL_INVALID_VGPR_DEMAND)
            plan_failure = FAIL_INVALID_VGPR_DEMAND;
        else if (query_workgroup_found)
            plan_failure = FAIL_DUPLICATE_WORKGROUP;
        else if (active_contexts >= MAX_WORKGROUP_CONTEXTS)
            plan_failure = FAIL_BARRIER_CONTEXTS;
        else if (requested_rows > PHYSICAL_ROWS)
            plan_failure = FAIL_VGPR_EXCEEDS_CU;
        else if (scalar_demand > SCALAR_PREDICATE_STATE_UNITS)
            plan_failure = FAIL_SCALAR_STATE_EXCEEDS_CU;
        else if (shared_demand > SHARED_LOCAL_MEMORY_BYTES)
            plan_failure = FAIL_SHARED_MEMORY_EXCEEDS_CU;
        else if (other_demand > OTHER_WORKGROUP_STATE_UNITS)
            plan_failure = FAIL_OTHER_STATE_EXCEEDS_CU;
        else if (free_slots < $unsigned(dispatch_wave_count))
            plan_failure = FAIL_WAVE_SLOTS_BUSY;
        else if (free_rows < requested_rows)
            plan_failure = FAIL_VGPR_ROWS_BUSY;
        else if ((used_scalar + scalar_demand) > SCALAR_PREDICATE_STATE_UNITS)
            plan_failure = FAIL_SCALAR_STATE_BUSY;
        else if ((used_shared + shared_demand) > SHARED_LOCAL_MEMORY_BYTES)
            plan_failure = FAIL_SHARED_MEMORY_BUSY;
        else if ((used_other + other_demand) > OTHER_WORKGROUP_STATE_UNITS)
            plan_failure = FAIL_OTHER_STATE_BUSY;

        if (plan_failure == 0) begin
            comb_wave = 0;
            for (comb_slot = 0; comb_slot < RESIDENT_WAVE_SLOTS; comb_slot = comb_slot + 1) begin
                if (!allocator_in_use[comb_slot] && (comb_wave < $unsigned(dispatch_wave_count))) begin
                    plan_slot[comb_wave] = comb_slot;
                    planned_slots_flat[(comb_wave*WAVE_SLOT_WIDTH)+:WAVE_SLOT_WIDTH]
                        = comb_slot[WAVE_SLOT_WIDTH-1:0];
                    comb_wave = comb_wave + 1;
                end
            end
            slot_found = (comb_wave == $unsigned(dispatch_wave_count));
            if (!slot_found)
                plan_failure = FAIL_WAVE_SLOTS_BUSY;
        end
    end

    always_comb begin : transaction_outputs
        logic [WAVE_SLOT_WIDTH-1:0] txn_slot;
        reserve_valid = (txn_state_q == ST_RESERVE);
        reserve_wave_slot = txn_wave_slot_map_flat_q[(txn_wave_index_q*WAVE_SLOT_WIDTH)+:WAVE_SLOT_WIDTH];
        reserve_register_count = txn_register_counts_flat_q[(txn_wave_index_q*9)+:9];
        activate_valid = (txn_state_q == ST_ACTIVATE);
        activate_wave_slot = reserve_wave_slot;
        release_valid = 1'b0;
        allocator_release_valid = 1'b0;
        release_wave_slot = '0;
        release_quiescent = 1'b1;
        release_candidate = -1;
        selected_release_is_final_wave = 1'b0;
        shared_memory_release_valid = 1'b0;
        shared_memory_release_workgroup_id = '0;
        if (txn_state_q == ST_ROLLBACK) begin
            release_valid = 1'b1;
            allocator_release_valid = 1'b1;
            release_wave_slot = txn_wave_slot_map_flat_q[(rollback_index_q*WAVE_SLOT_WIDTH)+:WAVE_SLOT_WIDTH];
        end else if (txn_state_q == ST_RELEASE_SHARED_ROLLBACK) begin
            shared_memory_release_valid = shared_memory_owned_q;
            shared_memory_release_workgroup_id = txn_workgroup_id_q;
        end else if ((txn_state_q == ST_IDLE) || (txn_state_q == ST_RESERVE)
            || (txn_state_q == ST_WAIT_SANITIZE) || (txn_state_q == ST_ACTIVATE)
            || (txn_state_q == ST_COMMIT) || (txn_state_q == ST_ALLOCATE_SHARED)) begin
            for (integer scan_slot = RESIDENT_WAVE_SLOTS-1; scan_slot >= 0; scan_slot = scan_slot - 1) begin
                if (barrier_release_pending_mask[scan_slot] && !(busy_bitmap[scan_slot]))
                    release_candidate = scan_slot;
            end
            if (release_candidate >= 0) begin
                release_valid = 1'b1;
                release_wave_slot = release_candidate[WAVE_SLOT_WIDTH-1:0];
                selected_release_is_final_wave =
                    barrier_final_wave_release_mask[release_candidate];
                if (selected_release_is_final_wave) begin
                    shared_memory_release_valid = release_ready;
                    shared_memory_release_workgroup_id =
                        barrier_slot_workgroup_id_flat[(release_candidate*WORKGROUP_ID_WIDTH)
                            +: WORKGROUP_ID_WIDTH];
                    allocator_release_valid = shared_memory_release_ready;
                end else begin
                    allocator_release_valid = 1'b1;
                end
            end
        end
        txn_slot = reserve_wave_slot;
    end

    assign dispatch_ready = (txn_state_q == ST_IDLE);
    assign query_workgroup_id = dispatch_workgroup_id;
    assign busy_bitmap = matrix_busy_raw | vector_execution_busy_bitmap_raw | lsu_busy_mask;
    assign matrix_execution_busy_bitmap = matrix_busy_raw;
    assign vector_execution_busy_bitmap = vector_execution_busy_bitmap_raw | lsu_busy_mask;
    assign resident_wave_mask = barrier_resident_mask & allocation_active_bitmap;
    assign live_wave_mask = barrier_live_mask & allocation_active_bitmap;
    assign barrier_waiting_mask = barrier_waiting_mask_raw & allocation_active_bitmap;
    assign issuable_wave_mask = barrier_issuable_mask & allocation_active_bitmap
        & ~lsu_fault_block_mask;
    assign release_pending_wave_mask = barrier_release_pending_mask;
    assign workgroup_active_mask = barrier_active_mask;
    assign resident_wave_count = barrier_resident_count;
    assign scalar_state_units_used = barrier_scalar_used;
    assign shared_local_bytes_used = shared_memory_allocated_bytes;
    assign other_workgroup_state_units_used = barrier_other_used;
    assign matrix_exec_request_valid = matrix_request_valid & issuable_wave_mask & ~lsu_busy_mask;
    assign vector_exec_request_valid = vector_request_valid & issuable_wave_mask;
    // Preserve same-wave program order: an already-presented matrix/vector
    // request and any live execution finish before the LSU captures its next op.
    assign memory_issue_slot_available = issuable_wave_mask
        & ~matrix_busy_raw & ~vector_execution_busy_bitmap_raw
        & ~matrix_request_valid & ~vector_request_valid;
    assign lsu_issue_valid = memory_issue_valid & memory_issue_slot_available;
    assign memory_issue_ready = lsu_issue_ready & memory_issue_slot_available;
    assign memory_issue_accepted = lsu_issue_accepted;

    assign barrier_terminate_valid = terminate_wave_valid
        || (lsu_fault_valid && memory_fault_ready);
    assign barrier_terminate_slot = terminate_wave_valid ? terminate_wave_slot : lsu_fault_wave_slot;
    assign barrier_terminate_reason = terminate_wave_valid ? terminate_wave_reason : 2'b10;
    assign terminate_wave_ready = barrier_terminate_ready && !memory_fault_to_barrier;
    assign terminate_wave_accepted = terminate_wave_valid && terminate_wave_ready;
    assign memory_fault_to_barrier = !terminate_wave_valid && lsu_fault_valid && memory_fault_ready;
    assign lsu_fault_ready = !terminate_wave_valid && memory_fault_ready && barrier_terminate_ready;
    assign memory_fault_valid = lsu_fault_valid;
    assign memory_fault_workgroup_id = lsu_fault_workgroup_id;
    assign memory_fault_wave_slot = lsu_fault_wave_slot;
    assign memory_fault_transaction_tag = lsu_fault_transaction_tag;
    assign memory_fault_code = lsu_fault_code;
    assign memory_fault_lane = lsu_fault_lane;

    always_comb begin : memory_destination_scoreboard
        memory_destination_pending_mask_flat = '0;
        for (memory_pending_slot = 0; memory_pending_slot < RESIDENT_WAVE_SLOTS;
            memory_pending_slot = memory_pending_slot + 1) begin
            if (memory_load_destination_pending_mask[memory_pending_slot])
                memory_destination_pending_mask_flat[(memory_pending_slot*256)
                    + $unsigned(lsu_load_destination_register_flat[(memory_pending_slot*8)+:8])] = 1'b1;
        end
    end

    logic [RESIDENT_WAVE_SLOTS-1:0] barrier_waiting_mask_raw;
    logic [RESIDENT_WAVE_SLOTS-1:0] release_done_mask;
    logic [RESIDENT_WAVE_SLOTS-1:0] commit_slot_mask_unused;
    logic [RESIDENT_WAVE_SLOTS-1:0] group_release_pending_unused;

    assign shared_memory_allocation_valid =
        (txn_state_q == ST_ALLOCATE_SHARED)
        && !shared_memory_allocation_submitted_q;
    assign shared_memory_allocation_workgroup_id = txn_workgroup_id_q;
    assign shared_memory_allocation_byte_count = txn_shared_bytes_q;

    cgx1_cu_shared_local_memory #(
        .CU_SHARED_BYTES(SHARED_LOCAL_MEMORY_BYTES),
        .MAX_WORKGROUP_CONTEXTS(MAX_WORKGROUP_CONTEXTS),
        .MAX_OUTSTANDING_TRANSACTIONS(RESIDENT_WAVE_SLOTS),
        .WORKGROUP_ID_WIDTH(WORKGROUP_ID_WIDTH),
        .WAVE_ID_WIDTH(WAVE_SLOT_WIDTH),
        .TRANSACTION_TAG_WIDTH(64)
    ) shared_local_memory (
        .clk(clk), .reset_n(reset_n),
        .allocation_valid(shared_memory_allocation_valid),
        .allocation_ready(shared_memory_allocation_ready),
        .allocation_workgroup_id(shared_memory_allocation_workgroup_id),
        .allocation_byte_count(shared_memory_allocation_byte_count),
        .allocation_result_valid(shared_memory_allocation_result_valid),
        .allocation_accepted(shared_memory_allocation_accepted),
        .allocation_failure(shared_memory_allocation_failure),
        .allocation_base_byte_address(),
        .release_valid(shared_memory_release_valid),
        .release_workgroup_id(shared_memory_release_workgroup_id),
        .release_ready(shared_memory_release_ready),
        .release_accepted(shared_memory_release_accepted),
        .request_valid(local_memory_request_valid),
        .request_workgroup_id(local_memory_request_workgroup_id),
        .request_wave_id(local_memory_request_wave_id),
        .request_transaction_tag(local_memory_request_transaction_tag),
        .request_write(local_memory_request_write), .request_lane_mask(local_memory_request_lane_mask),
        .request_byte_addresses_flat(local_memory_request_byte_addresses_flat),
        .request_store_data_flat(local_memory_request_store_data_flat),
        .request_ready(local_memory_request_ready), .request_accepted(local_memory_request_accepted),
        .response_valid(local_memory_response_valid), .response_ready(local_memory_response_ready),
        .response_workgroup_id(local_memory_response_workgroup_id),
        .response_wave_id(local_memory_response_wave_id),
        .response_transaction_tag(local_memory_response_transaction_tag),
        .response_write(local_memory_response_write), .response_lane_mask(local_memory_response_lane_mask),
        .response_lane_data_flat(local_memory_response_lane_data_flat),
        .response_fault_code(local_memory_response_fault_code),
        .response_fault_lane(local_memory_response_fault_lane),
        .cancel_valid(local_memory_cancel_valid), .cancel_workgroup_id(local_memory_cancel_workgroup_id),
        .cancel_wave_id(local_memory_cancel_wave_id), .cancel_ready(local_memory_cancel_ready),
        .cancel_accepted(local_memory_cancel_accepted),
        .allocated_bytes_used(shared_memory_allocated_bytes),
        .outstanding_transaction_bitmap(),
        .outstanding_wave_bitmap(shared_memory_outstanding_wave_bitmap)
    );

    cgx1_compute_workgroup_lsu #(
        .RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),
        .WORKGROUP_ID_WIDTH(WORKGROUP_ID_WIDTH),
        .WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH),
        .TRANSACTION_TAG_WIDTH(64),
        .MEMORY_EPOCH_WIDTH(32)
    ) lsu (
        .clk(clk), .reset_n(reset_n), .memory_epoch(memory_epoch),
        .wave_live_mask(live_wave_mask),
        .wave_workgroup_id_flat(barrier_slot_workgroup_id_flat),
        .issue_valid(lsu_issue_valid), .issue_ready(lsu_issue_ready),
        .issue_accepted(lsu_issue_accepted), .issue_global(memory_issue_global),
        .issue_write(memory_issue_write), .issue_destination_flat(memory_issue_destination_flat),
        .issue_lane_mask_flat(memory_issue_lane_mask_flat),
        .issue_byte_addresses_flat(memory_issue_byte_addresses_flat),
        .issue_store_data_flat(memory_issue_store_data_flat),
        .memory_waiting_mask(memory_waiting_mask), .busy_mask(lsu_busy_mask),
        .fault_pending_mask(lsu_fault_block_mask),
        .load_destination_pending_mask(memory_load_destination_pending_mask),
        .load_destination_register_flat(lsu_load_destination_register_flat),
        .local_request_valid(local_memory_request_valid),
        .local_request_ready(local_memory_request_ready),
        .local_request_accepted(local_memory_request_accepted),
        .local_request_workgroup_id(local_memory_request_workgroup_id),
        .local_request_wave_id(local_memory_request_wave_id),
        .local_request_transaction_tag(local_memory_request_transaction_tag),
        .local_request_write(local_memory_request_write),
        .local_request_lane_mask(local_memory_request_lane_mask),
        .local_request_byte_addresses_flat(local_memory_request_byte_addresses_flat),
        .local_request_store_data_flat(local_memory_request_store_data_flat),
        .local_response_valid(local_memory_response_valid),
        .local_response_ready(local_memory_response_ready),
        .local_response_workgroup_id(local_memory_response_workgroup_id),
        .local_response_wave_id(local_memory_response_wave_id),
        .local_response_transaction_tag(local_memory_response_transaction_tag),
        .local_response_write(local_memory_response_write),
        .local_response_lane_mask(local_memory_response_lane_mask),
        .local_response_lane_data_flat(local_memory_response_lane_data_flat),
        .local_response_fault_code(local_memory_response_fault_code),
        .local_response_fault_lane(local_memory_response_fault_lane),
        .local_cancel_valid(local_memory_cancel_valid),
        .local_cancel_workgroup_id(local_memory_cancel_workgroup_id),
        .local_cancel_wave_id(local_memory_cancel_wave_id),
        .local_cancel_ready(local_memory_cancel_ready),
        .local_cancel_accepted(local_memory_cancel_accepted),
        .local_outstanding_wave_bitmap(shared_memory_outstanding_wave_bitmap),
        .global_request_valid(memory_global_request_valid),
        .global_request_ready(memory_global_request_ready),
        .global_request_workgroup_id(memory_global_request_workgroup_id),
        .global_request_wave_id(memory_global_request_wave_slot),
        .global_request_epoch(memory_global_request_epoch),
        .global_request_transaction_tag(memory_global_request_transaction_tag),
        .global_request_write(memory_global_request_write),
        .global_request_lane_mask(memory_global_request_lane_mask),
        .global_request_byte_addresses_flat(memory_global_request_byte_addresses_flat),
        .global_request_store_data_flat(memory_global_request_store_data_flat),
        .global_response_valid(memory_global_response_valid),
        .global_response_ready(memory_global_response_ready),
        .global_response_workgroup_id(memory_global_response_workgroup_id),
        .global_response_wave_id(memory_global_response_wave_slot),
        .global_response_epoch(memory_global_response_epoch),
        .global_response_transaction_tag(memory_global_response_transaction_tag),
        .global_response_write(memory_global_response_write),
        .global_response_lane_mask(memory_global_response_lane_mask),
        .global_response_lane_data_flat(memory_global_response_lane_data_flat),
        .global_response_fault_code(memory_global_response_fault_code),
        .global_response_fault_lane(memory_global_response_fault_lane),
        .writeback_valid(lsu_writeback_valid), .writeback_ready(memory_vgpr_write_ready),
        .writeback_address_fault(lsu_writeback_address_fault),
        .writeback_workgroup_id(lsu_writeback_workgroup_id),
        .writeback_wave_slot(lsu_writeback_wave_slot),
        .writeback_transaction_tag(lsu_writeback_transaction_tag),
        .writeback_destination(lsu_writeback_destination),
        .writeback_lane_mask(lsu_writeback_lane_mask),
        .writeback_lane_data_flat(lsu_writeback_lane_data_flat),
        .completion_valid(memory_completion_valid), .completion_ready(memory_completion_ready),
        .completion_workgroup_id(memory_completion_workgroup_id),
        .completion_wave_slot(memory_completion_wave_slot),
        .completion_transaction_tag(memory_completion_transaction_tag),
        .completion_write(memory_completion_write),
        .fault_valid(lsu_fault_valid), .fault_ready(lsu_fault_ready),
        .fault_workgroup_id(lsu_fault_workgroup_id), .fault_wave_slot(lsu_fault_wave_slot),
        .fault_transaction_tag(lsu_fault_transaction_tag), .fault_code(lsu_fault_code),
        .fault_lane(lsu_fault_lane)
    );

    assign memory_vgpr_write_ready = lsu_writeback_ready || lsu_writeback_address_fault;

    cgx1_workgroup_residency_barrier #(
        .RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),
        .MAX_WORKGROUP_CONTEXTS(MAX_WORKGROUP_CONTEXTS),
        .SCALAR_PREDICATE_STATE_UNITS(SCALAR_PREDICATE_STATE_UNITS),
        .SHARED_LOCAL_MEMORY_BYTES(SHARED_LOCAL_MEMORY_BYTES),
        .OTHER_WORKGROUP_STATE_UNITS(OTHER_WORKGROUP_STATE_UNITS),
        .WORKGROUP_ID_WIDTH(WORKGROUP_ID_WIDTH),
        .WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH),
        .LOCAL_WAVE_WIDTH(WAVE_SLOT_WIDTH),
        .WAVE_COUNT_WIDTH(WAVE_COUNT_WIDTH)
    ) barrier_state (
        .clk(clk), .reset_n(reset_n),
        .commit_valid(txn_state_q == ST_COMMIT),
        .commit_workgroup_id(txn_workgroup_id_q),
        .commit_wave_count(txn_wave_count_q),
        .commit_wave_slot_map_flat(txn_wave_slot_map_flat_q),
        .commit_scalar_state_units_per_wave(txn_scalar_units_q),
        .commit_shared_local_bytes(txn_shared_bytes_q),
        .commit_other_workgroup_state_units(txn_other_units_q),
        .commit_ready(commit_ready), .commit_accepted(commit_accepted),
        .barrier_arrive_valid(barrier_arrive_valid),
        .barrier_arrive_workgroup_id(barrier_arrive_workgroup_id),
        .barrier_arrive_local_wave_mask(barrier_arrive_local_wave_mask),
        .wave_execution_busy(busy_bitmap),
        .barrier_arrive_ready(barrier_arrive_ready),
        .barrier_arrive_accepted(barrier_arrive_accepted),
        .barrier_release_valid(barrier_release_valid),
        .barrier_release_workgroup_id(barrier_release_workgroup_id),
        .barrier_release_generation(barrier_release_generation),
        .barrier_release_wave_mask(barrier_release_wave_mask),
        .terminate_wave_valid(barrier_terminate_valid),
        .terminate_wave_slot(barrier_terminate_slot),
        .terminate_wave_reason(barrier_terminate_reason),
        .terminate_wave_ready(barrier_terminate_ready),
        .terminate_wave_accepted(barrier_terminate_accepted),
        .workgroup_abort_valid(workgroup_abort_valid),
        .workgroup_abort_id(workgroup_abort_id),
        .workgroup_abort_ready(workgroup_abort_ready),
        .workgroup_abort_accepted(workgroup_abort_accepted),
        .allocator_release_accepted_mask(release_done_mask),
        .query_workgroup_id(query_workgroup_id),
        .query_workgroup_found(query_workgroup_found), .query_workgroup_wave_count(),
        .query_workgroup_live_waves(), .query_workgroup_arrived_waves(),
        .query_barrier_generation(),
        .resident_wave_mask(barrier_resident_mask),
        .live_wave_mask(barrier_live_mask),
        .barrier_waiting_mask(barrier_waiting_mask_raw),
        .issuable_wave_mask(barrier_issuable_mask),
        .release_pending_wave_mask(barrier_release_pending_mask),
        .workgroup_active_mask(barrier_active_mask),
        .final_wave_release_mask(barrier_final_wave_release_mask),
        .slot_workgroup_id_flat(barrier_slot_workgroup_id_flat),
        .resident_wave_count(barrier_resident_count),
        .scalar_state_units_used(barrier_scalar_used),
        .shared_local_bytes_used(barrier_shared_used),
        .other_workgroup_state_units_used(barrier_other_used)
    );

    cgx1_compute_int8_vector_execution_frontend #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS),
        .RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),
        .ROW_WIDTH(ROW_WIDTH),
        .WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH),
        .MATRIX_BURST_LIMIT(MAX_MATRIX_BURST)
    ) execution_frontend (
        .clk(clk), .reset_n(reset_n),
        .reserve_valid(reserve_valid), .reserve_wave_slot(reserve_wave_slot),
        .reserve_register_count(reserve_register_count), .reserve_ready(reserve_ready),
        .reserve_accepted(reserve_accepted), .activate_valid(activate_valid),
        .activate_wave_slot(activate_wave_slot), .activate_ready(activate_ready),
        .activate_accepted(activate_accepted), .release_valid(allocator_release_valid),
        .release_wave_slot(release_wave_slot), .release_quiescent(release_quiescent),
        .release_ready(release_ready), .release_accepted(release_accepted),
        .restore_valid(restore_valid), .restore_wave_slot(restore_wave_slot),
        .restore_register(restore_register), .restore_data(restore_data), .restore_ready(restore_ready),
        .matrix_request_valid(matrix_exec_request_valid),
        .matrix_request_full_wave_active(matrix_request_full_wave_active),
        .matrix_request_d_base(matrix_request_d_base), .matrix_request_a_base(matrix_request_a_base),
        .matrix_request_b_base(matrix_request_b_base), .matrix_request_ready(matrix_request_ready),
        .matrix_request_accepted(matrix_request_accepted), .matrix_illegal_issue(matrix_illegal_issue),
        .matrix_illegal_wave_slot(matrix_illegal_wave_slot),
        .vector_request_valid(vector_exec_request_valid), .vector_request_opcode(vector_request_opcode),
        .vector_request_source0(vector_request_source0), .vector_request_source1(vector_request_source1),
        .vector_request_destination(vector_request_destination), .vector_request_lane_mask(vector_request_lane_mask),
        .memory_destination_pending_mask_flat(memory_destination_pending_mask_flat),
        .vector_request_accepted(vector_request_accepted), .vector_complete_valid(vector_complete_valid),
        .vector_complete_wave_slot(vector_complete_wave_slot), .vector_illegal_opcode(vector_illegal_opcode),
        .vector_address_fault(vector_address_fault), .vector_uninitialized_fault(vector_uninitialized_fault),
        .memory_write_valid(lsu_writeback_valid), .memory_write_wave_slot(lsu_writeback_wave_slot),
        .memory_write_destination(lsu_writeback_destination),
        .memory_write_lane_mask(lsu_writeback_lane_mask),
        .memory_write_data(lsu_writeback_lane_data_flat),
        .memory_write_ready(lsu_writeback_ready),
        .memory_write_address_fault(lsu_writeback_address_fault),
        .matrix_resident_wave_busy(matrix_busy_raw), .vector_busy(vector_busy_raw),
        .allocation_reserved_bitmap(allocation_reserved_bitmap),
        .allocation_active_bitmap(allocation_active_bitmap),
        .allocation_sanitized_bitmap(allocation_sanitized_bitmap),
        .allocation_row_base_flat(allocation_row_base_flat),
        .allocation_register_count_flat(allocation_register_count_flat),
        .vector_execution_busy_bitmap(vector_execution_busy_bitmap_raw)
    );

    integer seq_index;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            txn_state_q <= ST_IDLE;
            txn_failure_q <= '0;
            txn_wave_count_q <= '0;
            txn_register_counts_flat_q <= '0;
            txn_wave_slot_map_flat_q <= '0;
            txn_workgroup_id_q <= '0;
            txn_scalar_units_q <= '0;
            txn_shared_bytes_q <= '0;
            txn_other_units_q <= '0;
            txn_wave_index_q <= 0;
            txn_reserved_count_q <= 0;
            rollback_index_q <= 0;
            shared_memory_owned_q <= 1'b0;
            shared_memory_allocation_submitted_q <= 1'b0;
            dispatch_result_valid <= 1'b0;
            dispatch_accepted <= 1'b0;
            dispatch_failure <= '0;
        end else begin
            dispatch_result_valid <= 1'b0;
            dispatch_accepted <= 1'b0;
            dispatch_failure <= '0;
            if (shared_memory_allocation_valid && shared_memory_allocation_ready)
                shared_memory_allocation_submitted_q <= 1'b1;
            case (txn_state_q)
                ST_IDLE: begin
                    if (dispatch_valid && dispatch_ready) begin
                        if (plan_failure != 0) begin
                            dispatch_result_valid <= 1'b1;
                            dispatch_failure <= plan_failure;
                        end else begin
                            txn_workgroup_id_q <= dispatch_workgroup_id;
                            txn_wave_count_q <= dispatch_wave_count;
                            txn_register_counts_flat_q <= dispatch_vgpr_register_counts_flat;
                            txn_wave_slot_map_flat_q <= planned_slots_flat;
                            txn_scalar_units_q <= dispatch_scalar_state_units_per_wave;
                            txn_shared_bytes_q <= dispatch_shared_local_bytes;
                            txn_other_units_q <= dispatch_other_workgroup_state_units;
                            txn_wave_index_q <= 0;
                            txn_reserved_count_q <= 0;
                            txn_state_q <= ST_ALLOCATE_SHARED;
                        end
                    end
                end
                ST_ALLOCATE_SHARED: begin
                    if (shared_memory_allocation_result_valid) begin
                        shared_memory_allocation_submitted_q <= 1'b0;
                        if (shared_memory_allocation_accepted) begin
                            shared_memory_owned_q <= 1'b1;
                            txn_state_q <= ST_RESERVE;
                        end else begin
                            dispatch_result_valid <= 1'b1;
                            case (shared_memory_allocation_failure)
                                3'd1: dispatch_failure <= FAIL_SHARED_MEMORY_EXCEEDS_CU;
                                3'd2: dispatch_failure <= FAIL_SHARED_MEMORY_BUSY;
                                3'd3: dispatch_failure <= FAIL_SHARED_MEMORY_FRAGMENTED;
                                3'd4: dispatch_failure <= FAIL_BARRIER_CONTEXTS;
                                3'd5: dispatch_failure <= FAIL_DUPLICATE_WORKGROUP;
                                default: dispatch_failure
                                    <= FAIL_SHARED_MEMORY_ALLOCATION_FAILED;
                            endcase
                            txn_state_q <= ST_IDLE;
                        end
                    end
                end
                ST_RESERVE: begin
                    if (reserve_accepted) begin
                        txn_reserved_count_q <= txn_reserved_count_q + 1;
                        txn_state_q <= ST_WAIT_SANITIZE;
                    end else if (reserve_valid && !reserve_ready) begin
                        txn_failure_q <= FAIL_VGPR_FRAGMENTED;
                        rollback_index_q <= 0;
                        if (txn_reserved_count_q == 0) begin
                            txn_state_q <= ST_RELEASE_SHARED_ROLLBACK;
                        end else begin
                            txn_state_q <= ST_ROLLBACK;
                        end
                    end
                end
                ST_WAIT_SANITIZE: begin
                    if (allocation_sanitized_bitmap[reserve_wave_slot])
                        txn_state_q <= ST_ACTIVATE;
                end
                ST_ACTIVATE: begin
                    if (activate_accepted) begin
                        if (txn_wave_index_q + 1 >= $unsigned(txn_wave_count_q)) begin
                            txn_state_q <= ST_COMMIT;
                        end else begin
                            txn_wave_index_q <= txn_wave_index_q + 1;
                            txn_state_q <= ST_RESERVE;
                        end
                    end
                end
                ST_COMMIT: begin
                    if (commit_accepted) begin
                        dispatch_result_valid <= 1'b1;
                        dispatch_accepted <= 1'b1;
                        dispatch_failure <= 5'd0;
                        shared_memory_owned_q <= 1'b0;
                        txn_state_q <= ST_IDLE;
                    end
                end
                ST_ROLLBACK: begin
                    if (release_accepted) begin
                        if (rollback_index_q + 1 >= txn_reserved_count_q) begin
                            txn_reserved_count_q <= 0;
                            txn_state_q <= ST_RELEASE_SHARED_ROLLBACK;
                        end else begin
                            rollback_index_q <= rollback_index_q + 1;
                        end
                    end
                end
                ST_RELEASE_SHARED_ROLLBACK: begin
                    if (shared_memory_release_accepted) begin
                        shared_memory_owned_q <= 1'b0;
                        dispatch_result_valid <= 1'b1;
                        dispatch_failure <= txn_failure_q;
                        txn_state_q <= ST_IDLE;
                    end
                end
                default: txn_state_q <= ST_IDLE;
            endcase
        end
    end

    integer rel_scan;
    always_comb begin
        release_done_mask = '0;
        if (release_accepted && (txn_state_q != ST_ROLLBACK))
            release_done_mask[release_wave_slot] = 1'b1;
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (reset_n && (issuable_wave_mask & ~allocation_active_bitmap) != '0)
            $fatal(1, "workgroup issue mask contains a wave without an active allocator entry");
        if (reset_n && (txn_state_q == ST_IDLE)
            && (shared_memory_allocated_bytes != barrier_shared_used))
            $fatal(1, "shared-memory region ownership disagrees with workgroup admission metadata");
        if (reset_n && selected_release_is_final_wave
            && (shared_memory_release_accepted != release_accepted))
            $fatal(1, "final wave VGPR and shared-memory releases must be accepted together");
        if (reset_n && (matrix_request_accepted & ~issuable_wave_mask) != '0)
            $fatal(1, "matrix frontend accepted a non-issuable workgroup wave");
        if (reset_n && (vector_request_accepted & ~issuable_wave_mask) != '0)
            $fatal(1, "vector frontend accepted a non-issuable workgroup wave");
    end
`endif
endmodule
