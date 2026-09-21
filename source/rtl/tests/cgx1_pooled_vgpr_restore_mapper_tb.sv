// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_pooled_vgpr_restore_mapper_tb;
    logic allocation_reserved;
    logic allocation_sanitized;
    logic [3:0] allocation_row_base;
    logic [8:0] allocation_register_count;
    logic [7:0] architectural_register;
    logic restore_address_valid;
    logic [3:0] physical_row;
    logic [2:0] bank_class;

    cgx1_pooled_vgpr_restore_mapper #(
        .PHYSICAL_ROWS(16),
        .ROW_WIDTH(4)
    ) dut (
        .allocation_reserved(allocation_reserved),
        .allocation_sanitized(allocation_sanitized),
        .allocation_row_base(allocation_row_base),
        .allocation_register_count(allocation_register_count),
        .architectural_register(architectural_register),
        .restore_address_valid(restore_address_valid),
        .physical_row(physical_row),
        .bank_class(bank_class)
    );

    initial begin
        allocation_reserved = 1'b1;
        allocation_sanitized = 1'b0;
        allocation_row_base = 4'd3;
        allocation_register_count = 9'd9;
        architectural_register = 8'd8;
        #1;
        if (restore_address_valid)
            $fatal(1, "restore mapping was allowed before sanitization completed");

        allocation_sanitized = 1'b1;
        #1;
        if (!restore_address_valid || physical_row != 4'd4 || bank_class != 3'd0)
            $fatal(1, "sanitized restore mapping is incorrect");

        architectural_register = 8'd9;
        #1;
        if (restore_address_valid)
            $fatal(1, "restore mapper widened exact register count to row capacity");

        allocation_reserved = 1'b0;
        architectural_register = 8'd0;
        #1;
        if (restore_address_valid)
            $fatal(1, "restore mapper admitted a non-Reserved allocation");

        $display("[pass] CGX 1 privileged pooled VGPR restore mapping checks passed.");
        $finish;
    end
endmodule
