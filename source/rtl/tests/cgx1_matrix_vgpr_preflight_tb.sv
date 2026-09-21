// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_matrix_vgpr_preflight_tb;
    localparam integer PHYSICAL_ROWS = 16;
    localparam integer ROW_WIDTH = 4;

    logic allocation_active;
    logic [ROW_WIDTH-1:0] allocation_row_base;
    logic [8:0] allocation_register_count;
    logic [(PHYSICAL_ROWS*8)-1:0] valid_bitmap;
    logic [7:0] destination_base;
    logic [7:0] source_a_base;
    logic [7:0] source_b_base;
    logic layout_legal;
    logic allocation_range_legal;
    logic all_inputs_initialized;
    logic matrix_issue_legal;

    integer offset;
    integer row;
    integer bank;

    cgx1_matrix_vgpr_preflight #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS),
        .ROW_WIDTH(ROW_WIDTH)
    ) dut (
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

    task automatic mark_valid(input integer architectural_register);
        begin
            row = allocation_row_base + (architectural_register >> 3);
            bank = architectural_register & 7;
            valid_bitmap[(row * 8) + bank] = 1'b1;
        end
    endtask

    initial begin
        allocation_active = 1'b1;
        allocation_row_base = 4'd2;
        allocation_register_count = 9'd72;
        destination_base = 8'd32;
        source_a_base = 8'd64;
        source_b_base = 8'd68;
        valid_bitmap = '0;
        #1;

        if (!layout_legal || !allocation_range_legal || all_inputs_initialized || matrix_issue_legal)
            $fatal(1, "uninitialized canonical matrix instruction was admitted");

        for (offset = 0; offset < 4; offset = offset + 1) begin
            mark_valid(64 + offset);
            mark_valid(68 + offset);
        end
        for (offset = 0; offset < 8; offset = offset + 1)
            mark_valid(32 + offset);
        #1;

        if (!all_inputs_initialized || !matrix_issue_legal)
            $fatal(1, "fully initialized canonical matrix instruction was rejected");

        row = allocation_row_base + (69 >> 3);
        bank = 69 & 7;
        valid_bitmap[(row * 8) + bank] = 1'b0;
        #1;
        if (all_inputs_initialized || matrix_issue_legal)
            $fatal(1, "matrix preflight ignored an uninitialized B register");

        valid_bitmap[(row * 8) + bank] = 1'b1;
        allocation_register_count = 9'd71;
        #1;
        if (allocation_range_legal || matrix_issue_legal)
            $fatal(1, "matrix preflight widened a 71-register allocation to row granularity");

        allocation_register_count = 9'd72;
        source_a_base = 8'd65;
        #1;
        if (layout_legal || matrix_issue_legal)
            $fatal(1, "matrix preflight ignored source-A bank alignment");

        $display("[pass] CGX 1 pooled matrix VGPR preflight checks passed.");
        $finish;
    end
endmodule
