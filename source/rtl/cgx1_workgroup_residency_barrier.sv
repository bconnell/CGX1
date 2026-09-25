// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Atomic whole-workgroup CU admission and resident barrier state.
module cgx1_workgroup_residency_barrier #(
    parameter integer RESIDENT_WAVE_SLOTS = 8,
    parameter integer PHYSICAL_VGPR_ROWS = 16,
    parameter integer MAX_WORKGROUP_CONTEXTS = 4,
    parameter integer SCALAR_PREDICATE_STATE_UNITS = 128,
    parameter integer SHARED_LOCAL_MEMORY_BYTES = 4096,
    parameter integer OTHER_WORKGROUP_STATE_UNITS = 128,
    parameter integer WORKGROUP_ID_WIDTH = 16,
    parameter integer WAVE_SLOT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS),
    parameter integer LOCAL_WAVE_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS),
    parameter integer ROW_WIDTH = (PHYSICAL_VGPR_ROWS <= 1) ? 1 : $clog2(PHYSICAL_VGPR_ROWS),
    parameter integer ROW_COUNT_WIDTH = (PHYSICAL_VGPR_ROWS <= 1) ? 1 : $clog2(PHYSICAL_VGPR_ROWS + 1),
    parameter integer WORKGROUP_CONTEXT_WIDTH = (MAX_WORKGROUP_CONTEXTS <= 1) ? 1 : $clog2(MAX_WORKGROUP_CONTEXTS),
    parameter integer WAVE_COUNT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS + 1)
) (
    input  logic                              clk,
    input  logic                              reset_n,

    input  logic                              dispatch_valid,
    input  logic [WORKGROUP_ID_WIDTH-1:0]     dispatch_workgroup_id,
    input  logic [WAVE_COUNT_WIDTH-1:0]        dispatch_wave_count,
    input  logic [8:0]                        dispatch_vgpr_registers_per_wave,
    input  logic [15:0]                       dispatch_scalar_state_units_per_wave,
    input  logic [31:0]                       dispatch_shared_local_bytes,
    input  logic [15:0]                       dispatch_other_workgroup_state_units,
    output logic                              dispatch_ready,
    output logic                              dispatch_accepted,
    output logic [4:0]                        dispatch_failure,
    output logic [RESIDENT_WAVE_SLOTS-1:0]    dispatch_allocated_wave_slots,
    output logic [(RESIDENT_WAVE_SLOTS*WAVE_SLOT_WIDTH)-1:0] dispatch_wave_slot_map_flat,
    output logic [(RESIDENT_WAVE_SLOTS*ROW_WIDTH)-1:0] dispatch_vgpr_row_base_flat,

    input  logic                              barrier_arrive_valid,
    input  logic [WORKGROUP_ID_WIDTH-1:0]     barrier_arrive_workgroup_id,
    input  logic [RESIDENT_WAVE_SLOTS-1:0]    barrier_arrive_wave_mask,
    output logic                              barrier_arrive_ready,
    output logic                              barrier_arrive_accepted,
    output logic                              barrier_release_valid,
    output logic [WORKGROUP_ID_WIDTH-1:0]     barrier_release_workgroup_id,
    output logic [31:0]                       barrier_release_generation,
    output logic [RESIDENT_WAVE_SLOTS-1:0]    barrier_release_wave_mask,

    input  logic                              terminate_wave_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]        terminate_wave_slot,
    input  logic [1:0]                        terminate_wave_reason, // 00 complete, 01 faulted, 10 killed, 11 reserved
    output logic                              terminate_wave_ready,
    output logic                              terminate_wave_accepted,

    input  logic                              workgroup_abort_valid,
    input  logic [WORKGROUP_ID_WIDTH-1:0]     workgroup_abort_id,
    output logic                              workgroup_abort_ready,
    output logic                              workgroup_abort_accepted,

    input  logic [WORKGROUP_ID_WIDTH-1:0]     query_workgroup_id,
    output logic                              query_workgroup_found,
    output logic [WAVE_COUNT_WIDTH-1:0]        query_workgroup_wave_count,
    output logic [RESIDENT_WAVE_SLOTS-1:0]    query_workgroup_live_waves,
    output logic [RESIDENT_WAVE_SLOTS-1:0]    query_workgroup_arrived_waves,
    output logic [31:0]                       query_barrier_generation,

    output logic [RESIDENT_WAVE_SLOTS-1:0]    resident_wave_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0]    barrier_waiting_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0]    issuable_wave_mask,
    output logic [MAX_WORKGROUP_CONTEXTS-1:0] workgroup_active_mask,
    output logic [WAVE_COUNT_WIDTH-1:0]        resident_wave_count,
    output logic [ROW_COUNT_WIDTH-1:0]        pooled_vgpr_rows_used,
    output logic [31:0]                       scalar_state_units_used,
    output logic [31:0]                       shared_local_bytes_used,
    output logic [31:0]                       other_workgroup_state_units_used
);

    localparam logic [4:0] ADMIT_OK = 5'd0;
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

    logic [MAX_WORKGROUP_CONTEXTS-1:0] group_active_q;
    logic [WORKGROUP_ID_WIDTH-1:0] group_id_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [WAVE_COUNT_WIDTH-1:0] group_wave_count_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [RESIDENT_WAVE_SLOTS-1:0] group_live_waves_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [RESIDENT_WAVE_SLOTS-1:0] group_arrived_waves_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [31:0] group_barrier_generation_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [31:0] group_shared_local_bytes_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [15:0] group_other_state_units_q [0:MAX_WORKGROUP_CONTEXTS-1];

    logic [WORKGROUP_CONTEXT_WIDTH-1:0] slot_group_context_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [LOCAL_WAVE_WIDTH-1:0] slot_local_wave_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [ROW_WIDTH-1:0] slot_vgpr_row_base_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [ROW_COUNT_WIDTH-1:0] slot_vgpr_row_count_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [15:0] slot_scalar_state_units_q [0:RESIDENT_WAVE_SLOTS-1];

    logic [PHYSICAL_VGPR_ROWS-1:0] occupied_rows;
    logic [PHYSICAL_VGPR_ROWS-1:0] planned_rows;
    logic [RESIDENT_WAVE_SLOTS-1:0] planned_wave_slots;
    logic [RESIDENT_WAVE_SLOTS-1:0] planned_live_waves;
    integer planned_wave_slot [0:RESIDENT_WAVE_SLOTS-1];
    integer planned_row_base [0:RESIDENT_WAVE_SLOTS-1];
    integer free_wave_slots;
    integer free_vgpr_rows;
    integer rows_per_wave;
    integer total_rows_needed;
    integer active_group_count;
    integer free_group_index;
    integer abort_group_index;
    integer arrive_group_index;
    integer terminate_group_index;
    integer used_row_count;
    integer used_scalar_count;
    integer used_shared_count;
    integer used_other_count;
    logic slot_found;
    logic row_found;
    logic candidate_free;
    logic group_id_duplicate;
    logic [4:0] planned_failure;
    logic [RESIDENT_WAVE_SLOTS-1:0] planned_arrived_mask;
    logic [RESIDENT_WAVE_SLOTS-1:0] planned_live_after_terminate;
    logic [RESIDENT_WAVE_SLOTS-1:0] planned_arrived_after_terminate;

    integer seq_group;
    integer seq_slot;
    integer seq_local_wave;
    integer seq_arrive_group;
    integer seq_terminate_group;

    always @* begin
        integer comb_group;
        integer comb_slot;
        integer comb_row;
        integer comb_probe;
        integer comb_local_wave;

        occupied_rows = '0;
        planned_rows = '0;
        planned_wave_slots = '0;
        planned_live_waves = '0;
        planned_failure = ADMIT_OK;
        free_wave_slots = 0;
        free_vgpr_rows = 0;
        rows_per_wave = 0;
        total_rows_needed = 0;
        active_group_count = 0;
        free_group_index = -1;
        used_row_count = 0;
        used_scalar_count = 0;
        used_shared_count = 0;
        used_other_count = 0;
        group_id_duplicate = 1'b0;
        slot_found = 1'b0;
        row_found = 1'b0;
        candidate_free = 1'b0;
        for (comb_local_wave = 0; comb_local_wave < RESIDENT_WAVE_SLOTS; comb_local_wave = comb_local_wave + 1) begin
            planned_wave_slot[comb_local_wave] = -1;
            planned_row_base[comb_local_wave] = -1;
        end

        for (comb_slot = 0; comb_slot < RESIDENT_WAVE_SLOTS; comb_slot = comb_slot + 1) begin
            if (!resident_wave_mask[comb_slot]) begin
                free_wave_slots = free_wave_slots + 1;
            end else begin
                used_scalar_count = used_scalar_count + slot_scalar_state_units_q[comb_slot];
                for (comb_row = 0; comb_row < PHYSICAL_VGPR_ROWS; comb_row = comb_row + 1) begin
                    if ((comb_row >= slot_vgpr_row_base_q[comb_slot])
                        && (comb_row < (slot_vgpr_row_base_q[comb_slot] + slot_vgpr_row_count_q[comb_slot]))) begin
                        occupied_rows[comb_row] = 1'b1;
                    end
                end
            end
        end

        for (comb_row = 0; comb_row < PHYSICAL_VGPR_ROWS; comb_row = comb_row + 1) begin
            if (!occupied_rows[comb_row]) begin
                free_vgpr_rows = free_vgpr_rows + 1;
            end else begin
                used_row_count = used_row_count + 1;
            end
        end

        for (comb_group = 0; comb_group < MAX_WORKGROUP_CONTEXTS; comb_group = comb_group + 1) begin
            if (group_active_q[comb_group]) begin
                active_group_count = active_group_count + 1;
                used_shared_count = used_shared_count + group_shared_local_bytes_q[comb_group];
                used_other_count = used_other_count + group_other_state_units_q[comb_group];
                if (group_id_q[comb_group] == dispatch_workgroup_id) begin
                    group_id_duplicate = 1'b1;
                end
            end else if (free_group_index < 0) begin
                free_group_index = comb_group;
            end
        end

        dispatch_ready = 1'b1;
        dispatch_allocated_wave_slots = '0;
        dispatch_wave_slot_map_flat = '0;
        dispatch_vgpr_row_base_flat = '0;
        if (dispatch_valid) begin
            if (dispatch_wave_count == 0) begin
                planned_failure = FAIL_INVALID_WAVE_COUNT;
            end else if ($unsigned(dispatch_wave_count) > RESIDENT_WAVE_SLOTS) begin
                planned_failure = FAIL_WORKGROUP_WAVE_LIMIT;
            end else if (group_id_duplicate) begin
                planned_failure = FAIL_DUPLICATE_WORKGROUP;
            end else if ((dispatch_vgpr_registers_per_wave == 0)
                || ($unsigned(dispatch_vgpr_registers_per_wave) > 256)) begin
                planned_failure = FAIL_INVALID_VGPR_DEMAND;
            end else begin
                rows_per_wave = ($unsigned(dispatch_vgpr_registers_per_wave) + 7) / 8;
                total_rows_needed = rows_per_wave * $unsigned(dispatch_wave_count);
                if (total_rows_needed > PHYSICAL_VGPR_ROWS) begin
                    planned_failure = FAIL_VGPR_EXCEEDS_CU;
                end else if (($unsigned(dispatch_scalar_state_units_per_wave)
                        * $unsigned(dispatch_wave_count)) > SCALAR_PREDICATE_STATE_UNITS) begin
                    planned_failure = FAIL_SCALAR_STATE_EXCEEDS_CU;
                end else if ($unsigned(dispatch_shared_local_bytes) > SHARED_LOCAL_MEMORY_BYTES) begin
                    planned_failure = FAIL_SHARED_MEMORY_EXCEEDS_CU;
                end else if ($unsigned(dispatch_other_workgroup_state_units)
                    > OTHER_WORKGROUP_STATE_UNITS) begin
                    planned_failure = FAIL_OTHER_STATE_EXCEEDS_CU;
                end else if (free_group_index < 0) begin
                    planned_failure = FAIL_BARRIER_CONTEXTS;
                end else if (free_wave_slots < $unsigned(dispatch_wave_count)) begin
                    planned_failure = FAIL_WAVE_SLOTS_BUSY;
                end else if (free_vgpr_rows < total_rows_needed) begin
                    planned_failure = FAIL_VGPR_ROWS_BUSY;
                end else if ((used_scalar_count
                        + ($unsigned(dispatch_scalar_state_units_per_wave)
                            * $unsigned(dispatch_wave_count))) > SCALAR_PREDICATE_STATE_UNITS) begin
                    planned_failure = FAIL_SCALAR_STATE_BUSY;
                end else if ((used_shared_count + $unsigned(dispatch_shared_local_bytes))
                    > SHARED_LOCAL_MEMORY_BYTES) begin
                    planned_failure = FAIL_SHARED_MEMORY_BUSY;
                end else if ((used_other_count + $unsigned(dispatch_other_workgroup_state_units))
                    > OTHER_WORKGROUP_STATE_UNITS) begin
                    planned_failure = FAIL_OTHER_STATE_BUSY;
                end

                if (planned_failure == ADMIT_OK) begin
                    planned_rows = occupied_rows;
                    for (comb_local_wave = 0; comb_local_wave < RESIDENT_WAVE_SLOTS; comb_local_wave = comb_local_wave + 1) begin
                        planned_wave_slot[comb_local_wave] = -1;
                        planned_row_base[comb_local_wave] = -1;
                        if (comb_local_wave < $unsigned(dispatch_wave_count)) begin
                            slot_found = 1'b0;
                            for (comb_slot = 0; comb_slot < RESIDENT_WAVE_SLOTS; comb_slot = comb_slot + 1) begin
                                if (!slot_found && !resident_wave_mask[comb_slot]
                                    && !planned_wave_slots[comb_slot]) begin
                                    planned_wave_slot[comb_local_wave] = comb_slot;
                                    planned_wave_slots[comb_slot] = 1'b1;
                                    slot_found = 1'b1;
                                end
                            end

                            row_found = 1'b0;
                            for (comb_row = 0; comb_row < PHYSICAL_VGPR_ROWS; comb_row = comb_row + 1) begin
                                candidate_free = ((comb_row + rows_per_wave) <= PHYSICAL_VGPR_ROWS);
                                for (comb_probe = 0; comb_probe < PHYSICAL_VGPR_ROWS; comb_probe = comb_probe + 1) begin
                                    if ((comb_probe < rows_per_wave)
                                        && ((comb_row + comb_probe) < PHYSICAL_VGPR_ROWS)
                                        && planned_rows[comb_row + comb_probe]) begin
                                        candidate_free = 1'b0;
                                    end
                                end
                                if (!row_found && candidate_free) begin
                                    planned_row_base[comb_local_wave] = comb_row;
                                    for (comb_probe = 0; comb_probe < PHYSICAL_VGPR_ROWS; comb_probe = comb_probe + 1) begin
                                        if ((comb_probe < rows_per_wave)
                                            && ((comb_row + comb_probe) < PHYSICAL_VGPR_ROWS)) begin
                                            planned_rows[comb_row + comb_probe] = 1'b1;
                                        end
                                    end
                                    row_found = 1'b1;
                                end
                            end
                            if (!slot_found || !row_found) begin
                                planned_failure = FAIL_VGPR_FRAGMENTED;
                            end else begin
                                planned_live_waves[comb_local_wave] = 1'b1;
                            end
                        end
                    end
                end
            end

            dispatch_failure = planned_failure;
            dispatch_accepted = (planned_failure == ADMIT_OK);
            if (dispatch_accepted) begin
                dispatch_allocated_wave_slots = planned_wave_slots;
                for (comb_local_wave = 0; comb_local_wave < RESIDENT_WAVE_SLOTS; comb_local_wave = comb_local_wave + 1) begin
                    if (comb_local_wave < $unsigned(dispatch_wave_count)) begin
                        dispatch_wave_slot_map_flat[(comb_local_wave*WAVE_SLOT_WIDTH) +: WAVE_SLOT_WIDTH]
                            = planned_wave_slot[comb_local_wave][WAVE_SLOT_WIDTH-1:0];
                        dispatch_vgpr_row_base_flat[(comb_local_wave*ROW_WIDTH) +: ROW_WIDTH]
                            = planned_row_base[comb_local_wave][ROW_WIDTH-1:0];
                    end
                end
            end else begin
                dispatch_accepted = 1'b0;
            end
        end else begin
            dispatch_failure = ADMIT_OK;
            dispatch_accepted = 1'b0;
            for (comb_local_wave = 0; comb_local_wave < RESIDENT_WAVE_SLOTS; comb_local_wave = comb_local_wave + 1) begin
                planned_wave_slot[comb_local_wave] = -1;
                planned_row_base[comb_local_wave] = -1;
            end
        end

    end

    always @* begin
        integer out_slot;
        barrier_waiting_mask = '0;
        issuable_wave_mask = '0;
        workgroup_active_mask = group_active_q;
        resident_wave_count = '0;
        pooled_vgpr_rows_used = used_row_count[ROW_COUNT_WIDTH-1:0];
        scalar_state_units_used = used_scalar_count;
        shared_local_bytes_used = used_shared_count;
        other_workgroup_state_units_used = used_other_count;
        for (out_slot = 0; out_slot < RESIDENT_WAVE_SLOTS; out_slot = out_slot + 1) begin
            if (resident_wave_mask[out_slot]) begin
                resident_wave_count = resident_wave_count + 1'b1;
                if (group_arrived_waves_q[slot_group_context_q[out_slot]][slot_local_wave_q[out_slot]]) begin
                    barrier_waiting_mask[out_slot] = 1'b1;
                end else begin
                    issuable_wave_mask[out_slot] = 1'b1;
                end
            end
        end
    end

    always @* begin
        integer query_group;
        query_workgroup_found = 1'b0;
        query_workgroup_wave_count = '0;
        query_workgroup_live_waves = '0;
        query_workgroup_arrived_waves = '0;
        query_barrier_generation = '0;
        for (query_group = 0; query_group < MAX_WORKGROUP_CONTEXTS; query_group = query_group + 1) begin
            if (!query_workgroup_found && group_active_q[query_group]
                && (group_id_q[query_group] == query_workgroup_id)) begin
                query_workgroup_found = 1'b1;
                query_workgroup_wave_count = group_wave_count_q[query_group];
                query_workgroup_live_waves = group_live_waves_q[query_group];
                query_workgroup_arrived_waves = group_arrived_waves_q[query_group];
                query_barrier_generation = group_barrier_generation_q[query_group];
            end
        end
    end

    always @* begin
        integer control_group;
        abort_group_index = -1;
        arrive_group_index = -1;
        terminate_group_index = -1;
        for (control_group = 0; control_group < MAX_WORKGROUP_CONTEXTS; control_group = control_group + 1) begin
            if (group_active_q[control_group]) begin
                if ((group_id_q[control_group] == workgroup_abort_id) && (abort_group_index < 0))
                    abort_group_index = control_group;
                if ((group_id_q[control_group] == barrier_arrive_workgroup_id) && (arrive_group_index < 0))
                    arrive_group_index = control_group;
            end
        end
        if (($unsigned(terminate_wave_slot) < RESIDENT_WAVE_SLOTS)
            && resident_wave_mask[terminate_wave_slot]) begin
            terminate_group_index = slot_group_context_q[terminate_wave_slot];
        end

        workgroup_abort_ready = (abort_group_index >= 0);
        workgroup_abort_accepted = workgroup_abort_valid && workgroup_abort_ready;
        terminate_wave_ready = ($unsigned(terminate_wave_slot) < RESIDENT_WAVE_SLOTS)
            && resident_wave_mask[terminate_wave_slot] && !workgroup_abort_accepted
            && (terminate_wave_reason != 2'b11);
        terminate_wave_accepted = terminate_wave_valid && terminate_wave_ready;

        barrier_arrive_ready = 1'b0;
        if ((arrive_group_index >= 0) && (barrier_arrive_wave_mask != '0)
            && !workgroup_abort_accepted && !terminate_wave_accepted) begin
            barrier_arrive_ready =
                ((barrier_arrive_wave_mask & ~group_live_waves_q[arrive_group_index]) == '0)
                && ((barrier_arrive_wave_mask & group_arrived_waves_q[arrive_group_index]) == '0);
        end
        barrier_arrive_accepted = barrier_arrive_valid && barrier_arrive_ready;

        seq_arrive_group = arrive_group_index;
        seq_terminate_group = terminate_group_index;
        planned_arrived_mask = '0;
        planned_live_after_terminate = '0;
        planned_arrived_after_terminate = '0;
        if (barrier_arrive_accepted) begin
            planned_arrived_mask = group_arrived_waves_q[seq_arrive_group]
                | barrier_arrive_wave_mask;
        end
        if (terminate_wave_accepted) begin
            planned_live_after_terminate = group_live_waves_q[seq_terminate_group]
                & ~(1'b1 << slot_local_wave_q[terminate_wave_slot]);
            planned_arrived_after_terminate = group_arrived_waves_q[seq_terminate_group]
                & planned_live_after_terminate;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            resident_wave_mask <= '0;
            group_active_q <= '0;
            barrier_release_valid <= 1'b0;
            barrier_release_workgroup_id <= '0;
            barrier_release_generation <= '0;
            barrier_release_wave_mask <= '0;
            for (seq_group = 0; seq_group < MAX_WORKGROUP_CONTEXTS; seq_group = seq_group + 1) begin
                group_id_q[seq_group] <= '0;
                group_wave_count_q[seq_group] <= '0;
                group_live_waves_q[seq_group] <= '0;
                group_arrived_waves_q[seq_group] <= '0;
                group_barrier_generation_q[seq_group] <= '0;
                group_shared_local_bytes_q[seq_group] <= '0;
                group_other_state_units_q[seq_group] <= '0;
            end
            for (seq_slot = 0; seq_slot < RESIDENT_WAVE_SLOTS; seq_slot = seq_slot + 1) begin
                slot_group_context_q[seq_slot] <= '0;
                slot_local_wave_q[seq_slot] <= '0;
                slot_vgpr_row_base_q[seq_slot] <= '0;
                slot_vgpr_row_count_q[seq_slot] <= '0;
                slot_scalar_state_units_q[seq_slot] <= '0;
            end
        end else begin
            barrier_release_valid <= 1'b0;
            barrier_release_workgroup_id <= '0;
            barrier_release_generation <= '0;
            barrier_release_wave_mask <= '0;

            if (workgroup_abort_accepted) begin
                group_active_q[abort_group_index] <= 1'b0;
                group_live_waves_q[abort_group_index] <= '0;
                group_arrived_waves_q[abort_group_index] <= '0;
                group_wave_count_q[abort_group_index] <= '0;
                group_shared_local_bytes_q[abort_group_index] <= '0;
                group_other_state_units_q[abort_group_index] <= '0;
                for (seq_slot = 0; seq_slot < RESIDENT_WAVE_SLOTS; seq_slot = seq_slot + 1) begin
                    if (resident_wave_mask[seq_slot]
                        && (slot_group_context_q[seq_slot] == abort_group_index)) begin
                        resident_wave_mask[seq_slot] <= 1'b0;
                        slot_group_context_q[seq_slot] <= '0;
                        slot_local_wave_q[seq_slot] <= '0;
                        slot_vgpr_row_base_q[seq_slot] <= '0;
                        slot_vgpr_row_count_q[seq_slot] <= '0;
                        slot_scalar_state_units_q[seq_slot] <= '0;
                    end
                end
            end else if (terminate_wave_accepted) begin
                resident_wave_mask[terminate_wave_slot] <= 1'b0;
                slot_group_context_q[terminate_wave_slot] <= '0;
                slot_local_wave_q[terminate_wave_slot] <= '0;
                slot_vgpr_row_base_q[terminate_wave_slot] <= '0;
                slot_vgpr_row_count_q[terminate_wave_slot] <= '0;
                slot_scalar_state_units_q[terminate_wave_slot] <= '0;

                if (planned_live_after_terminate == '0) begin
                    group_active_q[seq_terminate_group] <= 1'b0;
                    group_live_waves_q[seq_terminate_group] <= '0;
                    group_arrived_waves_q[seq_terminate_group] <= '0;
                    group_wave_count_q[seq_terminate_group] <= '0;
                    group_shared_local_bytes_q[seq_terminate_group] <= '0;
                    group_other_state_units_q[seq_terminate_group] <= '0;
                end else begin
                    group_live_waves_q[seq_terminate_group] <= planned_live_after_terminate;
                    if (planned_arrived_after_terminate == planned_live_after_terminate) begin
                        barrier_release_valid <= 1'b1;
                        barrier_release_workgroup_id <= group_id_q[seq_terminate_group];
                        barrier_release_generation <= group_barrier_generation_q[seq_terminate_group];
                        group_arrived_waves_q[seq_terminate_group] <= '0;
                        group_barrier_generation_q[seq_terminate_group]
                            <= group_barrier_generation_q[seq_terminate_group] + 1'b1;
                        for (seq_slot = 0; seq_slot < RESIDENT_WAVE_SLOTS; seq_slot = seq_slot + 1) begin
                            if (resident_wave_mask[seq_slot]
                                && (slot_group_context_q[seq_slot] == seq_terminate_group)
                                && (seq_slot != terminate_wave_slot)
                                && group_arrived_waves_q[seq_terminate_group][slot_local_wave_q[seq_slot]]) begin
                                barrier_release_wave_mask[seq_slot] <= 1'b1;
                            end
                        end
                    end else begin
                        group_arrived_waves_q[seq_terminate_group]
                            <= planned_arrived_after_terminate;
                    end
                end
            end else if (barrier_arrive_accepted) begin
                if ((planned_arrived_mask & group_live_waves_q[seq_arrive_group])
                    == group_live_waves_q[seq_arrive_group]) begin
                    group_arrived_waves_q[seq_arrive_group] <= '0;
                    group_barrier_generation_q[seq_arrive_group]
                        <= group_barrier_generation_q[seq_arrive_group] + 1'b1;
                    barrier_release_valid <= 1'b1;
                    barrier_release_workgroup_id <= group_id_q[seq_arrive_group];
                    barrier_release_generation <= group_barrier_generation_q[seq_arrive_group];
                    for (seq_slot = 0; seq_slot < RESIDENT_WAVE_SLOTS; seq_slot = seq_slot + 1) begin
                        if (resident_wave_mask[seq_slot]
                            && (slot_group_context_q[seq_slot] == seq_arrive_group)) begin
                            barrier_release_wave_mask[seq_slot] <= 1'b1;
                        end
                    end
                end else begin
                    group_arrived_waves_q[seq_arrive_group] <= planned_arrived_mask;
                end
            end

            if (dispatch_accepted) begin
                group_active_q[free_group_index] <= 1'b1;
                group_id_q[free_group_index] <= dispatch_workgroup_id;
                group_wave_count_q[free_group_index] <= dispatch_wave_count;
                group_live_waves_q[free_group_index] <= planned_live_waves;
                group_arrived_waves_q[free_group_index] <= '0;
                group_barrier_generation_q[free_group_index] <= '0;
                group_shared_local_bytes_q[free_group_index] <= dispatch_shared_local_bytes;
                group_other_state_units_q[free_group_index] <= dispatch_other_workgroup_state_units;
                for (seq_local_wave = 0; seq_local_wave < RESIDENT_WAVE_SLOTS; seq_local_wave = seq_local_wave + 1) begin
                    if (seq_local_wave < $unsigned(dispatch_wave_count)) begin
                        seq_slot = planned_wave_slot[seq_local_wave];
                        resident_wave_mask[seq_slot] <= 1'b1;
                        slot_group_context_q[seq_slot] <= free_group_index[WORKGROUP_CONTEXT_WIDTH-1:0];
                        slot_local_wave_q[seq_slot] <= seq_local_wave[LOCAL_WAVE_WIDTH-1:0];
                        slot_vgpr_row_base_q[seq_slot] <= planned_row_base[seq_local_wave][ROW_WIDTH-1:0];
                        slot_vgpr_row_count_q[seq_slot] <= rows_per_wave[ROW_COUNT_WIDTH-1:0];
                        slot_scalar_state_units_q[seq_slot] <= dispatch_scalar_state_units_per_wave;
                    end
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (RESIDENT_WAVE_SLOTS < 1 || PHYSICAL_VGPR_ROWS < 1
            || MAX_WORKGROUP_CONTEXTS < 1) begin
            $fatal(1, "workgroup residency capacities must be nonzero");
        end
        if ((1 << WAVE_SLOT_WIDTH) < RESIDENT_WAVE_SLOTS
            || (1 << LOCAL_WAVE_WIDTH) < RESIDENT_WAVE_SLOTS
            || (1 << ROW_WIDTH) < PHYSICAL_VGPR_ROWS
            || (1 << ROW_COUNT_WIDTH) <= PHYSICAL_VGPR_ROWS
            || (1 << WORKGROUP_CONTEXT_WIDTH) < MAX_WORKGROUP_CONTEXTS
            || (1 << WAVE_COUNT_WIDTH) <= RESIDENT_WAVE_SLOTS) begin
            $fatal(1, "workgroup residency index width is undersized");
        end
    end
`endif

endmodule
