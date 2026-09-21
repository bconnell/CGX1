// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Candidate pooled VGPR address translation RTL. Not yet simulation validated.

module cgx1_pooled_vgpr_mapper #(
    parameter integer PHYSICAL_ROWS = 128,
    parameter integer ROW_WIDTH = (PHYSICAL_ROWS <= 1) ? 1 : $clog2(PHYSICAL_ROWS)
) (
    input  logic                   allocation_active,
    input  logic [ROW_WIDTH-1:0]   allocation_row_base,
    input  logic [8:0]             allocation_register_count,
    input  logic [7:0]             architectural_register,
    output logic                   address_valid,
    output logic [ROW_WIDTH-1:0]   physical_row,
    output logic [2:0]             bank_class
);

    logic [ROW_WIDTH:0] translated_row;

    always_comb begin
        bank_class = architectural_register[2:0];
        translated_row = {1'b0, allocation_row_base}
            + (architectural_register >> 3);
        physical_row = translated_row[ROW_WIDTH-1:0];

        address_valid = allocation_active
            && (allocation_register_count != 9'd0)
            && ({1'b0, architectural_register} < allocation_register_count)
            && (translated_row < PHYSICAL_ROWS);
    end

`ifndef SYNTHESIS
    always_comb begin
        if (address_valid && (translated_row >= PHYSICAL_ROWS)) begin
            $fatal(1, "pooled VGPR translation exceeded physical row capacity");
        end
    end
`endif

endmodule
