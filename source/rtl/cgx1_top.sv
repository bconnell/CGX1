// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// CGX 1 architectural RTL scaffold.

module cgx1_top #(
    parameter int TILE_COUNT = 4
) (
    input  logic                  clk,
    input  logic                  reset_n,
    input  logic                  external_48v_present,
    input  logic                  coolant_flow_valid,
    input  logic                  hardware_fault,
    input  logic [7:0]            requested_power_state,
    output logic [7:0]            active_power_state,
    output logic [TILE_COUNT-1:0] tile_enable,
    input  logic                  emergency_thermal,
    input  logic [(TILE_COUNT*3)-1:0] tile_operating_state_flat,
    input  logic [TILE_COUNT-1:0] tile_power_good,
    input  logic [TILE_COUNT-1:0] tile_clocks_stable,
    input  logic [TILE_COUNT-1:0] tile_coherence_ready,
    input  logic [TILE_COUNT-1:0] tile_isolation_asserted,
    output logic [TILE_COUNT-1:0] tile_isolation_request
);

    localparam logic [7:0] P0 = 8'd0;
    logic emergency_isolation_required;
    logic requested_board_state_valid;

    cgx1_tile_power_manager #(
        .TILE_COUNT(TILE_COUNT)
    ) tile_power_manager (
        .reset_n(reset_n),
        .active_power_state(active_power_state),
        .requested_power_state(requested_power_state),
        .external_48v_present(external_48v_present),
        .coolant_flow_valid(coolant_flow_valid),
        .hardware_fault(hardware_fault),
        .emergency_thermal(emergency_thermal),
        .tile_operating_state_flat(tile_operating_state_flat),
        .tile_power_good(tile_power_good),
        .tile_clocks_stable(tile_clocks_stable),
        .tile_coherence_ready(tile_coherence_ready),
        .tile_isolation_asserted(tile_isolation_asserted),
        .scheduler_eligible_mask(tile_enable),
        .emergency_isolation_request(tile_isolation_request),
        .emergency_isolation_required(emergency_isolation_required),
        .requested_board_state_valid(requested_board_state_valid)
    );

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active_power_state <= P0;
        end else if (emergency_isolation_required || !requested_board_state_valid) begin
            active_power_state <= P0;
        end else begin
            active_power_state <= requested_power_state;
        end
    end

endmodule
