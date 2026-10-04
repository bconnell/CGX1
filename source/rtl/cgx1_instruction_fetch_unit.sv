// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Per-resident-wave instruction fetch transactions with identity-checked drain.
module cgx1_instruction_fetch_unit #(
    parameter integer RESIDENT_WAVE_SLOTS = 8,
    parameter integer WORKGROUP_ID_WIDTH = 16,
    parameter integer WAVE_SLOT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS),
    parameter integer MEMORY_EPOCH_WIDTH = 32,
    parameter integer TRANSACTION_TAG_WIDTH = 64,
    parameter integer VIRTUAL_ADDRESS_WIDTH = 57
) (
    input logic clk,
    input logic reset_n,
    input logic [MEMORY_EPOCH_WIDTH-1:0] execution_epoch,
    input logic [RESIDENT_WAVE_SLOTS-1:0] wave_live_mask,
    input logic [RESIDENT_WAVE_SLOTS-1:0] fetch_eligible_mask,
    input logic [(RESIDENT_WAVE_SLOTS*WORKGROUP_ID_WIDTH)-1:0] wave_workgroup_id_flat,
    input logic [(RESIDENT_WAVE_SLOTS*VIRTUAL_ADDRESS_WIDTH)-1:0] wave_pc_flat,

    output logic [RESIDENT_WAVE_SLOTS-1:0] issue_block_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] quiescence_busy_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0] instruction_valid,
    output logic [(RESIDENT_WAVE_SLOTS*32)-1:0] instruction_word_flat,
    output logic [(RESIDENT_WAVE_SLOTS*WORKGROUP_ID_WIDTH)-1:0] instruction_workgroup_id_flat,
    output logic [(RESIDENT_WAVE_SLOTS*VIRTUAL_ADDRESS_WIDTH)-1:0] instruction_pc_flat,
    output logic [(RESIDENT_WAVE_SLOTS*MEMORY_EPOCH_WIDTH)-1:0] instruction_epoch_flat,
    output logic [(RESIDENT_WAVE_SLOTS*TRANSACTION_TAG_WIDTH)-1:0] instruction_transaction_tag_flat,
    input logic [RESIDENT_WAVE_SLOTS-1:0] instruction_ready,

    output logic request_valid,
    input logic request_ready,
    output logic [WORKGROUP_ID_WIDTH-1:0] request_workgroup_id,
    output logic [WAVE_SLOT_WIDTH-1:0] request_wave_slot,
    output logic [MEMORY_EPOCH_WIDTH-1:0] request_epoch,
    output logic [TRANSACTION_TAG_WIDTH-1:0] request_transaction_tag,
    output logic [VIRTUAL_ADDRESS_WIDTH-1:0] request_pc,

    input logic response_valid,
    output logic response_ready,
    input logic [WORKGROUP_ID_WIDTH-1:0] response_workgroup_id,
    input logic [WAVE_SLOT_WIDTH-1:0] response_wave_slot,
    input logic [MEMORY_EPOCH_WIDTH-1:0] response_epoch,
    input logic [TRANSACTION_TAG_WIDTH-1:0] response_transaction_tag,
    input logic [VIRTUAL_ADDRESS_WIDTH-1:0] response_pc,
    input logic [31:0] response_word,
    input logic [2:0] response_fault_code,

    output logic [RESIDENT_WAVE_SLOTS-1:0] fault_valid_mask,
    output logic [(RESIDENT_WAVE_SLOTS*WORKGROUP_ID_WIDTH)-1:0] fault_workgroup_id_flat,
    output logic [(RESIDENT_WAVE_SLOTS*MEMORY_EPOCH_WIDTH)-1:0] fault_epoch_flat,
    output logic [(RESIDENT_WAVE_SLOTS*TRANSACTION_TAG_WIDTH)-1:0] fault_transaction_tag_flat,
    output logic [(RESIDENT_WAVE_SLOTS*VIRTUAL_ADDRESS_WIDTH)-1:0] fault_pc_flat,
    output logic [(RESIDENT_WAVE_SLOTS*3)-1:0] fault_code_flat,
    input logic [RESIDENT_WAVE_SLOTS-1:0] fault_ready_mask
);
    localparam logic [2:0] ST_IDLE = 3'd0;
    localparam logic [2:0] ST_QUEUED = 3'd1;
    localparam logic [2:0] ST_WAIT = 3'd2;
    localparam logic [2:0] ST_INSTRUCTION = 3'd3;
    localparam logic [2:0] ST_FAULT = 3'd4;
    localparam logic [2:0] FAULT_INVALID_PC = 3'd1;

    logic [2:0] state_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [WORKGROUP_ID_WIDTH-1:0] workgroup_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [MEMORY_EPOCH_WIDTH-1:0] epoch_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [TRANSACTION_TAG_WIDTH-1:0] tag_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [VIRTUAL_ADDRESS_WIDTH-1:0] pc_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [31:0] word_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [2:0] fault_code_q [0:RESIDENT_WAVE_SLOTS-1];

    logic [TRANSACTION_TAG_WIDTH-1:0] next_tag_q;
    logic [WAVE_SLOT_WIDTH-1:0] queue_rr_q;
    logic [WAVE_SLOT_WIDTH-1:0] request_rr_q;
    logic request_hold_valid_q;
    logic [WAVE_SLOT_WIDTH-1:0] request_hold_slot_q;
    integer queue_candidate;
    integer request_candidate;
    integer response_match;

    always_comb begin : fetch_outputs
        integer slot;
        integer scan_offset;
        integer scan_slot;

        issue_block_mask = '0;
        quiescence_busy_mask = '0;
        instruction_valid = '0;
        instruction_word_flat = '0;
        instruction_workgroup_id_flat = '0;
        instruction_pc_flat = '0;
        instruction_epoch_flat = '0;
        instruction_transaction_tag_flat = '0;
        fault_valid_mask = '0;
        fault_workgroup_id_flat = '0;
        fault_epoch_flat = '0;
        fault_transaction_tag_flat = '0;
        fault_pc_flat = '0;
        fault_code_flat = '0;

        for (slot = 0; slot < RESIDENT_WAVE_SLOTS; slot = slot + 1) begin
            if (state_q[slot] != ST_IDLE)
                quiescence_busy_mask[slot] = 1'b1;
            if ((state_q[slot] == ST_QUEUED) || (state_q[slot] == ST_WAIT)
                || (state_q[slot] == ST_FAULT))
                issue_block_mask[slot] = 1'b1;
            if ((state_q[slot] == ST_INSTRUCTION) && wave_live_mask[slot]) begin
                instruction_valid[slot] = 1'b1;
                instruction_word_flat[(slot*32)+:32] = word_q[slot];
                instruction_workgroup_id_flat[(slot*WORKGROUP_ID_WIDTH)+:WORKGROUP_ID_WIDTH]
                    = workgroup_q[slot];
                instruction_pc_flat[(slot*VIRTUAL_ADDRESS_WIDTH)+:VIRTUAL_ADDRESS_WIDTH]
                    = pc_q[slot];
                instruction_epoch_flat[(slot*MEMORY_EPOCH_WIDTH)+:MEMORY_EPOCH_WIDTH]
                    = epoch_q[slot];
                instruction_transaction_tag_flat[(slot*TRANSACTION_TAG_WIDTH)+:TRANSACTION_TAG_WIDTH]
                    = tag_q[slot];
            end
            if ((state_q[slot] == ST_FAULT) && wave_live_mask[slot]) begin
                fault_valid_mask[slot] = 1'b1;
                fault_workgroup_id_flat[(slot*WORKGROUP_ID_WIDTH)+:WORKGROUP_ID_WIDTH]
                    = workgroup_q[slot];
                fault_epoch_flat[(slot*MEMORY_EPOCH_WIDTH)+:MEMORY_EPOCH_WIDTH]
                    = epoch_q[slot];
                fault_transaction_tag_flat[(slot*TRANSACTION_TAG_WIDTH)+:TRANSACTION_TAG_WIDTH]
                    = tag_q[slot];
                fault_pc_flat[(slot*VIRTUAL_ADDRESS_WIDTH)+:VIRTUAL_ADDRESS_WIDTH]
                    = pc_q[slot];
                fault_code_flat[(slot*3)+:3] = fault_code_q[slot];
            end
        end

        queue_candidate = -1;
        for (scan_offset = 0; scan_offset < RESIDENT_WAVE_SLOTS; scan_offset = scan_offset + 1) begin
            scan_slot = ($unsigned(queue_rr_q) + scan_offset) % RESIDENT_WAVE_SLOTS;
            if ((queue_candidate < 0) && (state_q[scan_slot] == ST_IDLE)
                && wave_live_mask[scan_slot] && fetch_eligible_mask[scan_slot])
                queue_candidate = scan_slot;
        end

        request_candidate = -1;
        if (request_hold_valid_q) begin
            request_candidate = $unsigned(request_hold_slot_q);
        end else begin
            for (scan_offset = 0; scan_offset < RESIDENT_WAVE_SLOTS; scan_offset = scan_offset + 1) begin
                scan_slot = ($unsigned(request_rr_q) + scan_offset) % RESIDENT_WAVE_SLOTS;
                if ((request_candidate < 0) && (state_q[scan_slot] == ST_QUEUED))
                    request_candidate = scan_slot;
            end
        end

        request_valid = (request_candidate >= 0);
        request_workgroup_id = '0;
        request_wave_slot = '0;
        request_epoch = '0;
        request_transaction_tag = '0;
        request_pc = '0;
        if (request_candidate >= 0) begin
            request_workgroup_id = workgroup_q[request_candidate];
            request_wave_slot = request_candidate[WAVE_SLOT_WIDTH-1:0];
            request_epoch = epoch_q[request_candidate];
            request_transaction_tag = tag_q[request_candidate];
            request_pc = pc_q[request_candidate];
        end

        response_ready = 1'b1;
        response_match = -1;
        if (response_valid && ($unsigned(response_wave_slot) < RESIDENT_WAVE_SLOTS)) begin
            slot = $unsigned(response_wave_slot);
            if ((state_q[slot] == ST_WAIT)
                && (workgroup_q[slot] == response_workgroup_id)
                && (epoch_q[slot] == response_epoch)
                && (tag_q[slot] == response_transaction_tag)
                && (pc_q[slot] == response_pc))
                response_match = slot;
        end
    end

    integer state_slot;
    integer next_queue_rr;
    integer next_request_rr;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            next_tag_q <= {{(TRANSACTION_TAG_WIDTH-1){1'b0}}, 1'b1};
            queue_rr_q <= '0;
            request_rr_q <= '0;
            request_hold_valid_q <= 1'b0;
            request_hold_slot_q <= '0;
            for (state_slot = 0; state_slot < RESIDENT_WAVE_SLOTS; state_slot = state_slot + 1) begin
                state_q[state_slot] <= ST_IDLE;
                workgroup_q[state_slot] <= '0;
                epoch_q[state_slot] <= '0;
                tag_q[state_slot] <= '0;
                pc_q[state_slot] <= '0;
                word_q[state_slot] <= '0;
                fault_code_q[state_slot] <= '0;
            end
        end else begin
            if (queue_candidate >= 0) begin
                state_slot = queue_candidate;
                workgroup_q[state_slot] <= wave_workgroup_id_flat[
                    (state_slot*WORKGROUP_ID_WIDTH)+:WORKGROUP_ID_WIDTH];
                epoch_q[state_slot] <= execution_epoch;
                tag_q[state_slot] <= next_tag_q;
                pc_q[state_slot] <= wave_pc_flat[
                    (state_slot*VIRTUAL_ADDRESS_WIDTH)+:VIRTUAL_ADDRESS_WIDTH];
                word_q[state_slot] <= '0;
                if (wave_pc_flat[(state_slot*VIRTUAL_ADDRESS_WIDTH)+:2] != 2'b00) begin
                    state_q[state_slot] <= ST_FAULT;
                    fault_code_q[state_slot] <= FAULT_INVALID_PC;
                end else begin
                    state_q[state_slot] <= ST_QUEUED;
                    fault_code_q[state_slot] <= '0;
                end
                if (next_tag_q == {TRANSACTION_TAG_WIDTH{1'b1}})
                    next_tag_q <= {{(TRANSACTION_TAG_WIDTH-1){1'b0}}, 1'b1};
                else
                    next_tag_q <= next_tag_q + 1'b1;
                next_queue_rr = state_slot + 1;
                if (next_queue_rr >= RESIDENT_WAVE_SLOTS)
                    next_queue_rr = 0;
                queue_rr_q <= next_queue_rr[WAVE_SLOT_WIDTH-1:0];
            end

            if (request_valid && request_ready) begin
                state_q[request_candidate] <= ST_WAIT;
                next_request_rr = request_candidate + 1;
                if (next_request_rr >= RESIDENT_WAVE_SLOTS)
                    next_request_rr = 0;
                request_rr_q <= next_request_rr[WAVE_SLOT_WIDTH-1:0];
                request_hold_valid_q <= 1'b0;
            end else if (request_valid && !request_ready) begin
                request_hold_valid_q <= 1'b1;
                request_hold_slot_q <= request_candidate[WAVE_SLOT_WIDTH-1:0];
            end

            if (response_valid && response_ready && (response_match >= 0)) begin
                if (!wave_live_mask[response_match]) begin
                    state_q[response_match] <= ST_IDLE;
                end else if (response_fault_code != 0) begin
                    state_q[response_match] <= ST_FAULT;
                    fault_code_q[response_match] <= response_fault_code;
                end else begin
                    state_q[response_match] <= ST_INSTRUCTION;
                    word_q[response_match] <= response_word;
                end
            end

            for (state_slot = 0; state_slot < RESIDENT_WAVE_SLOTS; state_slot = state_slot + 1) begin
                if ((state_q[state_slot] == ST_QUEUED) && !wave_live_mask[state_slot]
                    && !(request_valid && (request_candidate == state_slot)))
                    state_q[state_slot] <= ST_IDLE;
                else if ((state_q[state_slot] == ST_INSTRUCTION) && !wave_live_mask[state_slot])
                    state_q[state_slot] <= ST_IDLE;
                else if ((state_q[state_slot] == ST_INSTRUCTION) && instruction_ready[state_slot])
                    state_q[state_slot] <= ST_IDLE;
                else if ((state_q[state_slot] == ST_FAULT) && !wave_live_mask[state_slot])
                    state_q[state_slot] <= ST_IDLE;
                else if ((state_q[state_slot] == ST_FAULT) && fault_ready_mask[state_slot])
                    state_q[state_slot] <= ST_IDLE;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (RESIDENT_WAVE_SLOTS < 1 || WAVE_SLOT_WIDTH < 1 || WORKGROUP_ID_WIDTH < 1
            || MEMORY_EPOCH_WIDTH < 1 || TRANSACTION_TAG_WIDTH < 1 || VIRTUAL_ADDRESS_WIDTH < 2)
            $fatal(1, "instruction fetch parameters must all be positive and PC width at least two");
    end
`endif
endmodule
