// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Candidate matrix admission guard for an exact resident-wave VGPR allocation.

module cgx1_matrix_vgpr_allocation_guard (
    input  logic       allocation_active,
    input  logic [8:0] allocation_register_count,
    input  logic [7:0] destination_base,
    input  logic [7:0] source_a_base,
    input  logic [7:0] source_b_base,
    output logic       layout_legal,
    output logic       allocation_range_legal,
    output logic       matrix_vgpr_legal
);

    function automatic logic range_fits(
        input logic [7:0] base,
        input logic [8:0] count,
        input logic [8:0] allocated_count
    );
        logic [8:0] range_end;
        begin
            range_end = {1'b0, base} + count;
            range_fits = allocation_active
                && (count != 9'd0)
                && (allocated_count != 9'd0)
                && (range_end <= allocated_count);
        end
    endfunction

    function automatic logic spans_overlap(
        input logic [7:0] left_base,
        input logic [8:0] left_count,
        input logic [7:0] right_base,
        input logic [8:0] right_count
    );
        logic [8:0] left_end;
        logic [8:0] right_end;
        begin
            left_end = {1'b0, left_base} + left_count;
            right_end = {1'b0, right_base} + right_count;
            spans_overlap = ({1'b0, left_base} < right_end)
                && ({1'b0, right_base} < left_end);
        end
    endfunction

    always_comb begin
        layout_legal =
            (destination_base[2:0] == 3'd0)
            && (source_a_base[2:0] == 3'd0)
            && ((source_b_base == source_a_base)
                || (source_b_base[2:0] == 3'd4))
            && ({1'b0, destination_base} + 9'd8 <= 9'd256)
            && ({1'b0, source_a_base} + 9'd4 <= 9'd256)
            && ({1'b0, source_b_base} + 9'd4 <= 9'd256)
            && !spans_overlap(destination_base, 9'd8, source_a_base, 9'd4)
            && !spans_overlap(destination_base, 9'd8, source_b_base, 9'd4);

        allocation_range_legal =
            range_fits(destination_base, 9'd8, allocation_register_count)
            && range_fits(source_a_base, 9'd4, allocation_register_count)
            && range_fits(source_b_base, 9'd4, allocation_register_count);

        matrix_vgpr_legal = layout_legal && allocation_range_legal;
    end

endmodule
