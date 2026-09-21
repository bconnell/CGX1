// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Candidate matrix issue preflight for pooled VGPR allocation and initialization state.

module cgx1_matrix_vgpr_preflight #(
    parameter integer PHYSICAL_ROWS = 128,
    parameter integer ROW_WIDTH = (PHYSICAL_ROWS <= 1) ? 1 : $clog2(PHYSICAL_ROWS)
) (
    input  logic                           allocation_active,
    input  logic [ROW_WIDTH-1:0]           allocation_row_base,
    input  logic [8:0]                     allocation_register_count,
    input  logic [(PHYSICAL_ROWS*8)-1:0]   valid_bitmap,
    input  logic [7:0]                     destination_base,
    input  logic [7:0]                     source_a_base,
    input  logic [7:0]                     source_b_base,
    output logic                           layout_legal,
    output logic                           allocation_range_legal,
    output logic                           all_inputs_initialized,
    output logic                           matrix_issue_legal
);

    logic guard_legal;
    integer source_offset;
    integer accumulator_offset;

    function automatic logic register_initialized(
        input logic [7:0] architectural_register
    );
        integer physical_row_index;
        integer bitmap_index;
        begin
            physical_row_index = $unsigned(allocation_row_base)
                + ($unsigned(architectural_register) >> 3);
            bitmap_index = (physical_row_index * 8)
                + architectural_register[2:0];

            if (physical_row_index >= PHYSICAL_ROWS) begin
                register_initialized = 1'b0;
            end else begin
                register_initialized = valid_bitmap[bitmap_index];
            end
        end
    endfunction

    cgx1_matrix_vgpr_allocation_guard guard (
        .allocation_active(allocation_active),
        .allocation_register_count(allocation_register_count),
        .destination_base(destination_base),
        .source_a_base(source_a_base),
        .source_b_base(source_b_base),
        .layout_legal(layout_legal),
        .allocation_range_legal(allocation_range_legal),
        .matrix_vgpr_legal(guard_legal)
    );

    always_comb begin
        all_inputs_initialized = guard_legal;

        if (guard_legal) begin
            for (source_offset = 0; source_offset < 4; source_offset = source_offset + 1) begin
                all_inputs_initialized = all_inputs_initialized
                    && register_initialized(source_a_base + source_offset)
                    && register_initialized(source_b_base + source_offset);
            end

            for (accumulator_offset = 0; accumulator_offset < 8; accumulator_offset = accumulator_offset + 1) begin
                all_inputs_initialized = all_inputs_initialized
                    && register_initialized(destination_base + accumulator_offset);
            end
        end

        matrix_issue_legal = guard_legal && all_inputs_initialized;
    end

endmodule
