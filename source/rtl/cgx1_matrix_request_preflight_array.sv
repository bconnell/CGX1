// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Candidate per-resident-wave pooled-VGPR matrix request preflight array.

module cgx1_matrix_request_preflight_array #(
    parameter integer PHYSICAL_ROWS = 128,
    parameter integer RESIDENT_WAVE_SLOTS = 16,
    parameter integer ROW_WIDTH = (PHYSICAL_ROWS <= 1) ? 1 : $clog2(PHYSICAL_ROWS)
) (
    input  logic [RESIDENT_WAVE_SLOTS-1:0]       request_valid,
    input  logic [RESIDENT_WAVE_SLOTS-1:0]       allocation_active,
    input  logic [(RESIDENT_WAVE_SLOTS*ROW_WIDTH)-1:0] allocation_row_base,
    input  logic [(RESIDENT_WAVE_SLOTS*9)-1:0]   allocation_register_count,
    input  logic [(PHYSICAL_ROWS*8)-1:0]         valid_bitmap,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0]   destination_base,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0]   source_a_base,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0]   source_b_base,
    output logic [RESIDENT_WAVE_SLOTS-1:0]       request_layout_legal,
    output logic [RESIDENT_WAVE_SLOTS-1:0]       request_allocation_legal,
    output logic [RESIDENT_WAVE_SLOTS-1:0]       request_initialized,
    output logic [RESIDENT_WAVE_SLOTS-1:0]       request_preflight_ready,
    output logic [RESIDENT_WAVE_SLOTS-1:0]       gated_request_valid
);

    genvar wave;
    generate
        for (wave = 0; wave < RESIDENT_WAVE_SLOTS; wave = wave + 1) begin : g_preflight
            cgx1_matrix_vgpr_preflight #(
                .PHYSICAL_ROWS(PHYSICAL_ROWS),
                .ROW_WIDTH(ROW_WIDTH)
            ) preflight (
                .allocation_active(allocation_active[wave]),
                .allocation_row_base(allocation_row_base[(wave*ROW_WIDTH) +: ROW_WIDTH]),
                .allocation_register_count(allocation_register_count[(wave*9) +: 9]),
                .valid_bitmap(valid_bitmap),
                .destination_base(destination_base[(wave*8) +: 8]),
                .source_a_base(source_a_base[(wave*8) +: 8]),
                .source_b_base(source_b_base[(wave*8) +: 8]),
                .layout_legal(request_layout_legal[wave]),
                .allocation_range_legal(request_allocation_legal[wave]),
                .all_inputs_initialized(request_initialized[wave]),
                .matrix_issue_legal()
            );

            always_comb begin
                request_preflight_ready[wave] = !request_layout_legal[wave]
                    || (request_allocation_legal[wave]
                        && request_initialized[wave]);
                gated_request_valid[wave] = request_valid[wave]
                    && request_preflight_ready[wave];
            end
        end
    endgenerate
endmodule
