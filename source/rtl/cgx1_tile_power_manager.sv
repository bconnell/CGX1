// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Publishes scheduler eligibility from board policy and per-tile status.
module cgx1_tile_power_manager #(
    parameter integer TILE_COUNT = 4
) (
    input logic reset_n,
    input logic [7:0] active_power_state,
    input logic [7:0] requested_power_state,
    input logic external_48v_present,
    input logic coolant_flow_valid,
    input logic hardware_fault,
    input logic emergency_thermal,
    input logic [(TILE_COUNT*3)-1:0] tile_operating_state_flat,
    input logic [TILE_COUNT-1:0] tile_power_good,
    input logic [TILE_COUNT-1:0] tile_clocks_stable,
    input logic [TILE_COUNT-1:0] tile_coherence_ready,
    input logic [TILE_COUNT-1:0] tile_isolation_asserted,
    output logic [TILE_COUNT-1:0] scheduler_eligible_mask,
    output logic [TILE_COUNT-1:0] emergency_isolation_request,
    output logic emergency_isolation_required,
    output logic requested_board_state_valid
);
    localparam logic [7:0] P0 = 8'd0;
    localparam logic [7:0] P1 = 8'd1;
    localparam logic [7:0] P2 = 8'd2;
    localparam logic [7:0] P3 = 8'd3;
    localparam logic [7:0] P4 = 8'd4;

    localparam integer T2_IDLE = 2;
    localparam integer T3_ECO = 3;
    localparam integer T4_NOMINAL = 4;
    localparam integer T5_BOOST = 5;

    logic active_board_state_valid;
    logic active_dock_state;
    logic requested_dock_state;
    logic [7:0] effective_board_state;
    integer tile_state_limit;
    integer slot;
    integer tile_state;

    always_comb begin : policy_decode
        active_board_state_valid = 1'b1;
        case (active_power_state)
            P0, P1, P2, P3, P4: active_board_state_valid = 1'b1;
            default: active_board_state_valid = 1'b0;
        endcase

        requested_board_state_valid = 1'b1;
        case (requested_power_state)
            P0, P1, P2, P3, P4: requested_board_state_valid = 1'b1;
            default: requested_board_state_valid = 1'b0;
        endcase

        active_dock_state = (active_power_state == P3) || (active_power_state == P4);
        requested_dock_state = (requested_power_state == P3) || (requested_power_state == P4);
        emergency_isolation_required = hardware_fault || emergency_thermal
            || ((active_dock_state || requested_dock_state)
                && (!external_48v_present || !coolant_flow_valid));
        emergency_isolation_request = {TILE_COUNT{!reset_n || emergency_isolation_required}};

        scheduler_eligible_mask = '0;
        effective_board_state = P0;
        tile_state_limit = T2_IDLE;
        tile_state = 0;
        if (active_board_state_valid && requested_board_state_valid) begin
            if (active_power_state < requested_power_state)
                effective_board_state = active_power_state;
            else
                effective_board_state = requested_power_state;

            case (effective_board_state)
                P0: tile_state_limit = T2_IDLE;
                P1: tile_state_limit = T3_ECO;
                P2: tile_state_limit = T4_NOMINAL;
                P3, P4: tile_state_limit = T5_BOOST;
                default: tile_state_limit = T2_IDLE;
            endcase

            if (reset_n && !emergency_isolation_required) begin
                for (slot = 0; slot < TILE_COUNT; slot = slot + 1) begin
                    tile_state = $unsigned(tile_operating_state_flat[(slot*3)+:3]);
                    if ((tile_state >= T3_ECO) && (tile_state <= T5_BOOST)
                        && (tile_state <= tile_state_limit)
                        && tile_power_good[slot]
                        && tile_clocks_stable[slot]
                        && tile_coherence_ready[slot]
                        && !tile_isolation_asserted[slot])
                        scheduler_eligible_mask[slot] = 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always_comb begin : policy_assertions
        if (scheduler_eligible_mask != '0) begin
            if (!reset_n || emergency_isolation_required || !active_board_state_valid
                || !requested_board_state_valid)
                $fatal(1, "tile became eligible while power policy is fail-closed");
            if ((scheduler_eligible_mask & tile_isolation_asserted) != '0)
                $fatal(1, "isolated tile became scheduler eligible");
            if ((scheduler_eligible_mask & ~tile_power_good) != '0
                || (scheduler_eligible_mask & ~tile_clocks_stable) != '0
                || (scheduler_eligible_mask & ~tile_coherence_ready) != '0)
                $fatal(1, "tile became eligible before readiness conditions");
        end
    end
`endif
endmodule
