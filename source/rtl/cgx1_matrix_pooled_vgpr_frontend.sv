// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Candidate matrix frontend for pooled resident-wave VGPR storage.

module cgx1_matrix_pooled_vgpr_frontend #(
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
    output logic                           matrix_issue_legal,
    input  logic                           capture_valid,
    input  logic [2:0]                     capture_cycle,
    output logic                           capture_addresses_valid,
    output logic [ROW_WIDTH-1:0]           capture_read0_row,
    output logic [2:0]                     capture_read0_bank,
    output logic [ROW_WIDTH-1:0]           capture_read1_row,
    output logic [2:0]                     capture_read1_bank,
    input  logic                           writeback_valid,
    input  logic [2:0]                     writeback_cycle,
    output logic                           writeback_address_valid,
    output logic [ROW_WIDTH-1:0]           writeback_row,
    output logic [2:0]                     writeback_bank
);

    logic layout_legal;
    logic allocation_range_legal;
    logic all_inputs_initialized;
    logic [7:0] capture_register0;
    logic [7:0] capture_register1;
    logic [7:0] writeback_register;
    logic map0_valid;
    logic map1_valid;
    logic write_map_valid;

    cgx1_matrix_vgpr_preflight #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS),
        .ROW_WIDTH(ROW_WIDTH)
    ) preflight (
        .allocation_active(allocation_active),
        .allocation_row_base(allocation_row_base),
        .allocation_register_count(allocation_register_count),
        .valid_bitmap(valid_bitmap),
        .destination_base(destination_base),
        .source_a_base(source_a_base),
        .source_b_base(source_b_base),
        .layout_legal(layout_legal),
        .allocation_range_legal(allocation_range_legal),
        .all_inputs_initialized(all_inputs_initialized),
        .matrix_issue_legal(matrix_issue_legal)
    );

    always_comb begin
        if (capture_cycle < 3'd4) begin
            capture_register0 = source_a_base + capture_cycle;
            capture_register1 = source_b_base + capture_cycle;
        end else begin
            capture_register0 = destination_base + ((capture_cycle - 3'd4) << 1);
            capture_register1 = destination_base + ((capture_cycle - 3'd4) << 1) + 1'b1;
        end

        writeback_register = destination_base + writeback_cycle;
    end

    cgx1_pooled_vgpr_mapper #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS), .ROW_WIDTH(ROW_WIDTH)
    ) read0_mapper (
        .allocation_active(allocation_active),
        .allocation_row_base(allocation_row_base),
        .allocation_register_count(allocation_register_count),
        .architectural_register(capture_register0),
        .address_valid(map0_valid),
        .physical_row(capture_read0_row),
        .bank_class(capture_read0_bank)
    );

    cgx1_pooled_vgpr_mapper #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS), .ROW_WIDTH(ROW_WIDTH)
    ) read1_mapper (
        .allocation_active(allocation_active),
        .allocation_row_base(allocation_row_base),
        .allocation_register_count(allocation_register_count),
        .architectural_register(capture_register1),
        .address_valid(map1_valid),
        .physical_row(capture_read1_row),
        .bank_class(capture_read1_bank)
    );

    cgx1_pooled_vgpr_mapper #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS), .ROW_WIDTH(ROW_WIDTH)
    ) write_mapper (
        .allocation_active(allocation_active),
        .allocation_row_base(allocation_row_base),
        .allocation_register_count(allocation_register_count),
        .architectural_register(writeback_register),
        .address_valid(write_map_valid),
        .physical_row(writeback_row),
        .bank_class(writeback_bank)
    );

    always_comb begin
        capture_addresses_valid = capture_valid
            && matrix_issue_legal
            && map0_valid
            && map1_valid;
        writeback_address_valid = writeback_valid
            && allocation_active
            && allocation_range_legal
            && write_map_valid;
    end
endmodule
