// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Per-wave VGPR scoreboard for matrix reservations and ordinary issue queries.
// Resident-wave arbitration and ordinary execution pipelines are separate work.

module cgx1_matrix_wave_scoreboard (
    input  logic         clk,
    input  logic         reset_n,

    input  logic         matrix_issue_accepted,
    input  logic [7:0]   matrix_accepted_d_base,
    input  logic [7:0]   matrix_accepted_a_base,
    input  logic [7:0]   matrix_accepted_b_base,

    input  logic         matrix_source_release_valid,
    input  logic [7:0]   matrix_source_release_a_base,
    input  logic [7:0]   matrix_source_release_b_base,

    input  logic         matrix_destination_complete_valid,
    input  logic [7:0]   matrix_destination_complete_base,

    input  logic         matrix_rf_read_valid,
    input  logic         matrix_rf_write_valid,

    input  logic [255:0] ordinary_read_mask,
    input  logic [255:0] ordinary_write_mask,
    input  logic         ordinary_uses_read_ports,
    input  logic         ordinary_uses_write_port,

    output logic         ordinary_raw_hazard,
    output logic         ordinary_waw_hazard,
    output logic         ordinary_war_hazard,
    output logic         ordinary_read_port_conflict,
    output logic         ordinary_write_port_conflict,
    output logic         ordinary_ready,

    output logic [255:0] matrix_source_pending_mask,
    output logic [255:0] matrix_destination_pending_mask
);

    logic [255:0] source_pending_q;
    logic [255:0] source_pending_d;
    logic [255:0] destination_pending_q;
    logic [255:0] destination_pending_d;

    logic [255:0] issue_source_mask;
    logic [255:0] issue_destination_mask;
    logic [255:0] effective_source_pending;
    logic [255:0] effective_destination_pending;

    function automatic logic [255:0] register_range_mask (
        input logic [7:0] base,
        input integer count
    );
        logic [255:0] mask;
        integer offset;
        integer index;
        begin
            mask = '0;
            for (offset = 0; offset < count; offset = offset + 1) begin
                index = base + offset;
                if (index >= 0 && index < 256) begin
                    mask[index] = 1'b1;
                end
            end
            register_range_mask = mask;
        end
    endfunction

    always_comb begin
        issue_source_mask =
            register_range_mask(matrix_accepted_a_base, 4)
            | register_range_mask(matrix_accepted_b_base, 4);
        issue_destination_mask =
            register_range_mask(matrix_accepted_d_base, 8);

        effective_source_pending = source_pending_q;
        effective_destination_pending = destination_pending_q;

        // issue_accepted is a registered pulse from the matrix controller.
        // Include it combinationally so ordinary issue sees the reservation
        // immediately, before the scoreboard state captures it next clock.
        if (matrix_issue_accepted) begin
            effective_source_pending =
                effective_source_pending | issue_source_mask;
            effective_destination_pending =
                effective_destination_pending | issue_destination_mask;
        end

        matrix_source_pending_mask = effective_source_pending;
        matrix_destination_pending_mask = effective_destination_pending;

        ordinary_raw_hazard =
            |(ordinary_read_mask & effective_destination_pending);
        ordinary_waw_hazard =
            |(ordinary_write_mask & effective_destination_pending);
        ordinary_war_hazard =
            |(ordinary_write_mask & effective_source_pending);

        ordinary_read_port_conflict =
            ordinary_uses_read_ports && matrix_rf_read_valid;
        ordinary_write_port_conflict =
            ordinary_uses_write_port && matrix_rf_write_valid;

        ordinary_ready =
            !ordinary_raw_hazard
            && !ordinary_waw_hazard
            && !ordinary_war_hazard
            && !ordinary_read_port_conflict
            && !ordinary_write_port_conflict;

        source_pending_d = source_pending_q;
        destination_pending_d = destination_pending_q;

        if (matrix_source_release_valid) begin
            source_pending_d =
                source_pending_d
                & ~register_range_mask(matrix_source_release_a_base, 4)
                & ~register_range_mask(matrix_source_release_b_base, 4);
        end

        if (matrix_destination_complete_valid) begin
            destination_pending_d =
                destination_pending_d
                & ~register_range_mask(
                    matrix_destination_complete_base,
                    8);
        end

        if (matrix_issue_accepted) begin
            source_pending_d = source_pending_d | issue_source_mask;
            destination_pending_d =
                destination_pending_d | issue_destination_mask;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            source_pending_q <= '0;
            destination_pending_q <= '0;
        end else begin
            source_pending_q <= source_pending_d;
            destination_pending_q <= destination_pending_d;
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (reset_n && matrix_issue_accepted) begin
            if (|source_pending_q) begin
                $fatal(
                    1,
                    "matrix scoreboard accepted a new matrix issue before prior source capture released"
                );
            end
            if (|(issue_source_mask & destination_pending_q)
                || |(issue_destination_mask & destination_pending_q)) begin
                $fatal(
                    1,
                    "matrix scoreboard accepted a matrix issue that depends on a pending destination"
                );
            end
            if (matrix_accepted_d_base > 8'd248
                || matrix_accepted_a_base > 8'd252
                || matrix_accepted_b_base > 8'd252) begin
                $fatal(1, "matrix scoreboard received an out-of-range matrix reservation");
            end
        end
    end
`endif

endmodule
