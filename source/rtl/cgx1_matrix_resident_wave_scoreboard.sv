// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Parameterized resident-wave routing for per-wave matrix VGPR scoreboards.
// Physical wave storage and the ordinary vector execution datapath are separate work.

module cgx1_matrix_resident_wave_scoreboard #(
    parameter integer RESIDENT_WAVE_SLOTS = 4,
    parameter integer WAVE_SLOT_WIDTH = 2
) (
    input  logic                               clk,
    input  logic                               reset_n,
    input  logic                               matrix_issue_accepted,
    input  logic [WAVE_SLOT_WIDTH-1:0]         matrix_issue_wave_slot,
    input  logic [7:0]                         matrix_accepted_d_base,
    input  logic [7:0]                         matrix_accepted_a_base,
    input  logic [7:0]                         matrix_accepted_b_base,
    input  logic                               matrix_source_release_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         matrix_source_release_wave_slot,
    input  logic [7:0]                         matrix_source_release_a_base,
    input  logic [7:0]                         matrix_source_release_b_base,
    input  logic                               matrix_destination_complete_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         matrix_destination_complete_wave_slot,
    input  logic [7:0]                         matrix_destination_complete_base,
    input  logic                               matrix_rf_read_valid,
    input  logic                               matrix_rf_write_valid,
    input  logic                               ordinary_issue_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         ordinary_wave_slot,
    input  logic [255:0]                       ordinary_read_mask,
    input  logic [255:0]                       ordinary_write_mask,
    input  logic                               ordinary_uses_read_ports,
    input  logic                               ordinary_uses_write_port,
    output logic                               ordinary_raw_hazard,
    output logic                               ordinary_waw_hazard,
    output logic                               ordinary_war_hazard,
    output logic                               ordinary_read_port_conflict,
    output logic                               ordinary_write_port_conflict,
    output logic                               ordinary_ready,
    output logic                               ordinary_issue_accepted,
    output logic [255:0]                       selected_source_pending_mask,
    output logic [255:0]                       selected_destination_pending_mask,
    output logic [RESIDENT_WAVE_SLOTS-1:0]     resident_wave_busy
);

    logic [RESIDENT_WAVE_SLOTS-1:0] slot_raw_hazard;
    logic [RESIDENT_WAVE_SLOTS-1:0] slot_waw_hazard;
    logic [RESIDENT_WAVE_SLOTS-1:0] slot_war_hazard;
    logic [RESIDENT_WAVE_SLOTS-1:0] slot_read_port_conflict;
    logic [RESIDENT_WAVE_SLOTS-1:0] slot_write_port_conflict;
    logic [RESIDENT_WAVE_SLOTS-1:0] slot_ready;
    logic [255:0] slot_source_pending [0:RESIDENT_WAVE_SLOTS-1];
    logic [255:0] slot_destination_pending [0:RESIDENT_WAVE_SLOTS-1];
    integer select_index;
    logic ordinary_slot_valid;

    genvar slot_index;
    generate
        for (slot_index = 0; slot_index < RESIDENT_WAVE_SLOTS; slot_index = slot_index + 1) begin : resident_scoreboard
            localparam logic [WAVE_SLOT_WIDTH-1:0] SLOT = slot_index;
            cgx1_matrix_wave_scoreboard scoreboard (
                .clk(clk),
                .reset_n(reset_n),
                .matrix_issue_accepted(matrix_issue_accepted && (matrix_issue_wave_slot == SLOT)),
                .matrix_accepted_d_base(matrix_accepted_d_base),
                .matrix_accepted_a_base(matrix_accepted_a_base),
                .matrix_accepted_b_base(matrix_accepted_b_base),
                .matrix_source_release_valid(matrix_source_release_valid && (matrix_source_release_wave_slot == SLOT)),
                .matrix_source_release_a_base(matrix_source_release_a_base),
                .matrix_source_release_b_base(matrix_source_release_b_base),
                .matrix_destination_complete_valid(matrix_destination_complete_valid && (matrix_destination_complete_wave_slot == SLOT)),
                .matrix_destination_complete_base(matrix_destination_complete_base),
                .matrix_rf_read_valid(matrix_rf_read_valid),
                .matrix_rf_write_valid(matrix_rf_write_valid),
                .ordinary_read_mask((ordinary_wave_slot == SLOT) ? ordinary_read_mask : '0),
                .ordinary_write_mask((ordinary_wave_slot == SLOT) ? ordinary_write_mask : '0),
                .ordinary_uses_read_ports((ordinary_wave_slot == SLOT) && ordinary_uses_read_ports),
                .ordinary_uses_write_port((ordinary_wave_slot == SLOT) && ordinary_uses_write_port),
                .ordinary_raw_hazard(slot_raw_hazard[slot_index]),
                .ordinary_waw_hazard(slot_waw_hazard[slot_index]),
                .ordinary_war_hazard(slot_war_hazard[slot_index]),
                .ordinary_read_port_conflict(slot_read_port_conflict[slot_index]),
                .ordinary_write_port_conflict(slot_write_port_conflict[slot_index]),
                .ordinary_ready(slot_ready[slot_index]),
                .matrix_source_pending_mask(slot_source_pending[slot_index]),
                .matrix_destination_pending_mask(slot_destination_pending[slot_index])
            );

            always_comb begin
                resident_wave_busy[slot_index] =
                    (|slot_source_pending[slot_index])
                    || (|slot_destination_pending[slot_index]);
            end
        end
    endgenerate

    always_comb begin
        ordinary_slot_valid = 1'b0;
        ordinary_raw_hazard = 1'b0;
        ordinary_waw_hazard = 1'b0;
        ordinary_war_hazard = 1'b0;
        ordinary_read_port_conflict = 1'b0;
        ordinary_write_port_conflict = 1'b0;
        ordinary_ready = 1'b0;
        selected_source_pending_mask = '0;
        selected_destination_pending_mask = '0;

        for (select_index = 0; select_index < RESIDENT_WAVE_SLOTS; select_index = select_index + 1) begin
            if ($unsigned(ordinary_wave_slot) == select_index) begin
                ordinary_slot_valid = 1'b1;
                ordinary_raw_hazard = slot_raw_hazard[select_index];
                ordinary_waw_hazard = slot_waw_hazard[select_index];
                ordinary_war_hazard = slot_war_hazard[select_index];
                ordinary_read_port_conflict = slot_read_port_conflict[select_index];
                ordinary_write_port_conflict = slot_write_port_conflict[select_index];
                ordinary_ready = slot_ready[select_index];
                selected_source_pending_mask = slot_source_pending[select_index];
                selected_destination_pending_mask = slot_destination_pending[select_index];
            end
        end

        if (!ordinary_slot_valid) begin
            ordinary_ready = 1'b0;
        end

        ordinary_issue_accepted =
            ordinary_issue_valid && ordinary_slot_valid && ordinary_ready;
    end

`ifndef SYNTHESIS
    initial begin
        if (RESIDENT_WAVE_SLOTS < 1) begin
            $fatal(1, "resident-wave scoreboard requires at least one slot");
        end
        if ((1 << WAVE_SLOT_WIDTH) < RESIDENT_WAVE_SLOTS) begin
            $fatal(1, "resident-wave scoreboard wave-slot width is too small");
        end
    end
`endif
endmodule
