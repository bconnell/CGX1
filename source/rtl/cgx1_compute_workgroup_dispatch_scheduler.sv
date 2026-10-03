// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// CU-local arbitration for already-decoded workgroups; residency remains downstream authority.
`timescale 1ns/1ps
module cgx1_compute_workgroup_dispatch_scheduler #(
    parameter integer RESIDENT_WAVE_SLOTS = 8,
    parameter integer MAX_PENDING_ENTRIES = 16,
    parameter integer WORKGROUP_ID_WIDTH = 16,
    parameter integer VIRTUAL_ADDRESS_WIDTH = 57,
    parameter integer AGING_INTERVAL_CYCLES = 64,
    parameter logic [63:0] PRIORITY_WEIGHT_FLAT = {
        8'd128, 8'd64, 8'd32, 8'd16, 8'd8, 8'd4, 8'd2, 8'd1
    },
    parameter integer WAVE_COUNT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1)
        ? 1 : $clog2(RESIDENT_WAVE_SLOTS + 1),
    parameter integer PENDING_INDEX_WIDTH = (MAX_PENDING_ENTRIES <= 1)
        ? 1 : $clog2(MAX_PENDING_ENTRIES),
    parameter integer PENDING_COUNT_WIDTH = (MAX_PENDING_ENTRIES <= 1)
        ? 1 : $clog2(MAX_PENDING_ENTRIES + 1)
) (
    input logic clk,
    input logic reset_n,
    input logic tile_eligible,
    input logic [63:0] faulted_queue_mask,

    input logic submit_valid,
    output logic submit_ready,
    input logic [5:0] submit_queue_context_id,
    input logic [63:0] submit_process_id,
    input logic [63:0] submit_address_space_id,
    input logic [2:0] submit_priority,
    input logic submit_graphics,
    input logic [WORKGROUP_ID_WIDTH-1:0] submit_workgroup_id,
    input logic [WAVE_COUNT_WIDTH-1:0] submit_wave_count,
    input logic [VIRTUAL_ADDRESS_WIDTH-1:0] submit_start_pc,
    input logic [(RESIDENT_WAVE_SLOTS*32)-1:0] submit_initial_live_lane_mask_flat,
    input logic [(RESIDENT_WAVE_SLOTS*9)-1:0] submit_vgpr_register_counts_flat,
    input logic [15:0] submit_scalar_state_units_per_wave,
    input logic [31:0] submit_shared_local_bytes,
    input logic [15:0] submit_other_workgroup_state_units,

    output logic dispatch_valid,
    input logic dispatch_ready,
    output logic [5:0] dispatch_queue_context_id,
    output logic [63:0] dispatch_process_id,
    output logic [63:0] dispatch_address_space_id,
    output logic [2:0] dispatch_priority,
    output logic [WORKGROUP_ID_WIDTH-1:0] dispatch_workgroup_id,
    output logic [WAVE_COUNT_WIDTH-1:0] dispatch_wave_count,
    output logic [VIRTUAL_ADDRESS_WIDTH-1:0] dispatch_start_pc,
    output logic [(RESIDENT_WAVE_SLOTS*32)-1:0] dispatch_initial_live_lane_mask_flat,
    output logic [(RESIDENT_WAVE_SLOTS*9)-1:0] dispatch_vgpr_register_counts_flat,
    output logic [15:0] dispatch_scalar_state_units_per_wave,
    output logic [31:0] dispatch_shared_local_bytes,
    output logic [15:0] dispatch_other_workgroup_state_units,

    input logic dispatch_result_valid,
    input logic dispatch_accepted,
    input logic [4:0] dispatch_failure,
    output logic completion_valid,
    input logic completion_ready,
    output logic [5:0] completion_queue_context_id,
    output logic [63:0] completion_process_id,
    output logic [63:0] completion_address_space_id,
    output logic [WORKGROUP_ID_WIDTH-1:0] completion_workgroup_id,
    // 0 admitted, 1 terminal admission failure, 2 queue faulted, 3 graphics on compute CU.
    output logic [1:0] completion_status,
    output logic [4:0] completion_failure,
    output logic [PENDING_COUNT_WIDTH-1:0] pending_count
);
    localparam logic [4:0] FAIL_BARRIER_CONTEXTS = 5'd4;
    localparam logic [4:0] FAIL_WORKGROUP_WAVE_LIMIT = 5'd2;
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

    logic entry_valid [0:MAX_PENDING_ENTRIES-1];
    logic [5:0] entry_queue_context_id [0:MAX_PENDING_ENTRIES-1];
    logic [63:0] entry_process_id [0:MAX_PENDING_ENTRIES-1];
    logic [63:0] entry_address_space_id [0:MAX_PENDING_ENTRIES-1];
    logic [2:0] entry_priority [0:MAX_PENDING_ENTRIES-1];
    logic entry_graphics [0:MAX_PENDING_ENTRIES-1];
    logic [WORKGROUP_ID_WIDTH-1:0] entry_workgroup_id [0:MAX_PENDING_ENTRIES-1];
    logic [WAVE_COUNT_WIDTH-1:0] entry_wave_count [0:MAX_PENDING_ENTRIES-1];
    logic [VIRTUAL_ADDRESS_WIDTH-1:0] entry_start_pc [0:MAX_PENDING_ENTRIES-1];
    logic [(RESIDENT_WAVE_SLOTS*32)-1:0] entry_live_mask [0:MAX_PENDING_ENTRIES-1];
    logic [(RESIDENT_WAVE_SLOTS*9)-1:0] entry_vgpr_counts [0:MAX_PENDING_ENTRIES-1];
    logic [15:0] entry_scalar_units [0:MAX_PENDING_ENTRIES-1];
    logic [31:0] entry_shared_bytes [0:MAX_PENDING_ENTRIES-1];
    logic [15:0] entry_other_units [0:MAX_PENDING_ENTRIES-1];
    logic [63:0] entry_order [0:MAX_PENDING_ENTRIES-1];

    logic signed [63:0] context_credit [0:63];
    logic [63:0] context_wait_cycles [0:63];
    logic [7:0] context_weight [0:63];
    logic [5:0] round_robin_cursor_q;
    logic [63:0] next_order_q;

    logic inflight_q;
    logic [PENDING_INDEX_WIDTH-1:0] inflight_entry_q;
    logic [5:0] inflight_context_q;
    logic [63:0] inflight_process_q;
    logic [63:0] inflight_address_space_q;
    logic [WORKGROUP_ID_WIDTH-1:0] inflight_workgroup_q;

    logic free_slot_found;
    logic [PENDING_INDEX_WIDTH-1:0] free_slot;
    logic [63:0] context_head_mask;
    logic selected_valid;
    logic [PENDING_INDEX_WIDTH-1:0] selected_entry;
    logic [5:0] selected_context;
    logic [2:0] selected_priority;
    logic [7:0] selected_weight;
    logic signed [63:0] selected_next_credit;
    logic [63:0] selected_total_weight;
    logic selected_faulted;
    logic selected_graphics;
    logic selected_context_has_other;
    logic inflight_context_has_other;
    logic selected_attempt;
    integer pending_count_integer;
    integer comb_i;
    integer comb_j;
    integer comb_distance;
    integer comb_effective_priority;
    integer comb_best_distance;
    integer comb_promotion;
    integer comb_weight;
    integer comb_ctx;
    integer seq_i;
    integer seq_another_for_context;

    function automatic logic failure_is_retryable(input logic [4:0] failure_code);
        begin
            case (failure_code)
                FAIL_BARRIER_CONTEXTS,
                FAIL_WAVE_SLOTS_BUSY,
                FAIL_VGPR_ROWS_BUSY,
                FAIL_VGPR_FRAGMENTED,
                FAIL_SCALAR_STATE_BUSY,
                FAIL_SHARED_MEMORY_BUSY,
                FAIL_OTHER_STATE_BUSY,
                FAIL_SHARED_MEMORY_FRAGMENTED: failure_is_retryable = 1'b1;
                default: failure_is_retryable = 1'b0;
            endcase
        end
    endfunction

    always_comb begin : dispatch_select
        logic is_head;
        logic signed [63:0] candidate_credit;
        logic signed [63:0] best_credit;
        free_slot_found = 1'b0;
        free_slot = '0;
        pending_count_integer = 0;
        context_head_mask = '0;
        selected_valid = 1'b0;
        selected_entry = '0;
        selected_context = '0;
        selected_priority = '0;
        selected_weight = '0;
        selected_next_credit = '0;
        selected_total_weight = '0;
        selected_faulted = 1'b0;
        selected_graphics = 1'b0;
        selected_context_has_other = 1'b0;
        inflight_context_has_other = 1'b0;
        best_credit = 64'sh8000000000000000;
        comb_best_distance = 64;
        for (comb_ctx = 0; comb_ctx < 64; comb_ctx = comb_ctx + 1)
            context_weight[comb_ctx] = '0;

        for (comb_i = 0; comb_i < MAX_PENDING_ENTRIES; comb_i = comb_i + 1) begin
            if (!entry_valid[comb_i] && !free_slot_found) begin
                free_slot_found = 1'b1;
                free_slot = comb_i[PENDING_INDEX_WIDTH-1:0];
            end
            if (entry_valid[comb_i])
                pending_count_integer = pending_count_integer + 1;
        end

        for (comb_i = 0; comb_i < MAX_PENDING_ENTRIES; comb_i = comb_i + 1) begin
            if (entry_valid[comb_i]) begin
                is_head = 1'b1;
                for (comb_j = 0; comb_j < MAX_PENDING_ENTRIES; comb_j = comb_j + 1) begin
                    if (comb_j != comb_i && entry_valid[comb_j]
                        && entry_queue_context_id[comb_j] == entry_queue_context_id[comb_i]
                        && entry_order[comb_j] < entry_order[comb_i])
                        is_head = 1'b0;
                end
                if (is_head) begin
                    context_head_mask[entry_queue_context_id[comb_i]] = 1'b1;
                    if (context_wait_cycles[entry_queue_context_id[comb_i]]
                        == 64'hffffffffffffffff)
                        comb_promotion = context_wait_cycles[entry_queue_context_id[comb_i]]
                            / AGING_INTERVAL_CYCLES;
                    else
                        comb_promotion = (context_wait_cycles[entry_queue_context_id[comb_i]] + 1'b1)
                            / AGING_INTERVAL_CYCLES;
                    comb_effective_priority = entry_priority[comb_i] + comb_promotion;
                    if (comb_effective_priority > 7)
                        comb_effective_priority = 7;
                    comb_weight = $unsigned(
                        PRIORITY_WEIGHT_FLAT[comb_effective_priority*8 +: 8]);
                    context_weight[entry_queue_context_id[comb_i]] = comb_weight[7:0];
                    candidate_credit = context_credit[entry_queue_context_id[comb_i]]
                        + comb_weight;
                    selected_total_weight = selected_total_weight + comb_weight;
                    comb_distance = (entry_queue_context_id[comb_i]
                        + 64 - round_robin_cursor_q) % 64;
                    if (!selected_valid || candidate_credit > best_credit
                        || (candidate_credit == best_credit
                            && comb_distance < comb_best_distance)) begin
                        selected_valid = 1'b1;
                        selected_entry = comb_i[PENDING_INDEX_WIDTH-1:0];
                        selected_context = entry_queue_context_id[comb_i];
                        selected_priority = entry_priority[comb_i];
                        selected_weight = comb_weight[7:0];
                        selected_next_credit = candidate_credit;
                        selected_faulted = faulted_queue_mask[entry_queue_context_id[comb_i]];
                        selected_graphics = entry_graphics[comb_i];
                        best_credit = candidate_credit;
                        comb_best_distance = comb_distance;
                    end
                end
            end
        end

        for (comb_j = 0; comb_j < MAX_PENDING_ENTRIES; comb_j = comb_j + 1) begin
            if (entry_valid[comb_j]) begin
                if (selected_valid && comb_j != selected_entry
                    && entry_queue_context_id[comb_j] == selected_context)
                    selected_context_has_other = 1'b1;
                if (inflight_q && comb_j != inflight_entry_q
                    && entry_queue_context_id[comb_j] == inflight_context_q)
                    inflight_context_has_other = 1'b1;
            end
        end

        submit_ready = reset_n && free_slot_found;
        pending_count = pending_count_integer[PENDING_COUNT_WIDTH-1:0];
        selected_attempt = selected_valid && tile_eligible && !inflight_q
            && (!completion_valid || completion_ready)
            && (selected_faulted || selected_graphics || dispatch_ready);
        // The real frontend consumes a dispatch only while ready; retain the
        // queue head until its later admission result resolves.
        dispatch_valid = selected_attempt && !selected_faulted && !selected_graphics;
        dispatch_queue_context_id = selected_context;
        dispatch_process_id = '0;
        dispatch_address_space_id = '0;
        dispatch_priority = selected_priority;
        dispatch_workgroup_id = '0;
        dispatch_wave_count = '0;
        dispatch_start_pc = '0;
        dispatch_initial_live_lane_mask_flat = '0;
        dispatch_vgpr_register_counts_flat = '0;
        dispatch_scalar_state_units_per_wave = '0;
        dispatch_shared_local_bytes = '0;
        dispatch_other_workgroup_state_units = '0;
        if (selected_valid) begin
            dispatch_process_id = entry_process_id[selected_entry];
            dispatch_address_space_id = entry_address_space_id[selected_entry];
            dispatch_workgroup_id = entry_workgroup_id[selected_entry];
            dispatch_wave_count = entry_wave_count[selected_entry];
            dispatch_start_pc = entry_start_pc[selected_entry];
            dispatch_initial_live_lane_mask_flat = entry_live_mask[selected_entry];
            dispatch_vgpr_register_counts_flat = entry_vgpr_counts[selected_entry];
            dispatch_scalar_state_units_per_wave = entry_scalar_units[selected_entry];
            dispatch_shared_local_bytes = entry_shared_bytes[selected_entry];
            dispatch_other_workgroup_state_units = entry_other_units[selected_entry];
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin : dispatch_state
        if (!reset_n) begin
            for (seq_i = 0; seq_i < MAX_PENDING_ENTRIES; seq_i = seq_i + 1) begin
                entry_valid[seq_i] <= 1'b0;
                entry_queue_context_id[seq_i] <= '0;
                entry_process_id[seq_i] <= '0;
                entry_address_space_id[seq_i] <= '0;
                entry_priority[seq_i] <= '0;
                entry_graphics[seq_i] <= 1'b0;
                entry_workgroup_id[seq_i] <= '0;
                entry_wave_count[seq_i] <= '0;
                entry_start_pc[seq_i] <= '0;
                entry_live_mask[seq_i] <= '0;
                entry_vgpr_counts[seq_i] <= '0;
                entry_scalar_units[seq_i] <= '0;
                entry_shared_bytes[seq_i] <= '0;
                entry_other_units[seq_i] <= '0;
                entry_order[seq_i] <= '0;
            end
            for (seq_i = 0; seq_i < 64; seq_i = seq_i + 1) begin
                context_credit[seq_i] <= '0;
                context_wait_cycles[seq_i] <= '0;
            end
            round_robin_cursor_q <= '0;
            next_order_q <= '0;
            inflight_q <= 1'b0;
            inflight_entry_q <= '0;
            inflight_context_q <= '0;
            inflight_process_q <= '0;
            inflight_address_space_q <= '0;
            inflight_workgroup_q <= '0;
            completion_valid <= 1'b0;
            completion_queue_context_id <= '0;
            completion_process_id <= '0;
            completion_address_space_id <= '0;
            completion_workgroup_id <= '0;
            completion_status <= '0;
            completion_failure <= '0;
        end else begin
            if (completion_valid && completion_ready)
                completion_valid <= 1'b0;

            for (seq_i = 0; seq_i < 64; seq_i = seq_i + 1) begin
                if (!context_head_mask[seq_i]) begin
                    context_wait_cycles[seq_i] <= '0;
                    context_credit[seq_i] <= '0;
                end
            end

            if (submit_valid && submit_ready) begin
                entry_valid[free_slot] <= 1'b1;
                entry_queue_context_id[free_slot] <= submit_queue_context_id;
                entry_process_id[free_slot] <= submit_process_id;
                entry_address_space_id[free_slot] <= submit_address_space_id;
                entry_priority[free_slot] <= submit_priority;
                entry_graphics[free_slot] <= submit_graphics;
                entry_workgroup_id[free_slot] <= submit_workgroup_id;
                entry_wave_count[free_slot] <= submit_wave_count;
                entry_start_pc[free_slot] <= submit_start_pc;
                entry_live_mask[free_slot] <= submit_initial_live_lane_mask_flat;
                entry_vgpr_counts[free_slot] <= submit_vgpr_register_counts_flat;
                entry_scalar_units[free_slot] <= submit_scalar_state_units_per_wave;
                entry_shared_bytes[free_slot] <= submit_shared_local_bytes;
                entry_other_units[free_slot] <= submit_other_workgroup_state_units;
                entry_order[free_slot] <= next_order_q;
                next_order_q <= next_order_q + 1'b1;
            end

            if (selected_attempt) begin
                for (seq_i = 0; seq_i < 64; seq_i = seq_i + 1) begin
                    if (context_head_mask[seq_i]) begin
                        if (context_wait_cycles[seq_i] != 64'hffffffffffffffff)
                            context_wait_cycles[seq_i] <= context_wait_cycles[seq_i] + 1'b1;
                        context_credit[seq_i] <= context_credit[seq_i]
                            + $signed({1'b0, context_weight[seq_i]});
                    end
                end
                context_credit[selected_context] <= selected_next_credit
                    - $signed(selected_total_weight);
                round_robin_cursor_q <= selected_context + 1'b1;

                if (selected_faulted || selected_graphics) begin
                    entry_valid[selected_entry] <= 1'b0;
                    context_wait_cycles[selected_context] <= '0;
                    completion_valid <= 1'b1;
                    completion_queue_context_id <= selected_context;
                    completion_process_id <= entry_process_id[selected_entry];
                    completion_address_space_id <= entry_address_space_id[selected_entry];
                    completion_workgroup_id <= entry_workgroup_id[selected_entry];
                    completion_status <= selected_faulted ? 2'd2 : 2'd3;
                    completion_failure <= '0;
                    if (!selected_context_has_other)
                        context_credit[selected_context] <= '0;
                end else begin
                    inflight_q <= 1'b1;
                    inflight_entry_q <= selected_entry;
                    inflight_context_q <= selected_context;
                    inflight_process_q <= entry_process_id[selected_entry];
                    inflight_address_space_q <= entry_address_space_id[selected_entry];
                    inflight_workgroup_q <= entry_workgroup_id[selected_entry];
                end
            end

            if (dispatch_result_valid && inflight_q) begin
                inflight_q <= 1'b0;
                if (dispatch_accepted || !failure_is_retryable(dispatch_failure)) begin
                    entry_valid[inflight_entry_q] <= 1'b0;
                    context_wait_cycles[inflight_context_q] <= '0;
                    completion_valid <= 1'b1;
                    completion_queue_context_id <= inflight_context_q;
                    completion_process_id <= inflight_process_q;
                    completion_address_space_id <= inflight_address_space_q;
                    completion_workgroup_id <= inflight_workgroup_q;
                    completion_status <= dispatch_accepted ? 2'd0 : 2'd1;
                    completion_failure <= dispatch_accepted ? '0 : dispatch_failure;
                    if (!inflight_context_has_other)
                        context_credit[inflight_context_q] <= '0;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (RESIDENT_WAVE_SLOTS < 1 || MAX_PENDING_ENTRIES < 1)
            $fatal(1, "CU dispatch scheduler capacities must be nonzero");
        if (AGING_INTERVAL_CYCLES < 1)
            $fatal(1, "CU dispatch scheduler aging interval must be nonzero");
        if ((1 << PENDING_INDEX_WIDTH) < MAX_PENDING_ENTRIES)
            $fatal(1, "CU dispatch scheduler entry index is too narrow");
        if (PRIORITY_WEIGHT_FLAT[7:0] == 0 || PRIORITY_WEIGHT_FLAT[15:8] == 0
            || PRIORITY_WEIGHT_FLAT[23:16] == 0 || PRIORITY_WEIGHT_FLAT[31:24] == 0
            || PRIORITY_WEIGHT_FLAT[39:32] == 0 || PRIORITY_WEIGHT_FLAT[47:40] == 0
            || PRIORITY_WEIGHT_FLAT[55:48] == 0 || PRIORITY_WEIGHT_FLAT[63:56] == 0)
            $fatal(1, "CU dispatch scheduler priority weights must be nonzero");
    end
`endif
endmodule
