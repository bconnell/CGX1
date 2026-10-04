// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_provisional_control_termination #(
    parameter integer RESIDENT_WAVE_SLOTS = 4,
    parameter integer WAVE_SLOT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS)
) (
    input logic clk,
    input logic reset_n,
    input logic external_control_event_valid,
    input logic [RESIDENT_WAVE_SLOTS-1:0] decoded_unhandled_valid,
    input logic [(RESIDENT_WAVE_SLOTS*4)-1:0] decoded_class_flat,
    input logic [(RESIDENT_WAVE_SLOTS*4)-1:0] decoded_opcode_flat,
    input logic [RESIDENT_WAVE_SLOTS-1:0] handler_ready,
    input logic control_flow_event_ready,
    input logic control_flow_event_accepted,
    output logic [RESIDENT_WAVE_SLOTS-1:0] handler_valid,
    output logic [RESIDENT_WAVE_SLOTS-1:0] decoder_ready,
    output logic terminate_event_valid,
    output logic [WAVE_SLOT_WIDTH-1:0] terminate_event_wave_slot,
    output logic terminate_event_accepted
);
    localparam logic [3:0] CONTROL_CLASS = 4'h3;
    localparam logic [3:0] TERMINATE_OPCODE = 4'h0;

    logic [WAVE_SLOT_WIDTH-1:0] round_robin_slot_q;
    logic [RESIDENT_WAVE_SLOTS-1:0] terminate_candidate_mask;
    integer candidate_offset;
    integer candidate_slot;
    integer decode_slot;
    logic candidate_found;

    always_comb begin : select_control_termination
        terminate_candidate_mask = '0;
        handler_valid = decoded_unhandled_valid;
        decoder_ready = handler_ready;
        terminate_event_valid = 1'b0;
        terminate_event_wave_slot = '0;
        candidate_found = 1'b0;
        candidate_slot = 0;

        for (decode_slot = 0; decode_slot < RESIDENT_WAVE_SLOTS; decode_slot = decode_slot + 1) begin
            if (decoded_unhandled_valid[decode_slot]
                && (decoded_class_flat[(decode_slot*4)+:4] == CONTROL_CLASS)
                && (decoded_opcode_flat[(decode_slot*4)+:4] == TERMINATE_OPCODE)) begin
                terminate_candidate_mask[decode_slot] = 1'b1;
                handler_valid[decode_slot] = 1'b0;
                decoder_ready[decode_slot] = 1'b0;
            end
        end

        if (!external_control_event_valid) begin
            for (candidate_offset = 0; candidate_offset < RESIDENT_WAVE_SLOTS;
                 candidate_offset = candidate_offset + 1) begin
                candidate_slot = $unsigned(round_robin_slot_q) + candidate_offset;
                if (candidate_slot >= RESIDENT_WAVE_SLOTS)
                    candidate_slot = candidate_slot - RESIDENT_WAVE_SLOTS;
                if (!candidate_found && terminate_candidate_mask[candidate_slot]) begin
                    candidate_found = 1'b1;
                    terminate_event_valid = 1'b1;
                    terminate_event_wave_slot = candidate_slot;
                    decoder_ready[candidate_slot] = control_flow_event_ready;
                end
            end
        end
    end

    assign terminate_event_accepted = terminate_event_valid
        && control_flow_event_ready && control_flow_event_accepted;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            round_robin_slot_q <= '0;
        else if (terminate_event_accepted) begin
            if (($unsigned(terminate_event_wave_slot) + 1) >= RESIDENT_WAVE_SLOTS)
                round_robin_slot_q <= '0;
            else
                round_robin_slot_q <= terminate_event_wave_slot + 1'b1;
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (RESIDENT_WAVE_SLOTS < 1)
            $fatal(1, "provisional termination decoder requires at least one resident wave slot");
    end
`endif
endmodule
