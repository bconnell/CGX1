// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
`timescale 1ns/1ps

module cgx1_top_tb;
    localparam integer TILES = 4;
    localparam logic [7:0] P0 = 8'd0;
    localparam logic [7:0] P1 = 8'd1;
    localparam logic [7:0] P2 = 8'd2;
    localparam logic [7:0] P3 = 8'd3;
    localparam logic [7:0] P4 = 8'd4;
    localparam logic [2:0] T0 = 3'd0;
    localparam logic [2:0] T2 = 3'd2;
    localparam logic [2:0] T3 = 3'd3;
    localparam logic [2:0] T4 = 3'd4;
    localparam logic [2:0] T5 = 3'd5;

    logic clk = 1'b0;
    logic reset_n;
    logic external_48v_present;
    logic coolant_flow_valid;
    logic hardware_fault;
    logic emergency_thermal;
    logic [7:0] requested_power_state;
    logic [TILES*3-1:0] tile_operating_state_flat;
    logic [TILES-1:0] tile_power_good;
    logic [TILES-1:0] tile_clocks_stable;
    logic [TILES-1:0] tile_coherence_ready;
    logic [TILES-1:0] tile_isolation_asserted;
    logic [7:0] active_power_state;
    logic [TILES-1:0] tile_enable;
    logic [TILES-1:0] tile_isolation_request;

    always #5 clk = ~clk;

    cgx1_top #(.TILE_COUNT(TILES)) dut (
        .clk(clk),
        .reset_n(reset_n),
        .external_48v_present(external_48v_present),
        .coolant_flow_valid(coolant_flow_valid),
        .hardware_fault(hardware_fault),
        .emergency_thermal(emergency_thermal),
        .requested_power_state(requested_power_state),
        .tile_operating_state_flat(tile_operating_state_flat),
        .tile_power_good(tile_power_good),
        .tile_clocks_stable(tile_clocks_stable),
        .tile_coherence_ready(tile_coherence_ready),
        .tile_isolation_asserted(tile_isolation_asserted),
        .active_power_state(active_power_state),
        .tile_enable(tile_enable),
        .tile_isolation_request(tile_isolation_request)
    );

    task automatic step_clock;
        @(posedge clk);
        #1;
    endtask

    task automatic set_tile_states(
        input logic [2:0] tile0,
        input logic [2:0] tile1,
        input logic [2:0] tile2,
        input logic [2:0] tile3
    );
        tile_operating_state_flat = {tile3, tile2, tile1, tile0};
    endtask

    task automatic expect_mask(input logic [TILES-1:0] expected, input string label);
        #1;
        if (tile_enable !== expected)
            $fatal(1, "%s: expected eligible mask %b, got %b", label, expected, tile_enable);
    endtask

    task automatic expect_emergency(input logic [TILES-1:0] expected, input string label);
        #1;
        if (tile_isolation_request !== expected)
            $fatal(1, "%s: expected isolation request %b, got %b",
                label, expected, tile_isolation_request);
    endtask

    initial begin
        reset_n = 1'b0;
        external_48v_present = 1'b1;
        coolant_flow_valid = 1'b1;
        hardware_fault = 1'b0;
        emergency_thermal = 1'b0;
        requested_power_state = P0;
        set_tile_states(T3, T3, T3, T3);
        tile_power_good = '1;
        tile_clocks_stable = '1;
        tile_coherence_ready = '1;
        tile_isolation_asserted = '0;
        expect_mask('0, "reset disables scheduling");
        expect_emergency('1, "reset requests isolation");
        step_clock();
        if (active_power_state != P0)
            $fatal(1, "reset did not select P0");

        @(negedge clk); reset_n = 1'b1;
        expect_emergency('0, "normal status releases emergency isolation request");
        expect_mask('0, "P0 does not make idle tiles schedulable");

        // P1 selects any ready T3 subset, not a fixed tile index or count.
        @(negedge clk);
        set_tile_states(T4, T3, T3, T0);
        requested_power_state = P1;
        expect_mask('0, "promotion waits for active board state");
        step_clock();
        if (active_power_state != P1) $fatal(1, "P1 request was not registered");
        expect_mask(4'b0110, "P1 enables arbitrary ready T3 tiles");

        // A pending demotion is immediate; a promotion waits for active state.
        @(negedge clk);
        set_tile_states(T4, T5, T4, T3);
        requested_power_state = P2;
        expect_mask(4'b1000, "P2 promotion remains capped by active P1");
        step_clock();
        if (active_power_state != P2) $fatal(1, "P2 request was not registered");
        expect_mask(4'b1101, "P2 enables T3/T4 across arbitrary tile positions");

        @(negedge clk);
        set_tile_states(T5, T5, T5, T5);
        requested_power_state = P3;
        expect_mask('0, "P3 promotion waits for active board state");
        step_clock();
        expect_mask('1, "P3 permits every ready T5 tile");
        @(negedge clk); requested_power_state = P4;
        step_clock();
        expect_mask('1, "P4 permits every ready T5 tile");

        @(negedge clk);
        requested_power_state = P1;
        expect_mask('0, "P1 demotion masks over-cap tiles before state register updates");
        step_clock();
        if (active_power_state != P1 || tile_enable != '0)
            $fatal(1, "P1 demotion did not retain the stricter cap");

        // Every per-tile readiness condition independently removes eligibility.
        @(negedge clk);
        set_tile_states(T3, T3, T3, T3);
        tile_power_good = '1; tile_clocks_stable = '1;
        tile_coherence_ready = '1; tile_isolation_asserted = '0;
        expect_mask('1, "all ready T3 tiles may schedule in P1");
        tile_power_good[2] = 1'b0;
        expect_mask(4'b1011, "power-good gates tile 2");
        tile_power_good = '1; tile_clocks_stable[0] = 1'b0;
        expect_mask(4'b1110, "clock stability gates tile 0");
        tile_clocks_stable = '1; tile_coherence_ready[1] = 1'b0;
        expect_mask(4'b1101, "coherence readiness gates tile 1");
        tile_coherence_ready = '1; tile_isolation_asserted[3] = 1'b1;
        expect_mask(4'b0111, "asserted isolation gates tile 3");
        tile_isolation_asserted = '0;

        set_tile_states(T3, 3'd6, T3, T3);
        expect_mask(4'b1101, "invalid tile state fails closed");
        set_tile_states(T4, T4, T4, T4);
        expect_mask('0, "P1 rejects T4");
        @(negedge clk); requested_power_state = P2;
        step_clock();
        expect_mask('1, "P2 admits four T4 tiles without a fixed count");
        set_tile_states(T5, T5, T5, T5);
        expect_mask('0, "P2 rejects T5");
        @(negedge clk); requested_power_state = P0;
        expect_mask('0, "P0 demotion is immediate");
        step_clock();
        set_tile_states(T2, T2, T2, T2);
        expect_mask('0, "T2 is never scheduler eligible");

        // Invalid board encodings fail closed and select P0 at the next edge.
        @(negedge clk); requested_power_state = 8'hff;
        expect_mask('0, "invalid board request masks scheduling immediately");
        step_clock();
        if (active_power_state != P0) $fatal(1, "invalid board request did not fall back to P0");

        // Hardware fault and emergency thermal request immediate all-tile isolation.
        @(negedge clk); requested_power_state = P4;
        step_clock();
        set_tile_states(T5, T5, T5, T5);
        hardware_fault = 1'b1;
        expect_mask('0, "hardware fault masks eligibility immediately");
        expect_emergency('1, "hardware fault requests all-tile isolation");
        step_clock();
        if (active_power_state != P0) $fatal(1, "hardware fault did not fall back to P0");
        @(negedge clk); hardware_fault = 1'b0; emergency_thermal = 1'b1;
        expect_mask('0, "thermal emergency masks eligibility immediately");
        expect_emergency('1, "thermal emergency requests all-tile isolation");
        step_clock();
        if (active_power_state != P0) $fatal(1, "thermal emergency did not fall back to P0");
        @(negedge clk); emergency_thermal = 1'b0;

        // Dock loss is emergency isolation while active or requested dock mode.
        requested_power_state = P3;
        step_clock();
        @(negedge clk); external_48v_present = 1'b0;
        expect_mask('0, "dock power loss masks eligibility immediately");
        expect_emergency('1, "dock power loss requests all-tile isolation");
        step_clock();
        if (active_power_state != P0) $fatal(1, "dock power loss did not fall back to P0");
        @(negedge clk); external_48v_present = 1'b1; requested_power_state = P2;
        step_clock();
        @(negedge clk); coolant_flow_valid = 1'b0; requested_power_state = P4;
        expect_mask('0, "coolant loss masks pending dock promotion");
        expect_emergency('1, "coolant loss blocks requested dock promotion");
        step_clock();
        if (active_power_state != P0) $fatal(1, "coolant loss did not fall back to P0");
        @(negedge clk); coolant_flow_valid = 1'b1; requested_power_state = P1;
        step_clock();

        // Slot-only power/coolant loss is not an emergency dock condition.
        @(negedge clk); external_48v_present = 1'b0; coolant_flow_valid = 1'b0;
        set_tile_states(T3, T3, T3, T3);
        expect_mask('1, "slot operation is independent of dock sensors");
        expect_emergency('0, "slot operation does not request dock emergency isolation");

        @(negedge clk); reset_n = 1'b0;
        expect_mask('0, "asynchronous reset disables scheduling");
        expect_emergency('1, "asynchronous reset requests isolation");
        step_clock();
        if (active_power_state != P0) $fatal(1, "final reset did not select P0");

        $display("[pass] CGX1 top-level per-tile power eligibility and emergency isolation checks passed.");
        $finish;
    end
endmodule
