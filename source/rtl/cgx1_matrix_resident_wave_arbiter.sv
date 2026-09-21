// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Round-robin selector for resident-wave matrix requests.
// The resident-wave slot count is an implementation parameter, not an architectural target.

module cgx1_matrix_resident_wave_arbiter #(
    parameter integer RESIDENT_WAVE_SLOTS = 4,
    parameter integer WAVE_SLOT_WIDTH = 2
) (
    input  logic                               clk,
    input  logic                               reset_n,
    input  logic [RESIDENT_WAVE_SLOTS-1:0]     request_valid,
    input  logic [RESIDENT_WAVE_SLOTS-1:0]     request_full_wave_active,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0] request_d_base,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0] request_a_base,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0] request_b_base,
    output logic [RESIDENT_WAVE_SLOTS-1:0]     request_ready,
    output logic                               grant_valid,
    output logic [WAVE_SLOT_WIDTH-1:0]         grant_wave_slot,
    output logic                               grant_full_wave_active,
    output logic [7:0]                         grant_d_base,
    output logic [7:0]                         grant_a_base,
    output logic [7:0]                         grant_b_base,
    input  logic                               grant_ready
);

    logic [WAVE_SLOT_WIDTH-1:0] round_robin_q;
    logic [WAVE_SLOT_WIDTH-1:0] round_robin_d;
    integer scan_index;
    integer candidate_index;

    always_comb begin
        request_ready = '0;
        grant_valid = 1'b0;
        grant_wave_slot = '0;
        grant_full_wave_active = 1'b0;
        grant_d_base = 8'd0;
        grant_a_base = 8'd0;
        grant_b_base = 8'd0;

        for (scan_index = 0; scan_index < RESIDENT_WAVE_SLOTS; scan_index = scan_index + 1) begin
            candidate_index = $unsigned(round_robin_q) + scan_index;
            if (candidate_index >= RESIDENT_WAVE_SLOTS) begin
                candidate_index = candidate_index - RESIDENT_WAVE_SLOTS;
            end
            if (!grant_valid && request_valid[candidate_index]) begin
                grant_valid = 1'b1;
                grant_wave_slot = candidate_index[WAVE_SLOT_WIDTH-1:0];
                grant_full_wave_active = request_full_wave_active[candidate_index];
                grant_d_base = request_d_base[(candidate_index * 8) +: 8];
                grant_a_base = request_a_base[(candidate_index * 8) +: 8];
                grant_b_base = request_b_base[(candidate_index * 8) +: 8];
            end
        end

        if (grant_valid) begin
            request_ready[grant_wave_slot] = grant_ready;
        end

        round_robin_d = round_robin_q;
        if (grant_valid && grant_ready) begin
            if ($unsigned(grant_wave_slot) == RESIDENT_WAVE_SLOTS - 1) begin
                round_robin_d = '0;
            end else begin
                round_robin_d = grant_wave_slot + 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            round_robin_q <= '0;
        end else begin
            round_robin_q <= round_robin_d;
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (RESIDENT_WAVE_SLOTS < 1) begin
            $fatal(1, "resident-wave arbiter requires at least one slot");
        end
        if ((1 << WAVE_SLOT_WIDTH) < RESIDENT_WAVE_SLOTS) begin
            $fatal(1, "resident-wave arbiter wave-slot width is too small");
        end
    end
`endif
endmodule
