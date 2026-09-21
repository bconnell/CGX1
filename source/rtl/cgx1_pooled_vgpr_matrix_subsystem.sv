// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Candidate pooled resident-wave VGPR subsystem for matrix traffic and privileged restore.
// Ordinary vector execution remains outside this boundary.

module cgx1_pooled_vgpr_matrix_subsystem #(
    parameter integer PHYSICAL_ROWS = 128,
    parameter integer RESIDENT_WAVE_SLOTS = 16,
    parameter integer ROW_WIDTH = (PHYSICAL_ROWS <= 1) ? 1 : $clog2(PHYSICAL_ROWS),
    parameter integer WAVE_SLOT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS)
) (
    input  logic                               clk,
    input  logic                               reset_n,
    input  logic                               reserve_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         reserve_wave_slot,
    input  logic [8:0]                         reserve_register_count,
    output logic                               reserve_ready,
    output logic                               reserve_accepted,
    input  logic                               activate_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         activate_wave_slot,
    output logic                               activate_ready,
    output logic                               activate_accepted,
    input  logic                               release_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         release_wave_slot,
    input  logic                               release_quiescent,
    output logic                               release_ready,
    output logic                               release_accepted,
    input  logic [RESIDENT_WAVE_SLOTS-1:0]     wave_execution_busy,
    input  logic                               restore_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         restore_wave_slot,
    input  logic [7:0]                         restore_register,
    input  logic [1023:0]                      restore_data,
    output logic                               restore_ready,
    input  logic [RESIDENT_WAVE_SLOTS-1:0]     matrix_request_valid,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_d_base,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_a_base,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_b_base,
    output logic [RESIDENT_WAVE_SLOTS-1:0]     matrix_request_preflight_ready,
    output logic [RESIDENT_WAVE_SLOTS-1:0]     matrix_request_gated_valid,
    input  logic                               matrix_rf_read_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         matrix_rf_read_wave_slot,
    input  logic [7:0]                         matrix_rf_read_addr0,
    input  logic [7:0]                         matrix_rf_read_addr1,
    output logic                               matrix_rf_read_ready,
    output logic                               matrix_rf_read0_initialized,
    output logic [1023:0]                      matrix_rf_read_data0,
    output logic                               matrix_rf_read1_initialized,
    output logic [1023:0]                      matrix_rf_read_data1,
    input  logic                               matrix_rf_write_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         matrix_rf_write_wave_slot,
    input  logic [7:0]                         matrix_rf_write_addr,
    input  logic [1023:0]                      matrix_rf_write_data,
    output logic                               matrix_rf_write_ready
);

    logic invalidate_valid;
    logic [ROW_WIDTH-1:0] invalidate_row;
    logic invalidate_ready;
    logic [WAVE_SLOT_WIDTH-1:0] unused_query_wave_slot;
    logic unused_query_reserved;
    logic unused_query_active;
    logic unused_query_sanitized;
    logic [ROW_WIDTH-1:0] unused_query_row_base;
    logic [ROW_WIDTH:0] unused_query_row_count;
    logic [8:0] unused_query_register_count;
    logic [RESIDENT_WAVE_SLOTS-1:0] allocation_reserved_bitmap;
    logic [RESIDENT_WAVE_SLOTS-1:0] allocation_active_bitmap;
    logic [RESIDENT_WAVE_SLOTS-1:0] allocation_sanitized_bitmap;
    logic [(RESIDENT_WAVE_SLOTS*ROW_WIDTH)-1:0] allocation_row_base_flat;
    logic [(RESIDENT_WAVE_SLOTS*9)-1:0] allocation_register_count_flat;
    logic [(PHYSICAL_ROWS*8)-1:0] valid_bitmap;
    logic restore_map_valid;
    logic [ROW_WIDTH-1:0] restore_row;
    logic [2:0] restore_bank;
    logic matrix_read0_map_valid;
    logic [ROW_WIDTH-1:0] matrix_read0_row;
    logic [2:0] matrix_read0_bank;
    logic matrix_read1_map_valid;
    logic [ROW_WIDTH-1:0] matrix_read1_row;
    logic [2:0] matrix_read1_bank;
    logic matrix_write_map_valid;
    logic [ROW_WIDTH-1:0] matrix_write_row;
    logic [2:0] matrix_write_bank;
    logic storage_read_valid;
    logic storage_read_ready;
    logic storage_read_bank_conflict;
    logic storage_write_valid;
    logic [ROW_WIDTH-1:0] storage_write_row;
    logic [2:0] storage_write_bank;
    logic [31:0] storage_write_lane_mask;
    logic [1023:0] storage_write_data;
    logic storage_write_ready;
    logic restore_selected;
    logic restore_slot_valid;
    logic matrix_read_slot_valid;
    logic matrix_write_slot_valid;
    logic restore_allocation_reserved;
    logic restore_allocation_sanitized;
    logic [ROW_WIDTH-1:0] restore_allocation_row_base;
    logic [8:0] restore_allocation_register_count;
    logic matrix_read_allocation_active;
    logic [ROW_WIDTH-1:0] matrix_read_allocation_row_base;
    logic [8:0] matrix_read_allocation_register_count;
    logic matrix_write_allocation_active;
    logic [ROW_WIDTH-1:0] matrix_write_allocation_row_base;
    logic [8:0] matrix_write_allocation_register_count;
    logic allocator_activate_ready;
    logic allocator_activate_accepted;
    logic allocator_release_ready;
    logic allocator_release_accepted;
    logic allocator_activate_valid;
    logic allocator_release_quiescent;
    logic allocator_release_valid;
    logic release_slot_valid;
    logic same_wave_restore_pending;
    logic same_wave_matrix_read_active;
    logic same_wave_matrix_write_active;
    logic same_wave_execution_busy;
    logic [RESIDENT_WAVE_SLOTS-1:0] matrix_request_preflight_ready_raw;
    logic [RESIDENT_WAVE_SLOTS-1:0] matrix_request_gated_valid_raw;

    assign unused_query_wave_slot = '0;

    cgx1_resident_wave_vgpr_allocator #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS),
        .RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),
        .ROW_WIDTH(ROW_WIDTH),
        .WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)
    ) allocator (
        .clk(clk), .reset_n(reset_n),
        .reserve_valid(reserve_valid), .reserve_wave_slot(reserve_wave_slot),
        .reserve_register_count(reserve_register_count), .reserve_ready(reserve_ready),
        .reserve_accepted(reserve_accepted), .activate_valid(allocator_activate_valid),
        .activate_wave_slot(activate_wave_slot), .activate_ready(allocator_activate_ready),
        .activate_accepted(allocator_activate_accepted), .release_valid(allocator_release_valid),
        .release_wave_slot(release_wave_slot), .release_quiescent(allocator_release_quiescent),
        .release_ready(allocator_release_ready), .release_accepted(allocator_release_accepted),
        .invalidate_valid(invalidate_valid), .invalidate_row(invalidate_row),
        .invalidate_ready(invalidate_ready), .query_wave_slot(unused_query_wave_slot),
        .query_reserved(unused_query_reserved), .query_active(unused_query_active),
        .query_sanitized(unused_query_sanitized), .query_row_base(unused_query_row_base),
        .query_row_count(unused_query_row_count), .query_register_count(unused_query_register_count),
        .allocation_reserved_bitmap(allocation_reserved_bitmap),
        .allocation_active_bitmap(allocation_active_bitmap),
        .allocation_sanitized_bitmap(allocation_sanitized_bitmap),
        .allocation_row_base_flat(allocation_row_base_flat),
        .allocation_register_count_flat(allocation_register_count_flat)
    );

    cgx1_matrix_request_preflight_array #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS),
        .RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),
        .ROW_WIDTH(ROW_WIDTH)
    ) preflight_array (
        .request_valid(matrix_request_valid),
        .allocation_active(allocation_active_bitmap),
        .allocation_row_base(allocation_row_base_flat),
        .allocation_register_count(allocation_register_count_flat),
        .valid_bitmap(valid_bitmap),
        .destination_base(matrix_request_d_base),
        .source_a_base(matrix_request_a_base),
        .source_b_base(matrix_request_b_base),
        .request_layout_legal(),
        .request_allocation_legal(),
        .request_initialized(),
        .request_preflight_ready(matrix_request_preflight_ready_raw),
        .gated_request_valid(matrix_request_gated_valid_raw)
    );

    always_comb begin
        release_slot_valid = $unsigned(release_wave_slot) < RESIDENT_WAVE_SLOTS;
        same_wave_restore_pending = release_slot_valid
            && restore_valid
            && ($unsigned(restore_wave_slot) < RESIDENT_WAVE_SLOTS)
            && (restore_wave_slot == release_wave_slot);
        same_wave_matrix_read_active = release_slot_valid
            && matrix_rf_read_valid
            && ($unsigned(matrix_rf_read_wave_slot) < RESIDENT_WAVE_SLOTS)
            && (matrix_rf_read_wave_slot == release_wave_slot);
        same_wave_matrix_write_active = release_slot_valid
            && matrix_rf_write_valid
            && ($unsigned(matrix_rf_write_wave_slot) < RESIDENT_WAVE_SLOTS)
            && (matrix_rf_write_wave_slot == release_wave_slot);
        same_wave_execution_busy = 1'b0;
        if (release_slot_valid) begin
            same_wave_execution_busy = wave_execution_busy[release_wave_slot];
        end

        allocator_release_valid = release_valid
            && !same_wave_restore_pending;
        allocator_release_quiescent = release_quiescent
            && !same_wave_matrix_read_active
            && !same_wave_matrix_write_active
            && !same_wave_execution_busy;

        allocator_activate_valid = activate_valid
            && !(restore_valid
                && ($unsigned(restore_wave_slot) < RESIDENT_WAVE_SLOTS)
                && ($unsigned(activate_wave_slot) < RESIDENT_WAVE_SLOTS)
                && (restore_wave_slot == activate_wave_slot));
        activate_ready = allocator_activate_ready
            && allocator_activate_valid;
        activate_accepted = allocator_activate_accepted;
        release_ready = allocator_release_ready && allocator_release_valid;
        release_accepted = allocator_release_accepted;
    end

    always_comb begin
        restore_slot_valid = $unsigned(restore_wave_slot) < RESIDENT_WAVE_SLOTS;
        matrix_read_slot_valid = $unsigned(matrix_rf_read_wave_slot) < RESIDENT_WAVE_SLOTS;
        matrix_write_slot_valid = $unsigned(matrix_rf_write_wave_slot) < RESIDENT_WAVE_SLOTS;

        restore_allocation_reserved = 1'b0;
        restore_allocation_sanitized = 1'b0;
        restore_allocation_row_base = '0;
        restore_allocation_register_count = '0;
        if (restore_slot_valid) begin
            restore_allocation_reserved = allocation_reserved_bitmap[restore_wave_slot];
            restore_allocation_sanitized = allocation_sanitized_bitmap[restore_wave_slot];
            restore_allocation_row_base = allocation_row_base_flat[($unsigned(restore_wave_slot)*ROW_WIDTH) +: ROW_WIDTH];
            restore_allocation_register_count = allocation_register_count_flat[($unsigned(restore_wave_slot)*9) +: 9];
        end

        matrix_read_allocation_active = 1'b0;
        matrix_read_allocation_row_base = '0;
        matrix_read_allocation_register_count = '0;
        if (matrix_read_slot_valid) begin
            matrix_read_allocation_active = allocation_active_bitmap[matrix_rf_read_wave_slot];
            matrix_read_allocation_row_base = allocation_row_base_flat[($unsigned(matrix_rf_read_wave_slot)*ROW_WIDTH) +: ROW_WIDTH];
            matrix_read_allocation_register_count = allocation_register_count_flat[($unsigned(matrix_rf_read_wave_slot)*9) +: 9];
        end

        matrix_write_allocation_active = 1'b0;
        matrix_write_allocation_row_base = '0;
        matrix_write_allocation_register_count = '0;
        if (matrix_write_slot_valid) begin
            matrix_write_allocation_active = allocation_active_bitmap[matrix_rf_write_wave_slot];
            matrix_write_allocation_row_base = allocation_row_base_flat[($unsigned(matrix_rf_write_wave_slot)*ROW_WIDTH) +: ROW_WIDTH];
            matrix_write_allocation_register_count = allocation_register_count_flat[($unsigned(matrix_rf_write_wave_slot)*9) +: 9];
        end
    end

    cgx1_pooled_vgpr_restore_mapper #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS), .ROW_WIDTH(ROW_WIDTH)
    ) restore_mapper (
        .allocation_reserved(restore_allocation_reserved),
        .allocation_sanitized(restore_allocation_sanitized),
        .allocation_row_base(restore_allocation_row_base),
        .allocation_register_count(restore_allocation_register_count),
        .architectural_register(restore_register),
        .restore_address_valid(restore_map_valid),
        .physical_row(restore_row), .bank_class(restore_bank)
    );

    cgx1_pooled_vgpr_mapper #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) read0_mapper (
        .allocation_active(matrix_read_allocation_active),
        .allocation_row_base(matrix_read_allocation_row_base),
        .allocation_register_count(matrix_read_allocation_register_count),
        .architectural_register(matrix_rf_read_addr0), .address_valid(matrix_read0_map_valid),
        .physical_row(matrix_read0_row), .bank_class(matrix_read0_bank)
    );

    cgx1_pooled_vgpr_mapper #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) read1_mapper (
        .allocation_active(matrix_read_allocation_active),
        .allocation_row_base(matrix_read_allocation_row_base),
        .allocation_register_count(matrix_read_allocation_register_count),
        .architectural_register(matrix_rf_read_addr1), .address_valid(matrix_read1_map_valid),
        .physical_row(matrix_read1_row), .bank_class(matrix_read1_bank)
    );

    cgx1_pooled_vgpr_mapper #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) write_mapper (
        .allocation_active(matrix_write_allocation_active),
        .allocation_row_base(matrix_write_allocation_row_base),
        .allocation_register_count(matrix_write_allocation_register_count),
        .architectural_register(matrix_rf_write_addr), .address_valid(matrix_write_map_valid),
        .physical_row(matrix_write_row), .bank_class(matrix_write_bank)
    );

    always_comb begin
        matrix_request_preflight_ready = matrix_request_preflight_ready_raw;
        matrix_request_gated_valid = matrix_request_gated_valid_raw;
        if (release_accepted && release_slot_valid) begin
            matrix_request_preflight_ready[release_wave_slot] = 1'b0;
            matrix_request_gated_valid[release_wave_slot] = 1'b0;
        end

        storage_read_valid = matrix_rf_read_valid
            && matrix_read_slot_valid
            && matrix_read0_map_valid
            && matrix_read1_map_valid;

        restore_selected = restore_valid
            && restore_slot_valid
            && restore_map_valid
            && !(release_accepted
                && (release_wave_slot == restore_wave_slot))
            && !matrix_rf_read_valid
            && !matrix_rf_write_valid;

        storage_write_valid = 1'b0;
        storage_write_row = '0;
        storage_write_bank = '0;
        storage_write_lane_mask = '0;
        storage_write_data = '0;

        if (matrix_rf_write_valid && matrix_write_slot_valid && matrix_write_map_valid) begin
            storage_write_valid = 1'b1;
            storage_write_row = matrix_write_row;
            storage_write_bank = matrix_write_bank;
            storage_write_lane_mask = 32'hFFFFFFFF;
            storage_write_data = matrix_rf_write_data;
        end else if (restore_selected) begin
            storage_write_valid = 1'b1;
            storage_write_row = restore_row;
            storage_write_bank = restore_bank;
            storage_write_lane_mask = 32'hFFFFFFFF;
            storage_write_data = restore_data;
        end

        matrix_rf_read_ready = matrix_rf_read_valid
            && matrix_read0_map_valid
            && matrix_read1_map_valid
            && storage_read_ready;
        matrix_rf_write_ready = matrix_rf_write_valid
            && matrix_write_map_valid
            && storage_write_ready;
        restore_ready = restore_selected && storage_write_ready;
    end

    cgx1_pooled_vgpr_storage #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS), .ROW_WIDTH(ROW_WIDTH)
    ) storage (
        .clk(clk), .reset_n(reset_n),
        .invalidate_valid(invalidate_valid), .invalidate_row(invalidate_row),
        .invalidate_ready(invalidate_ready),
        .read_valid(storage_read_valid),
        .read0_row(matrix_read0_row), .read0_bank(matrix_read0_bank),
        .read1_row(matrix_read1_row), .read1_bank(matrix_read1_bank),
        .read_ready(storage_read_ready), .read_bank_conflict(storage_read_bank_conflict),
        .read0_initialized(matrix_rf_read0_initialized), .read0_data(matrix_rf_read_data0),
        .read1_initialized(matrix_rf_read1_initialized), .read1_data(matrix_rf_read_data1),
        .write_valid(storage_write_valid), .write_row(storage_write_row), .write_bank(storage_write_bank),
        .write_lane_mask(storage_write_lane_mask), .write_data(storage_write_data),
        .write_ready(storage_write_ready), .valid_bitmap(valid_bitmap)
    );

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (reset_n && matrix_rf_read_valid && !matrix_rf_read_ready) begin
            $fatal(1, "pooled matrix capture read was not serviceable in its fixed cycle");
        end
        if (reset_n && matrix_rf_write_valid && !matrix_rf_write_ready) begin
            $fatal(1, "pooled matrix writeback was not serviceable in its fixed cycle");
        end
        if (reset_n && storage_read_bank_conflict && matrix_rf_read_valid) begin
            $fatal(1, "pooled matrix capture produced an unexpected same-bank conflict");
        end
    end
`endif
endmodule
