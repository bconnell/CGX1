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
    output logic [TILE_COUNT-1:0] tile_enable
);

    localparam logic [7:0] P0 = 8'd0;
    localparam logic [7:0] P1 = 8'd1;
    localparam logic [7:0] P2 = 8'd2;
    localparam logic [7:0] P3 = 8'd3;
    localparam logic [7:0] P4 = 8'd4;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active_power_state <= P0;
            tile_enable <= '0;
        end else if (hardware_fault) begin
            active_power_state <= P0;
            tile_enable <= '0;
        end else if ((requested_power_state >= P3) &&
                     (!external_48v_present || !coolant_flow_valid)) begin
            active_power_state <= P0;
            tile_enable <= '0;
        end else begin
            active_power_state <= requested_power_state;
            unique case (requested_power_state)
                P0: tile_enable <= '0;
                P1: tile_enable <= {{(TILE_COUNT-1){1'b0}}, 1'b1};
                P2: tile_enable <= {{(TILE_COUNT-2){1'b0}}, 2'b11};
                P3: tile_enable <= '1;
                P4: tile_enable <= '1;
                default: begin
                    active_power_state <= P0;
                    tile_enable <= '0;
                end
            endcase
        end
    end

endmodule
