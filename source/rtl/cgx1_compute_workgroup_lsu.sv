// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Decoded wave32 load/store boundary with per-resident-wave ownership.
module cgx1_compute_workgroup_lsu #(
    parameter integer RESIDENT_WAVE_SLOTS = 8,
    parameter integer WORKGROUP_ID_WIDTH = 16,
    parameter integer WAVE_SLOT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS),
    parameter integer TRANSACTION_TAG_WIDTH = 64,
    parameter integer MEMORY_EPOCH_WIDTH = 32,
    parameter integer VIRTUAL_ADDRESS_WIDTH = 57
) (
    input logic clk,
    input logic reset_n,
    input logic [MEMORY_EPOCH_WIDTH-1:0] memory_epoch,
    input logic [RESIDENT_WAVE_SLOTS-1:0] wave_live_mask,
    input logic [(RESIDENT_WAVE_SLOTS*WORKGROUP_ID_WIDTH)-1:0] wave_workgroup_id_flat,

    input logic [RESIDENT_WAVE_SLOTS-1:0] issue_valid,
    output logic [RESIDENT_WAVE_SLOTS-1:0] issue_ready,
    output logic [RESIDENT_WAVE_SLOTS-1:0] issue_accepted,
    input logic [RESIDENT_WAVE_SLOTS-1:0] issue_global,
    input logic [RESIDENT_WAVE_SLOTS-1:0] issue_write,
    input logic [(RESIDENT_WAVE_SLOTS*8)-1:0] issue_destination_flat,
    input logic [(RESIDENT_WAVE_SLOTS*32)-1:0] issue_lane_mask_flat,
    // Global lanes carry full GPU virtual addresses. Local lanes use a
    // zero-extended 32-bit offset into the admitted workgroup region.
    input logic [(RESIDENT_WAVE_SLOTS*32*VIRTUAL_ADDRESS_WIDTH)-1:0] issue_byte_addresses_flat,
    input logic [(RESIDENT_WAVE_SLOTS*1024)-1:0] issue_store_data_flat,

    output logic [RESIDENT_WAVE_SLOTS-1:0] memory_waiting_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] busy_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] fault_pending_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] load_destination_pending_mask,
    output logic [(RESIDENT_WAVE_SLOTS*8)-1:0] load_destination_register_flat,

    output logic local_request_valid,
    input logic local_request_ready,
    input logic local_request_accepted,
    output logic [WORKGROUP_ID_WIDTH-1:0] local_request_workgroup_id,
    output logic [WAVE_SLOT_WIDTH-1:0] local_request_wave_id,
    output logic [TRANSACTION_TAG_WIDTH-1:0] local_request_transaction_tag,
    output logic local_request_write,
    output logic [31:0] local_request_lane_mask,
    output logic [1023:0] local_request_byte_addresses_flat,
    output logic [1023:0] local_request_store_data_flat,
    input logic local_response_valid,
    output logic local_response_ready,
    input logic [WORKGROUP_ID_WIDTH-1:0] local_response_workgroup_id,
    input logic [WAVE_SLOT_WIDTH-1:0] local_response_wave_id,
    input logic [TRANSACTION_TAG_WIDTH-1:0] local_response_transaction_tag,
    input logic local_response_write,
    input logic [31:0] local_response_lane_mask,
    input logic [1023:0] local_response_lane_data_flat,
    input logic [1:0] local_response_fault_code,
    input logic [5:0] local_response_fault_lane,
    output logic local_cancel_valid,
    output logic [WORKGROUP_ID_WIDTH-1:0] local_cancel_workgroup_id,
    output logic [WAVE_SLOT_WIDTH-1:0] local_cancel_wave_id,
    input logic local_cancel_ready,
    input logic local_cancel_accepted,
    input logic [(1 << WAVE_SLOT_WIDTH)-1:0] local_outstanding_wave_bitmap,

    output logic global_request_valid,
    input logic global_request_ready,
    output logic [WORKGROUP_ID_WIDTH-1:0] global_request_workgroup_id,
    output logic [WAVE_SLOT_WIDTH-1:0] global_request_wave_id,
    output logic [MEMORY_EPOCH_WIDTH-1:0] global_request_epoch,
    output logic [TRANSACTION_TAG_WIDTH-1:0] global_request_transaction_tag,
    output logic global_request_write,
    output logic [31:0] global_request_lane_mask,
    output logic [(32*VIRTUAL_ADDRESS_WIDTH)-1:0] global_request_byte_addresses_flat,
    output logic [1023:0] global_request_store_data_flat,
    input logic global_response_valid,
    output logic global_response_ready,
    input logic [WORKGROUP_ID_WIDTH-1:0] global_response_workgroup_id,
    input logic [WAVE_SLOT_WIDTH-1:0] global_response_wave_id,
    input logic [MEMORY_EPOCH_WIDTH-1:0] global_response_epoch,
    input logic [TRANSACTION_TAG_WIDTH-1:0] global_response_transaction_tag,
    input logic global_response_write,
    input logic [31:0] global_response_lane_mask,
    input logic [1023:0] global_response_lane_data_flat,
    input logic [2:0] global_response_fault_code,
    input logic [5:0] global_response_fault_lane,

    output logic writeback_valid,
    input logic writeback_ready,
    input logic writeback_address_fault,
    output logic [WORKGROUP_ID_WIDTH-1:0] writeback_workgroup_id,
    output logic [WAVE_SLOT_WIDTH-1:0] writeback_wave_slot,
    output logic [TRANSACTION_TAG_WIDTH-1:0] writeback_transaction_tag,
    output logic [7:0] writeback_destination,
    output logic [31:0] writeback_lane_mask,
    output logic [1023:0] writeback_lane_data_flat,

    output logic completion_valid,
    input logic completion_ready,
    output logic [WORKGROUP_ID_WIDTH-1:0] completion_workgroup_id,
    output logic [WAVE_SLOT_WIDTH-1:0] completion_wave_slot,
    output logic [TRANSACTION_TAG_WIDTH-1:0] completion_transaction_tag,
    output logic completion_write,

    output logic fault_valid,
    input logic fault_ready,
    output logic [WORKGROUP_ID_WIDTH-1:0] fault_workgroup_id,
    output logic [WAVE_SLOT_WIDTH-1:0] fault_wave_slot,
    output logic [TRANSACTION_TAG_WIDTH-1:0] fault_transaction_tag,
    output logic [2:0] fault_code,
    output logic [5:0] fault_lane
);
    localparam logic [2:0] ST_FREE = 3'd0;
    localparam logic [2:0] ST_LOCAL_QUEUED = 3'd1;
    localparam logic [2:0] ST_LOCAL_WAIT = 3'd2;
    localparam logic [2:0] ST_GLOBAL_QUEUED = 3'd3;
    localparam logic [2:0] ST_GLOBAL_WAIT = 3'd4;
    localparam logic [2:0] ST_DONE = 3'd5;
    localparam logic [2:0] ST_FAULT = 3'd6;
    localparam logic [2:0] FAULT_LOCAL_ADDRESS_RANGE = 3'd3;
    localparam logic [2:0] FAULT_PROTOCOL = 3'd7;

    logic [2:0] state_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [WORKGROUP_ID_WIDTH-1:0] workgroup_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [MEMORY_EPOCH_WIDTH-1:0] epoch_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [TRANSACTION_TAG_WIDTH-1:0] tag_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [TRANSACTION_TAG_WIDTH-1:0] next_tag_q;
    logic write_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [7:0] destination_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [31:0] lane_mask_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [(32*VIRTUAL_ADDRESS_WIDTH)-1:0] addresses_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [1023:0] store_data_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [2:0] fault_code_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [5:0] fault_lane_q [0:RESIDENT_WAVE_SLOTS-1];

    logic global_hold_valid_q;
    logic [WAVE_SLOT_WIDTH-1:0] global_hold_slot_q;
    logic [WAVE_SLOT_WIDTH-1:0] global_rr_q;
    logic local_hold_valid_q;
    logic [WAVE_SLOT_WIDTH-1:0] local_hold_slot_q;
    logic [WAVE_SLOT_WIDTH-1:0] local_rr_q;
    logic cancel_hold_valid_q;
    logic [WAVE_SLOT_WIDTH-1:0] cancel_hold_slot_q;

    integer global_candidate;
    integer local_candidate;
    integer cancel_candidate;
    integer local_response_match;
    integer global_response_match;
    integer writeback_source;
    integer completion_candidate;
    integer fault_candidate;
    integer scan_offset;

    always_comb begin : state_outputs
        integer slot;
        issue_ready = '0;
        issue_accepted = '0;
        memory_waiting_mask = '0;
        busy_mask = '0;
        fault_pending_mask = '0;
        load_destination_pending_mask = '0;
        load_destination_register_flat = '0;
        for (slot = 0; slot < RESIDENT_WAVE_SLOTS; slot = slot + 1) begin
            issue_ready[slot] = wave_live_mask[slot] && (state_q[slot] == ST_FREE);
            issue_accepted[slot] = issue_valid[slot] && issue_ready[slot];
            if (state_q[slot] != ST_FREE) begin
                memory_waiting_mask[slot] = 1'b1;
                busy_mask[slot] = 1'b1;
            end
            if (state_q[slot] == ST_FAULT)
                fault_pending_mask[slot] = 1'b1;
            if (!write_q[slot]
                && ((state_q[slot] == ST_LOCAL_QUEUED)
                    || (state_q[slot] == ST_LOCAL_WAIT)
                    || (state_q[slot] == ST_GLOBAL_QUEUED)
                    || (state_q[slot] == ST_GLOBAL_WAIT))) begin
                load_destination_pending_mask[slot] = 1'b1;
                load_destination_register_flat[(slot*8)+:8] = destination_q[slot];
            end
        end
    end

    always_comb begin : request_arbitration
        integer candidate;
        integer offset;
        integer slot;
        integer lane;
        candidate = 0;
        offset = 0;
        slot = 0;
        lane = 0;
        global_candidate = -1;
        local_candidate = -1;
        // A presented ready/valid request stays stable through kill until accepted.
        if (global_hold_valid_q) begin
            slot = int'($unsigned(global_hold_slot_q));
            if ((slot < RESIDENT_WAVE_SLOTS)
                && (state_q[slot] == ST_GLOBAL_QUEUED))
                global_candidate = slot;
        end else begin
            for (offset = 0; offset < RESIDENT_WAVE_SLOTS; offset = offset + 1) begin
                candidate = (int'($unsigned(global_rr_q)) + offset) % RESIDENT_WAVE_SLOTS;
                if ((global_candidate < 0) && wave_live_mask[candidate]
                    && (state_q[candidate] == ST_GLOBAL_QUEUED))
                    global_candidate = candidate;
            end
        end
        if (local_hold_valid_q) begin
            slot = int'($unsigned(local_hold_slot_q));
            if ((slot < RESIDENT_WAVE_SLOTS)
                && (state_q[slot] == ST_LOCAL_QUEUED))
                local_candidate = slot;
        end else begin
            for (offset = 0; offset < RESIDENT_WAVE_SLOTS; offset = offset + 1) begin
                candidate = (int'($unsigned(local_rr_q)) + offset) % RESIDENT_WAVE_SLOTS;
                if ((local_candidate < 0) && wave_live_mask[candidate]
                    && (state_q[candidate] == ST_LOCAL_QUEUED))
                    local_candidate = candidate;
            end
        end

        global_request_valid = (global_candidate >= 0);
        global_request_workgroup_id = '0;
        global_request_wave_id = '0;
        global_request_epoch = '0;
        global_request_transaction_tag = '0;
        global_request_write = 1'b0;
        global_request_lane_mask = '0;
        global_request_byte_addresses_flat = '0;
        global_request_store_data_flat = '0;
        if (global_candidate >= 0) begin
            global_request_workgroup_id = workgroup_q[global_candidate];
            global_request_wave_id = global_candidate[WAVE_SLOT_WIDTH-1:0];
            global_request_epoch = epoch_q[global_candidate];
            global_request_transaction_tag = tag_q[global_candidate];
            global_request_write = write_q[global_candidate];
            global_request_lane_mask = lane_mask_q[global_candidate];
            global_request_byte_addresses_flat = addresses_q[global_candidate];
            global_request_store_data_flat = store_data_q[global_candidate];
        end

        local_request_valid = (local_candidate >= 0);
        local_request_workgroup_id = '0;
        local_request_wave_id = '0;
        local_request_transaction_tag = '0;
        local_request_write = 1'b0;
        local_request_lane_mask = '0;
        local_request_byte_addresses_flat = '0;
        local_request_store_data_flat = '0;
        if (local_candidate >= 0) begin
            local_request_workgroup_id = workgroup_q[local_candidate];
            local_request_wave_id = local_candidate[WAVE_SLOT_WIDTH-1:0];
            local_request_transaction_tag = tag_q[local_candidate];
            local_request_write = write_q[local_candidate];
            local_request_lane_mask = lane_mask_q[local_candidate];
            for (lane = 0; lane < 32; lane = lane + 1)
                local_request_byte_addresses_flat[(lane*32)+:32] =
                    addresses_q[local_candidate][(lane*VIRTUAL_ADDRESS_WIDTH)+:32];
            local_request_store_data_flat = store_data_q[local_candidate];
        end
    end

    always_comb begin : response_and_completion_decode
        integer slot;
        local_response_match = -1;
        global_response_match = -1;
        writeback_source = -1;
        completion_candidate = -1;
        fault_candidate = -1;
        writeback_valid = 1'b0;
        writeback_workgroup_id = '0;
        writeback_wave_slot = '0;
        writeback_transaction_tag = '0;
        writeback_destination = '0;
        writeback_lane_mask = '0;
        writeback_lane_data_flat = '0;
        completion_valid = 1'b0;
        completion_workgroup_id = '0;
        completion_wave_slot = '0;
        completion_transaction_tag = '0;
        completion_write = 1'b0;
        fault_valid = 1'b0;
        fault_workgroup_id = '0;
        fault_wave_slot = '0;
        fault_transaction_tag = '0;
        fault_code = '0;
        fault_lane = 6'h3f;

        for (slot = 0; slot < RESIDENT_WAVE_SLOTS; slot = slot + 1) begin
            if ((local_response_match < 0) && local_response_valid
                && (state_q[slot] == ST_LOCAL_WAIT)
                && (workgroup_q[slot] == local_response_workgroup_id)
                && (slot == int'($unsigned(local_response_wave_id)))
                && (tag_q[slot] == local_response_transaction_tag))
                local_response_match = slot;
            if ((global_response_match < 0) && global_response_valid
                && (state_q[slot] == ST_GLOBAL_WAIT)
                && (workgroup_q[slot] == global_response_workgroup_id)
                && (slot == int'($unsigned(global_response_wave_id)))
                && (epoch_q[slot] == global_response_epoch)
                && (tag_q[slot] == global_response_transaction_tag))
                global_response_match = slot;
            if ((completion_candidate < 0) && (state_q[slot] == ST_DONE)
                && wave_live_mask[slot])
                completion_candidate = slot;
            if ((fault_candidate < 0) && (state_q[slot] == ST_FAULT)
                && wave_live_mask[slot])
                fault_candidate = slot;
        end

        if ((local_response_match >= 0) && wave_live_mask[local_response_match]
            && !write_q[local_response_match] && (local_response_fault_code == 0))
            writeback_source = local_response_match;
        else if ((global_response_match >= 0) && wave_live_mask[global_response_match]
            && !write_q[global_response_match] && (global_response_fault_code == 0)
            && (global_response_write == write_q[global_response_match])
            && (global_response_lane_mask == lane_mask_q[global_response_match]))
            writeback_source = RESIDENT_WAVE_SLOTS + global_response_match;

        if (writeback_source >= 0) begin
            writeback_valid = 1'b1;
            if (writeback_source < RESIDENT_WAVE_SLOTS) begin
                slot = writeback_source;
                writeback_workgroup_id = workgroup_q[slot];
                writeback_wave_slot = slot[WAVE_SLOT_WIDTH-1:0];
                writeback_transaction_tag = tag_q[slot];
                writeback_destination = destination_q[slot];
                writeback_lane_mask = lane_mask_q[slot];
                writeback_lane_data_flat = local_response_lane_data_flat;
            end else begin
                slot = writeback_source - RESIDENT_WAVE_SLOTS;
                writeback_workgroup_id = workgroup_q[slot];
                writeback_wave_slot = slot[WAVE_SLOT_WIDTH-1:0];
                writeback_transaction_tag = tag_q[slot];
                writeback_destination = destination_q[slot];
                writeback_lane_mask = lane_mask_q[slot];
                writeback_lane_data_flat = global_response_lane_data_flat;
            end
        end

        if (completion_candidate >= 0) begin
            completion_valid = 1'b1;
            completion_workgroup_id = workgroup_q[completion_candidate];
            completion_wave_slot = completion_candidate[WAVE_SLOT_WIDTH-1:0];
            completion_transaction_tag = tag_q[completion_candidate];
            completion_write = write_q[completion_candidate];
        end
        if (fault_candidate >= 0) begin
            fault_valid = 1'b1;
            fault_workgroup_id = workgroup_q[fault_candidate];
            fault_wave_slot = fault_candidate[WAVE_SLOT_WIDTH-1:0];
            fault_transaction_tag = tag_q[fault_candidate];
            fault_code = fault_code_q[fault_candidate];
            fault_lane = fault_lane_q[fault_candidate];
        end
    end

    always_comb begin : response_backpressure
        local_response_ready = 1'b1;
        global_response_ready = 1'b1;
        if ((local_response_match >= 0) && !wave_live_mask[local_response_match])
            local_response_ready = 1'b1;
        else if ((local_response_match >= 0)
            && ((local_response_fault_code != 0)
                || (local_response_write != write_q[local_response_match])
                || (local_response_lane_mask != lane_mask_q[local_response_match])
                || local_response_write))
            local_response_ready = 1'b1;
        else if ((local_response_match >= 0))
            local_response_ready = (writeback_source == local_response_match)
                ? writeback_ready : 1'b0;
        if ((global_response_match >= 0) && !wave_live_mask[global_response_match])
            global_response_ready = 1'b1;
        else if ((global_response_match >= 0)
            && ((global_response_fault_code != 0)
                || (global_response_write != write_q[global_response_match])
                || (global_response_lane_mask != lane_mask_q[global_response_match])
                || global_response_write))
            global_response_ready = 1'b1;
        else if ((global_response_match >= 0))
            global_response_ready = (writeback_source
                == (RESIDENT_WAVE_SLOTS + global_response_match))
                ? writeback_ready : 1'b0;
    end

    always_comb begin : cancel_arbitration
        integer slot;
        cancel_candidate = -1;
        if (cancel_hold_valid_q) begin
            slot = int'($unsigned(cancel_hold_slot_q));
            if ((slot < RESIDENT_WAVE_SLOTS)
                && (state_q[slot] == ST_LOCAL_WAIT)
                && !wave_live_mask[slot]
                && local_outstanding_wave_bitmap[slot])
                cancel_candidate = slot;
        end else begin
            for (slot = 0; slot < RESIDENT_WAVE_SLOTS; slot = slot + 1)
                if ((cancel_candidate < 0)
                    && (state_q[slot] == ST_LOCAL_WAIT)
                    && !wave_live_mask[slot]
                    && local_outstanding_wave_bitmap[slot])
                    cancel_candidate = slot;
        end
        local_cancel_valid = (cancel_candidate >= 0);
        local_cancel_workgroup_id = '0;
        local_cancel_wave_id = '0;
        if (cancel_candidate >= 0) begin
            local_cancel_workgroup_id = workgroup_q[cancel_candidate];
            local_cancel_wave_id = cancel_candidate[WAVE_SLOT_WIDTH-1:0];
        end
    end

    integer state_slot;
    integer accepted_count;
    integer accepted_prefix;
    integer accepted_lane;
    integer accepted_address_bit;
    integer first_invalid_local_lane;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            next_tag_q <= {{(TRANSACTION_TAG_WIDTH-1){1'b0}}, 1'b1};
            global_hold_valid_q <= 1'b0;
            global_hold_slot_q <= '0;
            global_rr_q <= '0;
            local_hold_valid_q <= 1'b0;
            local_hold_slot_q <= '0;
            local_rr_q <= '0;
            cancel_hold_valid_q <= 1'b0;
            cancel_hold_slot_q <= '0;
            for (state_slot = 0; state_slot < RESIDENT_WAVE_SLOTS; state_slot = state_slot + 1) begin
                state_q[state_slot] <= ST_FREE;
                workgroup_q[state_slot] <= '0;
                epoch_q[state_slot] <= '0;
                tag_q[state_slot] <= '0;
                write_q[state_slot] <= 1'b0;
                destination_q[state_slot] <= '0;
                lane_mask_q[state_slot] <= '0;
                addresses_q[state_slot] <= '0;
                store_data_q[state_slot] <= '0;
                fault_code_q[state_slot] <= '0;
                fault_lane_q[state_slot] <= 6'h3f;
            end
        end else begin
            accepted_count = 0;
            accepted_prefix = 0;
            for (state_slot = 0; state_slot < RESIDENT_WAVE_SLOTS; state_slot = state_slot + 1) begin
                if (issue_accepted[state_slot]) begin
                    first_invalid_local_lane = -1;
                    if (!issue_global[state_slot]) begin
                        for (accepted_lane = 0; accepted_lane < 32; accepted_lane = accepted_lane + 1) begin
                            for (accepted_address_bit = 32;
                                accepted_address_bit < VIRTUAL_ADDRESS_WIDTH;
                                accepted_address_bit = accepted_address_bit + 1) begin
                                if ((first_invalid_local_lane < 0)
                                    && issue_lane_mask_flat[(state_slot*32)+accepted_lane]
                                    && issue_byte_addresses_flat[
                                        (state_slot*32*VIRTUAL_ADDRESS_WIDTH)
                                        +(accepted_lane*VIRTUAL_ADDRESS_WIDTH)
                                        +accepted_address_bit])
                                    first_invalid_local_lane = accepted_lane;
                            end
                        end
                    end
                    workgroup_q[state_slot] <= wave_workgroup_id_flat[
                        (state_slot*WORKGROUP_ID_WIDTH)+:WORKGROUP_ID_WIDTH];
                    epoch_q[state_slot] <= memory_epoch;
                    tag_q[state_slot] <= next_tag_q + TRANSACTION_TAG_WIDTH'(accepted_prefix);
                    write_q[state_slot] <= issue_write[state_slot];
                    destination_q[state_slot] <= issue_destination_flat[(state_slot*8)+:8];
                    lane_mask_q[state_slot] <= issue_lane_mask_flat[(state_slot*32)+:32];
                    addresses_q[state_slot] <= issue_byte_addresses_flat[
                        (state_slot*32*VIRTUAL_ADDRESS_WIDTH)+:(32*VIRTUAL_ADDRESS_WIDTH)];
                    store_data_q[state_slot] <= issue_store_data_flat[(state_slot*1024)+:1024];
                    fault_code_q[state_slot] <= '0;
                    fault_lane_q[state_slot] <= 6'h3f;
                    if (!issue_global[state_slot] && (first_invalid_local_lane >= 0)) begin
                        // Local addresses are 32-bit CU-region offsets. Never
                        // truncate an oversized address into a valid offset.
                        state_q[state_slot] <= ST_FAULT;
                        fault_code_q[state_slot] <= FAULT_LOCAL_ADDRESS_RANGE;
                        fault_lane_q[state_slot] <= first_invalid_local_lane[5:0];
                    end else begin
                        state_q[state_slot] <= issue_global[state_slot]
                            ? ST_GLOBAL_QUEUED : ST_LOCAL_QUEUED;
                    end
                    accepted_count = accepted_count + 1;
                    accepted_prefix = accepted_prefix + 1;
                end else begin
                    case (state_q[state_slot])
                        ST_FREE: begin end
                        ST_LOCAL_QUEUED: begin
                            if (local_request_accepted
                                && (local_request_wave_id == state_slot[WAVE_SLOT_WIDTH-1:0])
                                && (local_request_transaction_tag == tag_q[state_slot]))
                                state_q[state_slot] <= ST_LOCAL_WAIT;
                            else if (!wave_live_mask[state_slot]
                                && !(local_hold_valid_q
                                    && (local_hold_slot_q == state_slot[WAVE_SLOT_WIDTH-1:0])))
                                state_q[state_slot] <= ST_FREE;
                        end
                        ST_LOCAL_WAIT: begin
                            if (!wave_live_mask[state_slot]) begin
                                if (!local_outstanding_wave_bitmap[state_slot])
                                    state_q[state_slot] <= ST_FREE;
                            end else if (local_response_valid && local_response_ready
                                && (local_response_match == state_slot)) begin
                                if (local_response_fault_code != 0) begin
                                    state_q[state_slot] <= ST_FAULT;
                                    fault_code_q[state_slot] <= {1'b0, local_response_fault_code};
                                    fault_lane_q[state_slot] <= local_response_fault_lane;
                                end else if ((local_response_write != write_q[state_slot])
                                    || (local_response_lane_mask != lane_mask_q[state_slot])) begin
                                    state_q[state_slot] <= ST_FAULT;
                                    fault_code_q[state_slot] <= FAULT_PROTOCOL;
                                    fault_lane_q[state_slot] <= 6'h3f;
                                end else if (!write_q[state_slot] && writeback_address_fault) begin
                                    state_q[state_slot] <= ST_FAULT;
                                    fault_code_q[state_slot] <= 3'd4;
                                    fault_lane_q[state_slot] <= 6'h3f;
                                end else begin
                                    state_q[state_slot] <= ST_DONE;
                                end
                            end
                        end
                        ST_GLOBAL_QUEUED: begin
                            if (global_request_valid && global_request_ready
                                && (global_candidate == state_slot))
                                state_q[state_slot] <= ST_GLOBAL_WAIT;
                            else if (!wave_live_mask[state_slot]
                                && !(global_hold_valid_q
                                    && (global_hold_slot_q == state_slot[WAVE_SLOT_WIDTH-1:0])))
                                state_q[state_slot] <= ST_FREE;
                        end
                        ST_GLOBAL_WAIT: begin
                            if (global_response_valid && global_response_ready
                                && (global_response_match == state_slot)) begin
                                if (!wave_live_mask[state_slot]) begin
                                    state_q[state_slot] <= ST_FREE;
                                end else if (global_response_fault_code != 0) begin
                                    state_q[state_slot] <= ST_FAULT;
                                    fault_code_q[state_slot] <= global_response_fault_code;
                                    fault_lane_q[state_slot] <= global_response_fault_lane;
                                end else if ((global_response_write != write_q[state_slot])
                                    || (global_response_lane_mask != lane_mask_q[state_slot])) begin
                                    state_q[state_slot] <= ST_FAULT;
                                    fault_code_q[state_slot] <= FAULT_PROTOCOL;
                                    fault_lane_q[state_slot] <= 6'h3f;
                                end else if (!write_q[state_slot] && writeback_address_fault) begin
                                    state_q[state_slot] <= ST_FAULT;
                                    fault_code_q[state_slot] <= 3'd4;
                                    fault_lane_q[state_slot] <= 6'h3f;
                                end else begin
                                    state_q[state_slot] <= ST_DONE;
                                end
                            end
                        end
                        ST_DONE: begin
                            if (!wave_live_mask[state_slot]
                                || (completion_valid && completion_ready
                                    && (completion_candidate == state_slot)))
                                state_q[state_slot] <= ST_FREE;
                        end
                        ST_FAULT: begin
                            if (!wave_live_mask[state_slot]
                                || (fault_valid && fault_ready
                                    && (fault_candidate == state_slot)))
                                state_q[state_slot] <= ST_FREE;
                        end
                        default: state_q[state_slot] <= ST_FREE;
                    endcase
                end
            end
            if (accepted_count != 0)
                next_tag_q <= next_tag_q + TRANSACTION_TAG_WIDTH'(accepted_count);

            if (global_request_valid && global_request_ready) begin
                global_hold_valid_q <= 1'b0;
                global_rr_q <= WAVE_SLOT_WIDTH'((global_candidate + 1) % RESIDENT_WAVE_SLOTS);
            end else if (global_request_valid && !global_request_ready) begin
                global_hold_valid_q <= 1'b1;
                global_hold_slot_q <= global_candidate[WAVE_SLOT_WIDTH-1:0];
            end else if (global_hold_valid_q && (global_candidate < 0)) begin
                global_hold_valid_q <= 1'b0;
            end

            if (local_request_valid && local_request_ready && local_request_accepted) begin
                local_hold_valid_q <= 1'b0;
                local_rr_q <= WAVE_SLOT_WIDTH'((local_candidate + 1) % RESIDENT_WAVE_SLOTS);
            end else if (local_request_valid && !local_request_ready) begin
                local_hold_valid_q <= 1'b1;
                local_hold_slot_q <= local_candidate[WAVE_SLOT_WIDTH-1:0];
            end else if (local_hold_valid_q && (local_candidate < 0)) begin
                local_hold_valid_q <= 1'b0;
            end

            if (local_cancel_valid && local_cancel_accepted) begin
                cancel_hold_valid_q <= 1'b0;
            end else if (local_cancel_valid && !local_cancel_ready) begin
                cancel_hold_valid_q <= 1'b1;
                cancel_hold_slot_q <= cancel_candidate[WAVE_SLOT_WIDTH-1:0];
            end else if (cancel_hold_valid_q && (cancel_candidate < 0)) begin
                cancel_hold_valid_q <= 1'b0;
            end
        end
    end

`ifndef SYNTHESIS
    integer assertion_slot;
    always_ff @(posedge clk) begin
        if (reset_n) begin
            if ((memory_waiting_mask & ~busy_mask) != '0)
                $fatal(1, "LSU wait state escaped quiescence tracking");
            for (assertion_slot = 0; assertion_slot < RESIDENT_WAVE_SLOTS; assertion_slot = assertion_slot + 1) begin
                if (issue_accepted[assertion_slot] && !wave_live_mask[assertion_slot])
                    $fatal(1, "LSU accepted a request from a non-live wave");
            end
        end
    end
`endif

    initial begin
        if (VIRTUAL_ADDRESS_WIDTH < 32)
            $fatal(1, "LSU virtual address width must cover 32-bit local offsets");
    end
endmodule
