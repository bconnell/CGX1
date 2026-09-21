// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Candidate privileged restore mapper for a sanitized Reserved allocation.

module cgx1_pooled_vgpr_restore_mapper #(
    parameter integer PHYSICAL_ROWS = 128,
    parameter integer ROW_WIDTH = (PHYSICAL_ROWS <= 1) ? 1 : $clog2(PHYSICAL_ROWS)
) (
    input  logic                   allocation_reserved,
    input  logic                   allocation_sanitized,
    input  logic [ROW_WIDTH-1:0]   allocation_row_base,
    input  logic [8:0]             allocation_register_count,
    input  logic [7:0]             architectural_register,
    output logic                   restore_address_valid,
    output logic [ROW_WIDTH-1:0]   physical_row,
    output logic [2:0]             bank_class
);

    logic [ROW_WIDTH:0] translated_row;

    always_comb begin
        translated_row = {1'b0, allocation_row_base}
            + (architectural_register >> 3);
        bank_class = architectural_register[2:0];
        physical_row = translated_row[ROW_WIDTH-1:0];

        restore_address_valid = allocation_reserved
            && allocation_sanitized
            && (allocation_register_count != 9'd0)
            && ({1'b0, architectural_register} < allocation_register_count)
            && (translated_row < PHYSICAL_ROWS);
    end

endmodule
