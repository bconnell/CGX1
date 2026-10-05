// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Barrier membership only. Physical wave slots and VGPR allocations are owned
// by the pooled allocator composed by cgx1_compute_workgroup_execution_frontend.
module cgx1_workgroup_residency_barrier #(
    parameter integer RESIDENT_WAVE_SLOTS = 8,
    parameter integer MAX_WORKGROUP_CONTEXTS = 4,
    parameter integer SCALAR_PREDICATE_STATE_UNITS = 128,
    parameter integer SHARED_LOCAL_MEMORY_BYTES = 4096,
    parameter integer OTHER_WORKGROUP_STATE_UNITS = 128,
    parameter integer WORKGROUP_ID_WIDTH = 16,
    parameter integer WAVE_SLOT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS),
    parameter integer LOCAL_WAVE_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS),
    parameter integer WORKGROUP_CONTEXT_WIDTH = (MAX_WORKGROUP_CONTEXTS <= 1) ? 1 : $clog2(MAX_WORKGROUP_CONTEXTS),
    parameter integer WAVE_COUNT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS + 1)
) (
    input logic clk,
    input logic reset_n,

    input logic commit_valid,
    input logic [WORKGROUP_ID_WIDTH-1:0] commit_workgroup_id,
    input logic [WAVE_COUNT_WIDTH-1:0] commit_wave_count,
    input logic [(RESIDENT_WAVE_SLOTS*WAVE_SLOT_WIDTH)-1:0] commit_wave_slot_map_flat,
    input logic [15:0] commit_scalar_state_units_per_wave,
    input logic [31:0] commit_shared_local_bytes,
    input logic [31:0] commit_other_workgroup_state_units,
    output logic commit_ready,
    output logic commit_accepted,

    input logic barrier_arrive_valid,
    input logic [WORKGROUP_ID_WIDTH-1:0] barrier_arrive_workgroup_id,
    input logic [RESIDENT_WAVE_SLOTS-1:0] barrier_arrive_local_wave_mask,
    input logic [RESIDENT_WAVE_SLOTS-1:0] wave_execution_busy,
    input logic [RESIDENT_WAVE_SLOTS-1:0] wave_control_reconverged,
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

    input logic [RESIDENT_WAVE_SLOTS-1:0] allocator_release_accepted_mask,

    input logic [WORKGROUP_ID_WIDTH-1:0] query_workgroup_id,
    output logic query_workgroup_found,
    output logic [WAVE_COUNT_WIDTH-1:0] query_workgroup_wave_count,
    output logic [RESIDENT_WAVE_SLOTS-1:0] query_workgroup_live_waves,
    output logic [RESIDENT_WAVE_SLOTS-1:0] query_workgroup_arrived_waves,
    output logic [31:0] query_barrier_generation,

    output logic [RESIDENT_WAVE_SLOTS-1:0] resident_wave_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] live_wave_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] barrier_waiting_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] issuable_wave_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] release_pending_wave_mask,
    output logic [MAX_WORKGROUP_CONTEXTS-1:0] workgroup_active_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] final_wave_release_mask,
    output logic [(RESIDENT_WAVE_SLOTS*WORKGROUP_ID_WIDTH)-1:0] slot_workgroup_id_flat,
    output logic [WAVE_COUNT_WIDTH-1:0] resident_wave_count,
    output logic [31:0] scalar_state_units_used,
    output logic [31:0] shared_local_bytes_used,
    output logic [63:0] other_workgroup_state_units_used
);

    logic [MAX_WORKGROUP_CONTEXTS-1:0] group_active_q;
    logic [WORKGROUP_ID_WIDTH-1:0] group_id_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [WAVE_COUNT_WIDTH-1:0] group_wave_count_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [RESIDENT_WAVE_SLOTS-1:0] group_owned_local_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [RESIDENT_WAVE_SLOTS-1:0] group_live_local_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [RESIDENT_WAVE_SLOTS-1:0] group_arrived_local_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [31:0] group_barrier_generation_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [15:0] group_scalar_units_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [31:0] group_shared_bytes_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [31:0] group_other_units_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [RESIDENT_WAVE_SLOTS-1:0] slot_owned_q;
    logic [WORKGROUP_CONTEXT_WIDTH-1:0] slot_group_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [LOCAL_WAVE_WIDTH-1:0] slot_local_q [0:RESIDENT_WAVE_SLOTS-1];

    integer free_group_index;
    integer duplicate_group_index;
    integer arrival_group_index;
    integer abort_group_index;
    integer terminate_group_index;
    integer used_scalar;
    integer used_shared;
    logic [63:0] used_other;
    integer owned_count;
    logic [RESIDENT_WAVE_SLOTS-1:0] commit_slots_seen;
    logic commit_slots_valid;
    logic [RESIDENT_WAVE_SLOTS-1:0] arrived_after_terminate;
    logic [RESIDENT_WAVE_SLOTS-1:0] live_after_terminate;

    always_comb begin : wave_state_projection
        integer slot_index;
        integer group_index;
        integer local_index;
        resident_wave_mask = slot_owned_q;
        slot_workgroup_id_flat = '0;
        live_wave_mask = '0;
        barrier_waiting_mask = '0;
        group_index = 0;
        local_index = 0;

        for (slot_index = 0; slot_index < RESIDENT_WAVE_SLOTS; slot_index = slot_index + 1) begin
            if (slot_owned_q[slot_index]) begin
                local_index = int'($unsigned(slot_local_q[slot_index]));
                group_index = int'($unsigned(slot_group_q[slot_index]));
                if (group_active_q[group_index]) begin
                    slot_workgroup_id_flat[(slot_index*WORKGROUP_ID_WIDTH)
                        +: WORKGROUP_ID_WIDTH] = group_id_q[group_index];
                    if (group_live_local_q[group_index][local_index]) begin
                        live_wave_mask[slot_index] = 1'b1;
                        if (group_arrived_local_q[group_index][local_index])
                            barrier_waiting_mask[slot_index] = 1'b1;
                    end
                end
            end
        end
    end

    always_comb begin : control_decode
        integer group_index;
        integer slot_index;
        integer local_index;
        integer mapped_slot;
        local_index = 0;
        mapped_slot = 0;
        free_group_index = -1;
        duplicate_group_index = -1;
        arrival_group_index = -1;
        abort_group_index = -1;
        terminate_group_index = -1;
        used_scalar = 0;
        used_shared = 0;
        used_other = 0;
        owned_count = 0;
        issuable_wave_mask = '0;
        release_pending_wave_mask = '0;
        workgroup_active_mask = group_active_q;
        commit_slots_seen = '0;
        commit_slots_valid = 1'b1;

        for (group_index = 0; group_index < MAX_WORKGROUP_CONTEXTS; group_index = group_index + 1) begin
            if (group_active_q[group_index]) begin
                if (group_id_q[group_index] == commit_workgroup_id)
                    duplicate_group_index = group_index;
                if (group_id_q[group_index] == barrier_arrive_workgroup_id)
                    arrival_group_index = group_index;
                if (group_id_q[group_index] == workgroup_abort_id)
                    abort_group_index = group_index;
                used_scalar = used_scalar
                    + CountOnes(group_owned_local_q[group_index]) * group_scalar_units_q[group_index];
                used_shared = used_shared + group_shared_bytes_q[group_index];
                used_other = used_other + 64'($unsigned(group_other_units_q[group_index]));
            end else if (free_group_index < 0) begin
                free_group_index = group_index;
            end
        end

        for (slot_index = 0; slot_index < RESIDENT_WAVE_SLOTS; slot_index = slot_index + 1) begin
            if (slot_owned_q[slot_index]) begin
                owned_count = owned_count + 1;
                local_index = int'($unsigned(slot_local_q[slot_index]));
                group_index = int'($unsigned(slot_group_q[slot_index]));
                if (group_active_q[group_index]) begin
                    if (group_live_local_q[group_index][local_index]) begin
                        if (!group_arrived_local_q[group_index][local_index])
                            issuable_wave_mask[slot_index] = 1'b1;
                    end else begin
                        release_pending_wave_mask[slot_index] = 1'b1;
                    end
                end
            end
        end
        if (terminate_wave_valid && (int'($unsigned(terminate_wave_slot)) < RESIDENT_WAVE_SLOTS)
            && slot_owned_q[terminate_wave_slot]) begin
            terminate_group_index = int'($unsigned(slot_group_q[terminate_wave_slot]));
        end

        for (local_index = 0; local_index < RESIDENT_WAVE_SLOTS; local_index = local_index + 1) begin
            if (local_index < int'($unsigned(commit_wave_count))) begin
                mapped_slot = int'($unsigned(commit_wave_slot_map_flat[(local_index*WAVE_SLOT_WIDTH) +: WAVE_SLOT_WIDTH]));
                if (mapped_slot >= RESIDENT_WAVE_SLOTS) begin
                    commit_slots_valid = 1'b0;
                end else begin
                    if (commit_slots_seen[mapped_slot] || slot_owned_q[mapped_slot]) begin
                        commit_slots_valid = 1'b0;
                    end else begin
                        commit_slots_seen[mapped_slot] = 1'b1;
                    end
                end
            end
        end

        commit_ready = (free_group_index >= 0) && (duplicate_group_index < 0)
            && (commit_wave_count != 0)
            && (int'($unsigned(commit_wave_count)) <= RESIDENT_WAVE_SLOTS)
            && commit_slots_valid;
        commit_accepted = commit_valid && commit_ready;

        workgroup_abort_ready = (abort_group_index >= 0);
        workgroup_abort_accepted = workgroup_abort_valid && workgroup_abort_ready;
        terminate_wave_ready = 1'b0;
        if ((terminate_group_index >= 0) && (terminate_wave_reason != 2'b11)
            && !workgroup_abort_accepted)
            terminate_wave_ready = group_live_local_q[terminate_group_index]
                [int'($unsigned(slot_local_q[terminate_wave_slot]))];
        terminate_wave_accepted = terminate_wave_valid && terminate_wave_ready;

        barrier_arrive_ready = 1'b0;
        if ((arrival_group_index >= 0) && (barrier_arrive_local_wave_mask != '0)
            && !workgroup_abort_accepted && !terminate_wave_accepted) begin
            barrier_arrive_ready = 1'b1;
            for (local_index = 0; local_index < RESIDENT_WAVE_SLOTS; local_index = local_index + 1) begin
                if (barrier_arrive_local_wave_mask[local_index]) begin
                    mapped_slot = -1;
                    for (slot_index = 0; slot_index < RESIDENT_WAVE_SLOTS; slot_index = slot_index + 1) begin
                        if (slot_owned_q[slot_index]
                            && (int'($unsigned(slot_group_q[slot_index])) == arrival_group_index)
                            && (int'($unsigned(slot_local_q[slot_index])) == local_index))
                            mapped_slot = slot_index;
                    end
                    if (!group_live_local_q[arrival_group_index][local_index]
                        || group_arrived_local_q[arrival_group_index][local_index]
                        || (mapped_slot < 0))
                        barrier_arrive_ready = 1'b0;
                    else if (wave_execution_busy[mapped_slot]
                        || !wave_control_reconverged[mapped_slot])
                        barrier_arrive_ready = 1'b0;
                end
            end
        end
        barrier_arrive_accepted = barrier_arrive_valid && barrier_arrive_ready;

        if (terminate_wave_accepted)
            issuable_wave_mask[terminate_wave_slot] = 1'b0;
        if (workgroup_abort_accepted) begin
            for (slot_index = 0; slot_index < RESIDENT_WAVE_SLOTS; slot_index = slot_index + 1) begin
                if (slot_owned_q[slot_index]
                    && (int'($unsigned(slot_group_q[slot_index])) == abort_group_index))
                    issuable_wave_mask[slot_index] = 1'b0;
            end
        end

        arrived_after_terminate = '0;
        live_after_terminate = '0;
        if (terminate_wave_accepted) begin
            live_after_terminate = group_live_local_q[terminate_group_index]
                & ~(RESIDENT_WAVE_SLOTS'(1'b1) << slot_local_q[terminate_wave_slot]);
            arrived_after_terminate = group_arrived_local_q[terminate_group_index]
                & live_after_terminate;
        end

        resident_wave_count = owned_count[WAVE_COUNT_WIDTH-1:0];
        scalar_state_units_used = used_scalar;
        shared_local_bytes_used = used_shared;
        other_workgroup_state_units_used = used_other;
    end

    always_comb begin : final_wave_release_decode
        integer slot_index;
        integer group_index;
        final_wave_release_mask = '0;
        group_index = 0;
        for (slot_index = 0; slot_index < RESIDENT_WAVE_SLOTS; slot_index = slot_index + 1) begin
            if (slot_owned_q[slot_index]
                && (int'($unsigned(slot_group_q[slot_index])) < MAX_WORKGROUP_CONTEXTS)) begin
                group_index = int'($unsigned(slot_group_q[slot_index]));
                if (group_active_q[group_index]
                    && (group_live_local_q[group_index] == '0)
                    && (CountOnes(group_owned_local_q[group_index]) == 1))
                    final_wave_release_mask[slot_index] = 1'b1;
            end
        end
    end

    always_comb begin : query_decode
        integer group_index;
        query_workgroup_found = 1'b0;
        query_workgroup_wave_count = '0;
        query_workgroup_live_waves = '0;
        query_workgroup_arrived_waves = '0;
        query_barrier_generation = '0;
        for (group_index = 0; group_index < MAX_WORKGROUP_CONTEXTS; group_index = group_index + 1) begin
            if (!query_workgroup_found && group_active_q[group_index]
                && (group_id_q[group_index] == query_workgroup_id)) begin
                query_workgroup_found = 1'b1;
                query_workgroup_wave_count = group_wave_count_q[group_index];
                query_workgroup_live_waves = group_live_local_q[group_index];
                query_workgroup_arrived_waves = group_arrived_local_q[group_index];
                query_barrier_generation = group_barrier_generation_q[group_index];
            end
        end
    end

    integer reset_group;
    integer reset_slot;
    integer state_group;
    integer state_local;
    integer state_slot;
    integer release_group;
    integer release_slot;
    integer release_local;
    integer release_count;
    logic [RESIDENT_WAVE_SLOTS-1:0] released_local_mask [0:MAX_WORKGROUP_CONTEXTS-1];
    always_comb begin
        integer group_index;
        integer slot_index;
        integer local_index;
        group_index = 0;
        slot_index = 0;
        local_index = 0;
        for (group_index = 0; group_index < MAX_WORKGROUP_CONTEXTS; group_index = group_index + 1)
            released_local_mask[group_index] = '0;
        for (slot_index = 0; slot_index < RESIDENT_WAVE_SLOTS; slot_index = slot_index + 1) begin
            if (allocator_release_accepted_mask[slot_index] && slot_owned_q[slot_index]) begin
                group_index = int'($unsigned(slot_group_q[slot_index]));
                local_index = int'($unsigned(slot_local_q[slot_index]));
                released_local_mask[group_index][local_index] = 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            group_active_q <= '0;
            slot_owned_q <= '0;
            barrier_release_valid <= 1'b0;
            barrier_release_workgroup_id <= '0;
            barrier_release_generation <= '0;
            barrier_release_wave_mask <= '0;
            for (reset_group = 0; reset_group < MAX_WORKGROUP_CONTEXTS; reset_group = reset_group + 1) begin
                group_id_q[reset_group] <= '0;
                group_wave_count_q[reset_group] <= '0;
                group_owned_local_q[reset_group] <= '0;
                group_live_local_q[reset_group] <= '0;
                group_arrived_local_q[reset_group] <= '0;
                group_barrier_generation_q[reset_group] <= '0;
                group_scalar_units_q[reset_group] <= '0;
                group_shared_bytes_q[reset_group] <= '0;
                group_other_units_q[reset_group] <= '0;
            end
            for (reset_slot = 0; reset_slot < RESIDENT_WAVE_SLOTS; reset_slot = reset_slot + 1) begin
                slot_group_q[reset_slot] <= '0;
                slot_local_q[reset_slot] <= '0;
            end
        end else begin
            barrier_release_valid <= 1'b0;
            barrier_release_workgroup_id <= '0;
            barrier_release_generation <= '0;
            barrier_release_wave_mask <= '0;

            for (state_group = 0; state_group < MAX_WORKGROUP_CONTEXTS; state_group = state_group + 1) begin
                if (group_active_q[state_group] && (released_local_mask[state_group] != '0)) begin
                    group_owned_local_q[state_group] <= group_owned_local_q[state_group]
                        & ~released_local_mask[state_group];
                    if ((group_owned_local_q[state_group] & ~released_local_mask[state_group]) == '0) begin
                        group_active_q[state_group] <= 1'b0;
                        group_wave_count_q[state_group] <= '0;
                        group_live_local_q[state_group] <= '0;
                        group_arrived_local_q[state_group] <= '0;
                        group_scalar_units_q[state_group] <= '0;
                        group_shared_bytes_q[state_group] <= '0;
                        group_other_units_q[state_group] <= '0;
                    end
                end
            end
            for (state_slot = 0; state_slot < RESIDENT_WAVE_SLOTS; state_slot = state_slot + 1) begin
                if (allocator_release_accepted_mask[state_slot] && slot_owned_q[state_slot]) begin
                    slot_owned_q[state_slot] <= 1'b0;
                    slot_group_q[state_slot] <= '0;
                    slot_local_q[state_slot] <= '0;
                end
            end

            if (workgroup_abort_accepted) begin
                group_live_local_q[abort_group_index] <= '0;
                group_arrived_local_q[abort_group_index] <= '0;
            end else if (terminate_wave_accepted) begin
                if (live_after_terminate == '0) begin
                    group_live_local_q[terminate_group_index] <= '0;
                    group_arrived_local_q[terminate_group_index] <= '0;
                end else if (arrived_after_terminate == live_after_terminate) begin
                    group_live_local_q[terminate_group_index] <= live_after_terminate;
                    group_arrived_local_q[terminate_group_index] <= '0;
                    barrier_release_valid <= 1'b1;
                    barrier_release_workgroup_id <= group_id_q[terminate_group_index];
                    barrier_release_generation <= group_barrier_generation_q[terminate_group_index];
                    group_barrier_generation_q[terminate_group_index]
                        <= group_barrier_generation_q[terminate_group_index] + 1'b1;
                    for (state_slot = 0; state_slot < RESIDENT_WAVE_SLOTS; state_slot = state_slot + 1) begin
                        if (slot_owned_q[state_slot]
                            && (int'($unsigned(slot_group_q[state_slot])) == terminate_group_index)
                            && live_after_terminate[slot_local_q[state_slot]]
                            && group_arrived_local_q[terminate_group_index][slot_local_q[state_slot]])
                            barrier_release_wave_mask[state_slot] <= 1'b1;
                    end
                end else begin
                    group_live_local_q[terminate_group_index] <= live_after_terminate;
                    group_arrived_local_q[terminate_group_index] <= arrived_after_terminate;
                end
            end else if (barrier_arrive_accepted) begin
                if (((group_arrived_local_q[arrival_group_index] | barrier_arrive_local_wave_mask)
                    & group_live_local_q[arrival_group_index]) == group_live_local_q[arrival_group_index]) begin
                    group_arrived_local_q[arrival_group_index] <= '0;
                    group_barrier_generation_q[arrival_group_index]
                        <= group_barrier_generation_q[arrival_group_index] + 1'b1;
                    barrier_release_valid <= 1'b1;
                    barrier_release_workgroup_id <= group_id_q[arrival_group_index];
                    barrier_release_generation <= group_barrier_generation_q[arrival_group_index];
                    for (state_slot = 0; state_slot < RESIDENT_WAVE_SLOTS; state_slot = state_slot + 1) begin
                        if (slot_owned_q[state_slot]
                            && (int'($unsigned(slot_group_q[state_slot])) == arrival_group_index)
                            && group_live_local_q[arrival_group_index][slot_local_q[state_slot]])
                            barrier_release_wave_mask[state_slot] <= 1'b1;
                    end
                end else begin
                    group_arrived_local_q[arrival_group_index] <=
                        group_arrived_local_q[arrival_group_index] | barrier_arrive_local_wave_mask;
                end
            end

            if (commit_accepted) begin
                group_active_q[free_group_index] <= 1'b1;
                group_id_q[free_group_index] <= commit_workgroup_id;
                group_wave_count_q[free_group_index] <= commit_wave_count;
                group_owned_local_q[free_group_index] <= {RESIDENT_WAVE_SLOTS{1'b1}}
                    >> (RESIDENT_WAVE_SLOTS - int'($unsigned(commit_wave_count)));
                group_live_local_q[free_group_index] <= {RESIDENT_WAVE_SLOTS{1'b1}}
                    >> (RESIDENT_WAVE_SLOTS - int'($unsigned(commit_wave_count)));
                group_arrived_local_q[free_group_index] <= '0;
                group_barrier_generation_q[free_group_index] <= '0;
                group_scalar_units_q[free_group_index] <= commit_scalar_state_units_per_wave;
                group_shared_bytes_q[free_group_index] <= commit_shared_local_bytes;
                group_other_units_q[free_group_index] <= commit_other_workgroup_state_units;
                for (state_local = 0; state_local < RESIDENT_WAVE_SLOTS; state_local = state_local + 1) begin
                    if (state_local < int'($unsigned(commit_wave_count))) begin
                        state_slot = int'($unsigned(commit_wave_slot_map_flat[(state_local*WAVE_SLOT_WIDTH) +: WAVE_SLOT_WIDTH]));
                        slot_owned_q[state_slot] <= 1'b1;
                        slot_group_q[state_slot] <= free_group_index[WORKGROUP_CONTEXT_WIDTH-1:0];
                        slot_local_q[state_slot] <= state_local[LOCAL_WAVE_WIDTH-1:0];
                    end
                end
            end
        end
    end

    function automatic integer CountOnes(input logic [RESIDENT_WAVE_SLOTS-1:0] value);
        integer bit_index;
        begin
            CountOnes = 0;
            for (bit_index = 0; bit_index < RESIDENT_WAVE_SLOTS; bit_index = bit_index + 1)
                CountOnes = CountOnes + value[bit_index];
        end
    endfunction

`ifndef SYNTHESIS
    initial begin
        if (RESIDENT_WAVE_SLOTS < 1 || MAX_WORKGROUP_CONTEXTS < 1)
            $fatal(1, "workgroup barrier capacities must be nonzero");
        if ((1 << WAVE_SLOT_WIDTH) < RESIDENT_WAVE_SLOTS
            || (1 << LOCAL_WAVE_WIDTH) < RESIDENT_WAVE_SLOTS
            || (1 << WORKGROUP_CONTEXT_WIDTH) < MAX_WORKGROUP_CONTEXTS
            || (1 << WAVE_COUNT_WIDTH) <= RESIDENT_WAVE_SLOTS)
            $fatal(1, "workgroup barrier index width is undersized");
    end
`endif
endmodule
