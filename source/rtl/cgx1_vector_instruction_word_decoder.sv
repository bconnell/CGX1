// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Stateless bridge from fetched base words to the existing vector request format.
module cgx1_vector_instruction_word_decoder #(
    parameter integer RESIDENT_WAVE_SLOTS = 16
) (
    input logic [RESIDENT_WAVE_SLOTS-1:0] instruction_valid,
    input logic [(RESIDENT_WAVE_SLOTS*32)-1:0] instruction_word_flat,
    input logic [(RESIDENT_WAVE_SLOTS*32)-1:0] instruction_lane_mask_flat,
    output logic [RESIDENT_WAVE_SLOTS-1:0] instruction_ready,

    output logic [RESIDENT_WAVE_SLOTS-1:0] vector_request_valid,
    output logic [(RESIDENT_WAVE_SLOTS*4)-1:0] vector_request_opcode_flat,
    output logic [(RESIDENT_WAVE_SLOTS*8)-1:0] vector_request_source0_flat,
    output logic [(RESIDENT_WAVE_SLOTS*8)-1:0] vector_request_source1_flat,
    output logic [(RESIDENT_WAVE_SLOTS*8)-1:0] vector_request_destination_flat,
    output logic [(RESIDENT_WAVE_SLOTS*32)-1:0] vector_request_lane_mask_flat,
    input logic [RESIDENT_WAVE_SLOTS-1:0] vector_request_accepted,

    output logic [RESIDENT_WAVE_SLOTS-1:0] unhandled_instruction_valid,
    input logic [RESIDENT_WAVE_SLOTS-1:0] unhandled_instruction_ready,
    output logic [(RESIDENT_WAVE_SLOTS*4)-1:0] unhandled_instruction_class_flat,
    output logic [(RESIDENT_WAVE_SLOTS*32)-1:0] unhandled_instruction_word_flat,
    output logic [(RESIDENT_WAVE_SLOTS*4)-1:0] unhandled_instruction_opcode_flat,
    output logic [(RESIDENT_WAVE_SLOTS*8)-1:0] unhandled_instruction_destination_flat,
    output logic [(RESIDENT_WAVE_SLOTS*8)-1:0] unhandled_instruction_source0_flat,
    output logic [(RESIDENT_WAVE_SLOTS*8)-1:0] unhandled_instruction_source1_flat
);
    integer decode_slot;
    integer handshake_slot;

    always_comb begin
        vector_request_valid = '0;
        vector_request_opcode_flat = '0;
        vector_request_source0_flat = '0;
        vector_request_source1_flat = '0;
        vector_request_destination_flat = '0;
        vector_request_lane_mask_flat = '0;
        unhandled_instruction_valid = '0;
        unhandled_instruction_class_flat = '0;
        unhandled_instruction_word_flat = '0;
        unhandled_instruction_opcode_flat = '0;
        unhandled_instruction_destination_flat = '0;
        unhandled_instruction_source0_flat = '0;
        unhandled_instruction_source1_flat = '0;

        for (decode_slot = 0; decode_slot < RESIDENT_WAVE_SLOTS; decode_slot = decode_slot + 1) begin
            vector_request_opcode_flat[(decode_slot*4)+:4]
                = instruction_word_flat[(decode_slot*32)+24+:4];
            vector_request_destination_flat[(decode_slot*8)+:8]
                = instruction_word_flat[(decode_slot*32)+16+:8];
            vector_request_source0_flat[(decode_slot*8)+:8]
                = instruction_word_flat[(decode_slot*32)+8+:8];
            vector_request_source1_flat[(decode_slot*8)+:8]
                = instruction_word_flat[(decode_slot*32)+:8];
            vector_request_lane_mask_flat[(decode_slot*32)+:32]
                = instruction_lane_mask_flat[(decode_slot*32)+:32];
            unhandled_instruction_class_flat[(decode_slot*4)+:4]
                = instruction_word_flat[(decode_slot*32)+28+:4];
            unhandled_instruction_word_flat[(decode_slot*32)+:32]
                = instruction_word_flat[(decode_slot*32)+:32];
            unhandled_instruction_opcode_flat[(decode_slot*4)+:4]
                = instruction_word_flat[(decode_slot*32)+24+:4];
            unhandled_instruction_destination_flat[(decode_slot*8)+:8]
                = instruction_word_flat[(decode_slot*32)+16+:8];
            unhandled_instruction_source0_flat[(decode_slot*8)+:8]
                = instruction_word_flat[(decode_slot*32)+8+:8];
            unhandled_instruction_source1_flat[(decode_slot*8)+:8]
                = instruction_word_flat[(decode_slot*32)+:8];

            vector_request_valid[decode_slot] = instruction_valid[decode_slot]
                && (instruction_word_flat[(decode_slot*32)+28+:4] == 4'h1);
            unhandled_instruction_valid[decode_slot] = instruction_valid[decode_slot]
                && (instruction_word_flat[(decode_slot*32)+28+:4] != 4'h1);
        end
    end

    always_comb begin
        instruction_ready = '0;
        for (handshake_slot = 0; handshake_slot < RESIDENT_WAVE_SLOTS;
             handshake_slot = handshake_slot + 1) begin
            if (instruction_valid[handshake_slot]) begin
                if (instruction_word_flat[(handshake_slot*32)+28+:4] == 4'h1)
                    instruction_ready[handshake_slot] = vector_request_accepted[handshake_slot];
                else
                    instruction_ready[handshake_slot]
                        = unhandled_instruction_ready[handshake_slot];
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (RESIDENT_WAVE_SLOTS < 1)
            $fatal(1, "vector instruction decoder requires at least one resident wave slot");
    end
`endif
endmodule
