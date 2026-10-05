// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_provisional_control_instruction_dispatch #(
    parameter integer RESIDENT_WAVE_SLOTS = 4,
    parameter integer WAVE_SLOT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS),
    parameter integer VIRTUAL_ADDRESS_WIDTH = 57
) (
    input logic clk,
    input logic reset_n,
    input logic external_control_event_valid,
    input logic [RESIDENT_WAVE_SLOTS-1:0] decoded_unhandled_valid,
    input logic [(RESIDENT_WAVE_SLOTS*4)-1:0] decoded_class_flat,
    input logic [(RESIDENT_WAVE_SLOTS*4)-1:0] decoded_opcode_flat,
    input logic [(RESIDENT_WAVE_SLOTS*32)-1:0] decoded_word_flat,
    input logic [(RESIDENT_WAVE_SLOTS*VIRTUAL_ADDRESS_WIDTH)-1:0] decoded_pc_flat,
    input logic [(RESIDENT_WAVE_SLOTS*32)-1:0] active_lane_mask_flat,
    input logic [RESIDENT_WAVE_SLOTS-1:0] handler_ready,
    input logic control_flow_event_ready,
    input logic control_flow_event_accepted,
    output logic [RESIDENT_WAVE_SLOTS-1:0] handler_valid,
    output logic [RESIDENT_WAVE_SLOTS-1:0] decoder_ready,
    output logic control_instruction_event_valid,
    output logic [WAVE_SLOT_WIDTH-1:0] control_instruction_event_wave_slot,
    output logic [2:0] control_instruction_event_kind,
    output logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_instruction_event_target_pc,
    output logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_instruction_event_fallthrough_pc,
    output logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_instruction_event_join_pc,
    output logic [31:0] control_instruction_event_taken_mask,
    output logic control_instruction_event_accepted
);
    localparam logic [3:0] CONTROL_CLASS = 4'h3;
    localparam logic [3:0] TERMINATE_OPCODE = 4'h0;
    localparam logic [3:0] BRANCH_OPCODE = 4'h1;
    localparam logic [2:0] EVENT_BRANCH = 3'd1;
    localparam logic [2:0] EVENT_TERMINATE = 3'd7;
    localparam integer BRANCH_CALC_WIDTH = VIRTUAL_ADDRESS_WIDTH + 2;
    localparam logic signed [BRANCH_CALC_WIDTH-1:0] GPU_ADDRESS_LIMIT
        = $signed({1'b0, 1'b1, {VIRTUAL_ADDRESS_WIDTH{1'b0}}});
    localparam logic signed [BRANCH_CALC_WIDTH-1:0] FOUR_BYTES = 4;
    localparam logic [VIRTUAL_ADDRESS_WIDTH-1:0] INVALID_PC_SENTINEL
        = {{(VIRTUAL_ADDRESS_WIDTH-2){1'b0}}, 2'b01};

    logic [WAVE_SLOT_WIDTH-1:0] round_robin_slot_q;
    logic [RESIDENT_WAVE_SLOTS-1:0] control_instruction_candidate_mask;
    logic [23:0] branch_displacement_bits;
    logic signed [BRANCH_CALC_WIDTH-1:0] branch_displacement;
    logic signed [BRANCH_CALC_WIDTH-1:0] branch_next_pc;
    logic signed [BRANCH_CALC_WIDTH-1:0] branch_target;
    logic branch_target_in_range;
    logic [VIRTUAL_ADDRESS_WIDTH-1:0] branch_target_pc;
    integer candidate_offset;
    integer candidate_slot;
    integer decode_slot;
    logic candidate_found;

    always_comb begin : select_fetched_control_instruction
        control_instruction_candidate_mask = '0;
        control_instruction_event_valid = 1'b0;
        control_instruction_event_wave_slot = '0;
        control_instruction_event_kind = '0;
        control_instruction_event_target_pc = '0;
        control_instruction_event_fallthrough_pc = '0;
        control_instruction_event_join_pc = '0;
        control_instruction_event_taken_mask = '0;
        candidate_found = 1'b0;
        candidate_slot = 0;
        branch_displacement_bits = '0;
        branch_displacement = '0;
        branch_next_pc = '0;
        branch_target = '0;
        branch_target_in_range = 1'b0;
        branch_target_pc = '0;

        for (decode_slot = 0; decode_slot < RESIDENT_WAVE_SLOTS; decode_slot = decode_slot + 1) begin
            if (decoded_unhandled_valid[decode_slot]
                && (decoded_class_flat[(decode_slot*4)+:4] == CONTROL_CLASS)
                && ((decoded_opcode_flat[(decode_slot*4)+:4] == TERMINATE_OPCODE)
                    || (decoded_opcode_flat[(decode_slot*4)+:4] == BRANCH_OPCODE))) begin
                control_instruction_candidate_mask[decode_slot] = 1'b1;
            end
        end

        if (!external_control_event_valid) begin
            for (candidate_offset = 0; candidate_offset < RESIDENT_WAVE_SLOTS;
                 candidate_offset = candidate_offset + 1) begin
                candidate_slot = int'($unsigned(round_robin_slot_q)) + candidate_offset;
                if (candidate_slot >= RESIDENT_WAVE_SLOTS)
                    candidate_slot = candidate_slot - RESIDENT_WAVE_SLOTS;
                if (!candidate_found && control_instruction_candidate_mask[candidate_slot]) begin
                    candidate_found = 1'b1;
                    control_instruction_event_valid = 1'b1;
                    control_instruction_event_wave_slot = candidate_slot[WAVE_SLOT_WIDTH-1:0];
                    if (decoded_opcode_flat[(candidate_slot*4)+:4] == TERMINATE_OPCODE) begin
                        control_instruction_event_kind = EVENT_TERMINATE;
                    end else begin
                        branch_displacement_bits = decoded_word_flat[(candidate_slot*32)+:24];
                        branch_displacement = {{(BRANCH_CALC_WIDTH-24){branch_displacement_bits[23]}},
                            branch_displacement_bits};
                        branch_next_pc = $signed({2'b00,
                            decoded_pc_flat[(candidate_slot*VIRTUAL_ADDRESS_WIDTH)+:VIRTUAL_ADDRESS_WIDTH]})
                            + FOUR_BYTES;
                        branch_target = branch_next_pc + branch_displacement;
                        branch_target_in_range = (branch_target >= 0)
                            && (branch_target < GPU_ADDRESS_LIMIT);
                        if (branch_target_in_range)
                            branch_target_pc = branch_target[VIRTUAL_ADDRESS_WIDTH-1:0];
                        else
                            branch_target_pc = INVALID_PC_SENTINEL;
                        control_instruction_event_kind = EVENT_BRANCH;
                        control_instruction_event_target_pc = branch_target_pc;
                        // This provisional branch is unconditional, so the
                        // existing branch transition does not consume these
                        // two path PCs. Reuse the target to keep them valid at
                        // the final aligned instruction address.
                        control_instruction_event_fallthrough_pc = branch_target_pc;
                        control_instruction_event_join_pc = branch_target_pc;
                        control_instruction_event_taken_mask
                            = active_lane_mask_flat[(candidate_slot*32)+:32];
                    end
                end
            end
        end
    end

    always_comb begin : decoder_acceptance
        integer ready_slot;
        handler_valid = decoded_unhandled_valid;
        decoder_ready = handler_ready;
        for (ready_slot = 0; ready_slot < RESIDENT_WAVE_SLOTS; ready_slot = ready_slot + 1) begin
            if (control_instruction_candidate_mask[ready_slot]) begin
                handler_valid[ready_slot] = 1'b0;
                decoder_ready[ready_slot] = 1'b0;
            end
        end
        if (control_instruction_event_valid)
            decoder_ready[control_instruction_event_wave_slot] = control_flow_event_ready
                && control_flow_event_accepted;
    end

    assign control_instruction_event_accepted = control_instruction_event_valid
        && control_flow_event_ready && control_flow_event_accepted;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            round_robin_slot_q <= '0;
        else if (control_instruction_event_accepted) begin
            if ((int'($unsigned(control_instruction_event_wave_slot)) + 1) >= RESIDENT_WAVE_SLOTS)
                round_robin_slot_q <= '0;
            else
                round_robin_slot_q <= control_instruction_event_wave_slot + 1'b1;
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (RESIDENT_WAVE_SLOTS < 1)
            $fatal(1, "provisional control instruction dispatcher requires at least one resident wave slot");
        if (VIRTUAL_ADDRESS_WIDTH < 24)
            $fatal(1, "provisional control branch requires at least a 24-bit virtual address");
    end
`endif
endmodule
