// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Tracks decoded commands from CU admission through authoritative workgroup retirement.
`timescale 1ns/1ps
module cgx1_compute_workgroup_command_lifecycle #(
    parameter integer QUEUE_CONTEXT_COUNT = 64,
    parameter integer COMMAND_SLOTS = 32,
    parameter integer WORKGROUP_ID_WIDTH = 16,
    parameter integer COMMAND_SLOT_WIDTH = (COMMAND_SLOTS <= 1)
        ? 1 : $clog2(COMMAND_SLOTS),
    parameter integer TRACKED_COUNT_WIDTH = (COMMAND_SLOTS <= 1)
        ? 1 : $clog2(COMMAND_SLOTS + 1)
) (
    input logic clk,
    input logic reset_n,

    // The scheduler gates its accepted-submit handshake with this capacity.
    input logic submit_accepted_valid,
    output logic submit_capacity_ready,
    input logic [5:0] submit_queue_context_id,
    input logic [63:0] submit_process_id,
    input logic [63:0] submit_address_space_id,
    input logic [WORKGROUP_ID_WIDTH-1:0] submit_workgroup_id,
    input logic [63:0] submit_submission_id,
    input logic [63:0] submit_packet_byte_position,
    input logic [63:0] submit_queue_incarnation_id,

    // This is the scheduler's existing admission-result channel.
    input logic admission_valid,
    output logic admission_ready,
    input logic [5:0] admission_queue_context_id,
    input logic [63:0] admission_process_id,
    input logic [63:0] admission_address_space_id,
    input logic [WORKGROUP_ID_WIDTH-1:0] admission_workgroup_id,
    input logic [63:0] admission_submission_id,
    input logic [63:0] admission_packet_byte_position,
    input logic [63:0] admission_queue_incarnation_id,
    input logic [2:0] admission_status,
    input logic [4:0] admission_failure,

    input logic [QUEUE_CONTEXT_COUNT-1:0] cancelled_queue_mask,

    input logic workgroup_retire_valid,
    output logic workgroup_retire_ready,
    input logic [WORKGROUP_ID_WIDTH-1:0] workgroup_retire_id,

    output logic workgroup_abort_valid,
    input logic workgroup_abort_ready,
    output logic [WORKGROUP_ID_WIDTH-1:0] workgroup_abort_id,

    // Final command completion is separate from parser and admission results.
    output logic completion_valid,
    input logic completion_ready,
    output logic [5:0] completion_queue_context_id,
    output logic [63:0] completion_process_id,
    output logic [63:0] completion_address_space_id,
    output logic [WORKGROUP_ID_WIDTH-1:0] completion_workgroup_id,
    output logic [63:0] completion_submission_id,
    output logic [63:0] completion_packet_byte_position,
    output logic [63:0] completion_queue_incarnation_id,
    output logic [2:0] completion_status,
    output logic [4:0] completion_failure,

    output logic [QUEUE_CONTEXT_COUNT-1:0] queue_drained_mask,
    output logic [TRACKED_COUNT_WIDTH-1:0] tracked_count
);
    localparam logic [2:0] ENTRY_FREE = 3'd0;
    localparam logic [2:0] ENTRY_WAIT_ADMISSION = 3'd1;
    localparam logic [2:0] ENTRY_RESIDENT = 3'd2;
    localparam logic [2:0] ENTRY_ABORT = 3'd3;
    localparam logic [2:0] ENTRY_WAIT_RETIRE = 3'd4;
    localparam logic [2:0] ENTRY_COMPLETE = 3'd5;

    logic [2:0] entry_state_q [0:COMMAND_SLOTS-1];
    logic [5:0] entry_queue_context_id_q [0:COMMAND_SLOTS-1];
    logic [63:0] entry_process_id_q [0:COMMAND_SLOTS-1];
    logic [63:0] entry_address_space_id_q [0:COMMAND_SLOTS-1];
    logic [WORKGROUP_ID_WIDTH-1:0] entry_workgroup_id_q [0:COMMAND_SLOTS-1];
    logic [63:0] entry_submission_id_q [0:COMMAND_SLOTS-1];
    logic [63:0] entry_packet_byte_position_q [0:COMMAND_SLOTS-1];
    logic [63:0] entry_queue_incarnation_id_q [0:COMMAND_SLOTS-1];
    logic entry_cancel_requested_q [0:COMMAND_SLOTS-1];
    logic [2:0] entry_completion_status_q [0:COMMAND_SLOTS-1];
    logic [4:0] entry_completion_failure_q [0:COMMAND_SLOTS-1];

    logic abort_hold_valid_q;
    logic [COMMAND_SLOT_WIDTH-1:0] abort_hold_slot_q;
    logic completion_hold_valid_q;
    logic [COMMAND_SLOT_WIDTH-1:0] completion_hold_slot_q;

    integer free_slot_index;
    integer admission_match_index;
    integer retire_match_index;
    integer abort_candidate_index;
    integer abort_selected_index;
    integer completion_candidate_index;
    integer completion_selected_index;
    integer tracked_count_integer;
    integer comb_slot;
    integer seq_slot;
    logic retire_matches_admission;
    logic duplicate_submit_found;

    always_comb begin : lifecycle_arbitration
        free_slot_index = -1;
        admission_match_index = -1;
        retire_match_index = -1;
        abort_candidate_index = -1;
        abort_selected_index = -1;
        completion_candidate_index = -1;
        completion_selected_index = -1;
        tracked_count_integer = 0;
        duplicate_submit_found = 1'b0;
        queue_drained_mask = {QUEUE_CONTEXT_COUNT{1'b1}};

        for (comb_slot = 0; comb_slot < COMMAND_SLOTS; comb_slot = comb_slot + 1) begin
            if (entry_state_q[comb_slot] == ENTRY_FREE) begin
                if (free_slot_index < 0)
                    free_slot_index = comb_slot;
            end else begin
                tracked_count_integer = tracked_count_integer + 1;
                if (entry_queue_context_id_q[comb_slot] < QUEUE_CONTEXT_COUNT)
                    queue_drained_mask[entry_queue_context_id_q[comb_slot]] = 1'b0;
            end

            if (admission_match_index < 0
                && entry_state_q[comb_slot] == ENTRY_WAIT_ADMISSION
                && entry_queue_context_id_q[comb_slot] == admission_queue_context_id
                && entry_process_id_q[comb_slot] == admission_process_id
                && entry_address_space_id_q[comb_slot] == admission_address_space_id
                && entry_workgroup_id_q[comb_slot] == admission_workgroup_id
                && entry_submission_id_q[comb_slot] == admission_submission_id
                && entry_packet_byte_position_q[comb_slot] == admission_packet_byte_position
                && entry_queue_incarnation_id_q[comb_slot] == admission_queue_incarnation_id)
                admission_match_index = comb_slot;

            if (retire_match_index < 0
                && (entry_state_q[comb_slot] == ENTRY_RESIDENT
                    || entry_state_q[comb_slot] == ENTRY_ABORT
                    || entry_state_q[comb_slot] == ENTRY_WAIT_RETIRE)
                && entry_workgroup_id_q[comb_slot] == workgroup_retire_id)
                retire_match_index = comb_slot;

            if (abort_candidate_index < 0
                && entry_state_q[comb_slot] == ENTRY_ABORT)
                abort_candidate_index = comb_slot;

            if (completion_candidate_index < 0
                && entry_state_q[comb_slot] == ENTRY_COMPLETE)
                completion_candidate_index = comb_slot;
        end

        abort_selected_index = abort_candidate_index;
        if (abort_hold_valid_q
            && entry_state_q[abort_hold_slot_q] == ENTRY_ABORT)
            abort_selected_index = $unsigned(abort_hold_slot_q);

        completion_selected_index = completion_candidate_index;
        if (completion_hold_valid_q
            && entry_state_q[completion_hold_slot_q] == ENTRY_COMPLETE)
            completion_selected_index = $unsigned(completion_hold_slot_q);

        retire_matches_admission = 1'b0;
        if (workgroup_retire_valid && (retire_match_index < 0)
            && admission_valid && (admission_match_index >= 0)
            && admission_status == 3'd0
            && entry_workgroup_id_q[admission_match_index] == workgroup_retire_id)
            retire_matches_admission = 1'b1;

        for (comb_slot = 0; comb_slot < COMMAND_SLOTS; comb_slot = comb_slot + 1) begin
            if (entry_state_q[comb_slot] != ENTRY_FREE
                && entry_queue_context_id_q[comb_slot] == submit_queue_context_id
                && entry_process_id_q[comb_slot] == submit_process_id
                && entry_address_space_id_q[comb_slot] == submit_address_space_id
                && entry_workgroup_id_q[comb_slot] == submit_workgroup_id
                && entry_submission_id_q[comb_slot] == submit_submission_id
                && entry_packet_byte_position_q[comb_slot] == submit_packet_byte_position
                && entry_queue_incarnation_id_q[comb_slot] == submit_queue_incarnation_id)
                duplicate_submit_found = 1'b1;
        end

        submit_capacity_ready = reset_n && (free_slot_index >= 0)
            && (submit_queue_context_id < QUEUE_CONTEXT_COUNT)
            && !duplicate_submit_found;
        admission_ready = reset_n;
        workgroup_retire_ready = reset_n;

        workgroup_abort_valid = (abort_selected_index >= 0);
        workgroup_abort_id = '0;
        if (abort_selected_index >= 0)
            workgroup_abort_id = entry_workgroup_id_q[abort_selected_index];

        completion_valid = (completion_selected_index >= 0);
        completion_queue_context_id = '0;
        completion_process_id = '0;
        completion_address_space_id = '0;
        completion_workgroup_id = '0;
        completion_submission_id = '0;
        completion_packet_byte_position = '0;
        completion_queue_incarnation_id = '0;
        completion_status = '0;
        completion_failure = '0;
        if (completion_selected_index >= 0) begin
            completion_queue_context_id = entry_queue_context_id_q[completion_selected_index];
            completion_process_id = entry_process_id_q[completion_selected_index];
            completion_address_space_id = entry_address_space_id_q[completion_selected_index];
            completion_workgroup_id = entry_workgroup_id_q[completion_selected_index];
            completion_submission_id = entry_submission_id_q[completion_selected_index];
            completion_packet_byte_position = entry_packet_byte_position_q[completion_selected_index];
            completion_queue_incarnation_id = entry_queue_incarnation_id_q[completion_selected_index];
            completion_status = entry_completion_status_q[completion_selected_index];
            completion_failure = entry_completion_failure_q[completion_selected_index];
        end

        tracked_count = tracked_count_integer[TRACKED_COUNT_WIDTH-1:0];
    end

    always_ff @(posedge clk or negedge reset_n) begin : lifecycle_state
        if (!reset_n) begin
            abort_hold_valid_q <= 1'b0;
            abort_hold_slot_q <= '0;
            completion_hold_valid_q <= 1'b0;
            completion_hold_slot_q <= '0;
            for (seq_slot = 0; seq_slot < COMMAND_SLOTS; seq_slot = seq_slot + 1) begin
                entry_state_q[seq_slot] <= ENTRY_FREE;
                entry_queue_context_id_q[seq_slot] <= '0;
                entry_process_id_q[seq_slot] <= '0;
                entry_address_space_id_q[seq_slot] <= '0;
                entry_workgroup_id_q[seq_slot] <= '0;
                entry_submission_id_q[seq_slot] <= '0;
                entry_packet_byte_position_q[seq_slot] <= '0;
                entry_queue_incarnation_id_q[seq_slot] <= '0;
                entry_cancel_requested_q[seq_slot] <= 1'b0;
                entry_completion_status_q[seq_slot] <= '0;
                entry_completion_failure_q[seq_slot] <= '0;
            end
        end else begin
            if (submit_accepted_valid) begin
                if (free_slot_index < 0 || submit_queue_context_id >= QUEUE_CONTEXT_COUNT)
                    $fatal(1, "accepted command has no lifecycle slot or valid queue context");
                if (duplicate_submit_found)
                    $fatal(1, "duplicate command identity entered lifecycle tracking");
                entry_state_q[free_slot_index] <= ENTRY_WAIT_ADMISSION;
                entry_queue_context_id_q[free_slot_index] <= submit_queue_context_id;
                entry_process_id_q[free_slot_index] <= submit_process_id;
                entry_address_space_id_q[free_slot_index] <= submit_address_space_id;
                entry_workgroup_id_q[free_slot_index] <= submit_workgroup_id;
                entry_submission_id_q[free_slot_index] <= submit_submission_id;
                entry_packet_byte_position_q[free_slot_index] <= submit_packet_byte_position;
                entry_queue_incarnation_id_q[free_slot_index] <= submit_queue_incarnation_id;
                entry_cancel_requested_q[free_slot_index]
                    <= cancelled_queue_mask[submit_queue_context_id];
                entry_completion_status_q[free_slot_index] <= '0;
                entry_completion_failure_q[free_slot_index] <= '0;
            end

            for (seq_slot = 0; seq_slot < COMMAND_SLOTS; seq_slot = seq_slot + 1) begin
                if (entry_state_q[seq_slot] != ENTRY_FREE
                    && entry_state_q[seq_slot] != ENTRY_COMPLETE
                    && entry_queue_context_id_q[seq_slot] < QUEUE_CONTEXT_COUNT
                    && cancelled_queue_mask[entry_queue_context_id_q[seq_slot]]) begin
                    entry_cancel_requested_q[seq_slot] <= 1'b1;
                    if (entry_state_q[seq_slot] == ENTRY_RESIDENT)
                        entry_state_q[seq_slot] <= ENTRY_ABORT;
                end
            end

            if (admission_valid && admission_ready && (admission_match_index >= 0)) begin
                if (entry_cancel_requested_q[admission_match_index]
                    || cancelled_queue_mask[entry_queue_context_id_q[admission_match_index]]) begin
                    if (admission_status == 3'd0) begin
                        if (retire_matches_admission) begin
                            entry_state_q[admission_match_index] <= ENTRY_COMPLETE;
                            entry_completion_status_q[admission_match_index] <= 3'd4;
                            entry_completion_failure_q[admission_match_index] <= '0;
                        end else begin
                            entry_state_q[admission_match_index] <= ENTRY_ABORT;
                            entry_cancel_requested_q[admission_match_index] <= 1'b1;
                        end
                    end else begin
                        entry_state_q[admission_match_index] <= ENTRY_COMPLETE;
                        entry_completion_status_q[admission_match_index] <= 3'd4;
                        entry_completion_failure_q[admission_match_index] <= '0;
                    end
                end else if (admission_status == 3'd0) begin
                    if (retire_matches_admission) begin
                        entry_state_q[admission_match_index] <= ENTRY_COMPLETE;
                        entry_completion_status_q[admission_match_index] <= 3'd0;
                        entry_completion_failure_q[admission_match_index] <= '0;
                    end else begin
                        entry_state_q[admission_match_index] <= ENTRY_RESIDENT;
                    end
                end else begin
                    entry_state_q[admission_match_index] <= ENTRY_COMPLETE;
                    entry_completion_status_q[admission_match_index] <= admission_status;
                    entry_completion_failure_q[admission_match_index] <= admission_failure;
                end
            end

            if (workgroup_abort_valid) begin
                if (workgroup_abort_ready) begin
                    if (abort_hold_valid_q || abort_selected_index >= 0)
                        entry_state_q[abort_selected_index] <= ENTRY_WAIT_RETIRE;
                    abort_hold_valid_q <= 1'b0;
                end else if (!(workgroup_retire_valid && workgroup_retire_ready
                    && retire_match_index == abort_selected_index)) begin
                    abort_hold_valid_q <= 1'b1;
                    abort_hold_slot_q <= abort_selected_index[COMMAND_SLOT_WIDTH-1:0];
                end
            end else if (abort_hold_valid_q
                && entry_state_q[abort_hold_slot_q] != ENTRY_ABORT) begin
                abort_hold_valid_q <= 1'b0;
            end

            if (workgroup_retire_valid && workgroup_retire_ready) begin
                if (retire_match_index >= 0) begin
                    entry_state_q[retire_match_index] <= ENTRY_COMPLETE;
                    entry_completion_status_q[retire_match_index]
                        <= (entry_cancel_requested_q[retire_match_index]
                            || (entry_queue_context_id_q[retire_match_index] < QUEUE_CONTEXT_COUNT
                                && cancelled_queue_mask[entry_queue_context_id_q[retire_match_index]]))
                            ? 3'd4 : 3'd0;
                    entry_completion_failure_q[retire_match_index] <= '0;
                end
            end

            if (completion_valid && completion_ready) begin
                entry_state_q[completion_selected_index] <= ENTRY_FREE;
                entry_cancel_requested_q[completion_selected_index] <= 1'b0;
                completion_hold_valid_q <= 1'b0;
            end else if (completion_valid) begin
                completion_hold_valid_q <= 1'b1;
                completion_hold_slot_q <= completion_selected_index[COMMAND_SLOT_WIDTH-1:0];
            end else if (completion_hold_valid_q
                && entry_state_q[completion_hold_slot_q] != ENTRY_COMPLETE) begin
                completion_hold_valid_q <= 1'b0;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (QUEUE_CONTEXT_COUNT < 1 || QUEUE_CONTEXT_COUNT > 64)
            $fatal(1, "command lifecycle context capacity must be in 1..64");
        if (COMMAND_SLOTS < 1 || (1 << COMMAND_SLOT_WIDTH) < COMMAND_SLOTS)
            $fatal(1, "command lifecycle slot capacity or index width is invalid");
    end
`endif
endmodule
