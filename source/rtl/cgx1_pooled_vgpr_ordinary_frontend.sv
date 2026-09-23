// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_pooled_vgpr_ordinary_frontend #(
    parameter integer PHYSICAL_ROWS=128,
    parameter integer ROW_WIDTH=(PHYSICAL_ROWS<=1)?1:$clog2(PHYSICAL_ROWS)
)(
    input logic allocation_active,
    input logic [ROW_WIDTH-1:0] allocation_row_base,
    input logic [8:0] allocation_register_count,
    input logic [7:0] source0, source1, destination,
    output logic source0_valid, source1_valid, destination_valid,
    output logic [ROW_WIDTH-1:0] source0_row, source1_row, destination_row,
    output logic [2:0] source0_bank, source1_bank, destination_bank,
    output logic exact_alias,
    output logic distinct_same_bank
);
    cgx1_pooled_vgpr_mapper #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) m0(
      .allocation_active(allocation_active),.allocation_row_base(allocation_row_base),.allocation_register_count(allocation_register_count),
      .architectural_register(source0),.address_valid(source0_valid),.physical_row(source0_row),.bank_class(source0_bank));
    cgx1_pooled_vgpr_mapper #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) m1(
      .allocation_active(allocation_active),.allocation_row_base(allocation_row_base),.allocation_register_count(allocation_register_count),
      .architectural_register(source1),.address_valid(source1_valid),.physical_row(source1_row),.bank_class(source1_bank));
    cgx1_pooled_vgpr_mapper #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) md(
      .allocation_active(allocation_active),.allocation_row_base(allocation_row_base),.allocation_register_count(allocation_register_count),
      .architectural_register(destination),.address_valid(destination_valid),.physical_row(destination_row),.bank_class(destination_bank));
    always_comb begin
      exact_alias=source0_valid&&source1_valid&&(source0==source1)&&(source0_row==source1_row)&&(source0_bank==source1_bank);
      distinct_same_bank=source0_valid&&source1_valid&&!exact_alias&&(source0_bank==source1_bank);
    end
endmodule
