// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Candidate first-fit resident-wave VGPR row allocator with serialized validity invalidation.

module cgx1_resident_wave_vgpr_allocator #(
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
    output logic                               invalidate_valid,
    output logic [ROW_WIDTH-1:0]               invalidate_row,
    input  logic                               invalidate_ready,
    input  logic [WAVE_SLOT_WIDTH-1:0]         query_wave_slot,
    output logic                               query_reserved,
    output logic                               query_active,
    output logic                               query_sanitized,
    output logic [ROW_WIDTH-1:0]               query_row_base,
    output logic [ROW_WIDTH:0]                 query_row_count,
    output logic [8:0]                         query_register_count,
    output logic [RESIDENT_WAVE_SLOTS-1:0]     allocation_reserved_bitmap,
    output logic [RESIDENT_WAVE_SLOTS-1:0]     allocation_active_bitmap,
    output logic [RESIDENT_WAVE_SLOTS-1:0]     allocation_sanitized_bitmap,
    output logic [(RESIDENT_WAVE_SLOTS*ROW_WIDTH)-1:0] allocation_row_base_flat,
    output logic [(RESIDENT_WAVE_SLOTS*9)-1:0] allocation_register_count_flat
);

    localparam logic [1:0] STATE_FREE = 2'd0;
    localparam logic [1:0] STATE_RESERVED = 2'd1;
    localparam logic [1:0] STATE_ACTIVE = 2'd2;

    logic [1:0] state [0:RESIDENT_WAVE_SLOTS-1];
    logic [ROW_WIDTH-1:0] row_base [0:RESIDENT_WAVE_SLOTS-1];
    logic [ROW_WIDTH:0] row_count [0:RESIDENT_WAVE_SLOTS-1];
    logic [8:0] register_count [0:RESIDENT_WAVE_SLOTS-1];
    logic [ROW_WIDTH:0] invalidated_rows [0:RESIDENT_WAVE_SLOTS-1];

    logic [PHYSICAL_ROWS-1:0] occupied_rows;
    logic fit_found;
    logic [ROW_WIDTH-1:0] fit_base;
    logic [ROW_WIDTH:0] rows_needed;
    logic invalidate_found;
    logic [WAVE_SLOT_WIDTH-1:0] invalidate_wave_slot;
    logic [WAVE_SLOT_WIDTH-1:0] invalidate_rr_q;

    integer wave_index;
    integer row_index;
    integer base_index;
    integer probe_index;
    integer scan_offset;
    integer scan_index;
    logic candidate_free;

    always_comb begin
        occupied_rows = '0;
        for (row_index = 0; row_index < PHYSICAL_ROWS; row_index = row_index + 1) begin
            for (wave_index = 0; wave_index < RESIDENT_WAVE_SLOTS; wave_index = wave_index + 1) begin
                if ((state[wave_index] != STATE_FREE)
                    && (row_index >= row_base[wave_index])
                    && (row_index < (row_base[wave_index] + row_count[wave_index]))) begin
                    occupied_rows[row_index] = 1'b1;
                end
            end
        end

        rows_needed = (reserve_register_count + 9'd7) >> 3;
        fit_found = 1'b0;
        fit_base = '0;

        for (base_index = 0; base_index < PHYSICAL_ROWS; base_index = base_index + 1) begin
            candidate_free = 1'b1;
            if ((base_index + rows_needed) > PHYSICAL_ROWS) begin
                candidate_free = 1'b0;
            end else begin
                for (probe_index = 0; probe_index < PHYSICAL_ROWS; probe_index = probe_index + 1) begin
                    if ((probe_index < rows_needed)
                        && occupied_rows[base_index + probe_index]) begin
                        candidate_free = 1'b0;
                    end
                end
            end

            if (!fit_found && candidate_free) begin
                fit_found = 1'b1;
                fit_base = base_index[ROW_WIDTH-1:0];
            end
        end

        release_ready = 1'b0;
        if ($unsigned(release_wave_slot) < RESIDENT_WAVE_SLOTS) begin
            release_ready =
                (state[release_wave_slot] == STATE_RESERVED)
                || ((state[release_wave_slot] == STATE_ACTIVE)
                    && release_quiescent);
        end
        release_accepted = release_valid && release_ready;

        reserve_ready = 1'b0;
        if ($unsigned(reserve_wave_slot) < RESIDENT_WAVE_SLOTS) begin
            reserve_ready =
                (state[reserve_wave_slot] == STATE_FREE)
                && (reserve_register_count >= 9'd1)
                && (reserve_register_count <= 9'd256)
                && fit_found
                && !(release_accepted && (release_wave_slot == reserve_wave_slot));
        end
        reserve_accepted = reserve_valid && reserve_ready;

        activate_ready = 1'b0;
        if ($unsigned(activate_wave_slot) < RESIDENT_WAVE_SLOTS) begin
            activate_ready =
                (state[activate_wave_slot] == STATE_RESERVED)
                && (invalidated_rows[activate_wave_slot] == row_count[activate_wave_slot])
                && !(release_accepted && (release_wave_slot == activate_wave_slot));
        end
        activate_accepted = activate_valid && activate_ready;

        invalidate_found = 1'b0;
        invalidate_wave_slot = '0;
        invalidate_valid = 1'b0;
        invalidate_row = '0;

        for (scan_offset = 0; scan_offset < RESIDENT_WAVE_SLOTS; scan_offset = scan_offset + 1) begin
            scan_index = $unsigned(invalidate_rr_q) + scan_offset;
            if (scan_index >= RESIDENT_WAVE_SLOTS) begin
                scan_index = scan_index - RESIDENT_WAVE_SLOTS;
            end

            if (!invalidate_found
                && (state[scan_index] == STATE_RESERVED)
                && (invalidated_rows[scan_index] < row_count[scan_index])
                && !(release_accepted && (release_wave_slot == scan_index[WAVE_SLOT_WIDTH-1:0]))) begin
                invalidate_found = 1'b1;
                invalidate_wave_slot = scan_index[WAVE_SLOT_WIDTH-1:0];
                invalidate_valid = 1'b1;
                invalidate_row = row_base[scan_index]
                    + invalidated_rows[scan_index][ROW_WIDTH-1:0];
            end
        end

        allocation_reserved_bitmap = '0;
        allocation_active_bitmap = '0;
        allocation_sanitized_bitmap = '0;
        allocation_row_base_flat = '0;
        allocation_register_count_flat = '0;
        for (wave_index = 0; wave_index < RESIDENT_WAVE_SLOTS; wave_index = wave_index + 1) begin
            allocation_reserved_bitmap[wave_index] = state[wave_index] == STATE_RESERVED;
            allocation_active_bitmap[wave_index] = state[wave_index] == STATE_ACTIVE;
            allocation_sanitized_bitmap[wave_index] =
                (state[wave_index] == STATE_RESERVED)
                && (row_count[wave_index] != 0)
                && (invalidated_rows[wave_index] == row_count[wave_index]);
            allocation_row_base_flat[(wave_index * ROW_WIDTH) +: ROW_WIDTH] = row_base[wave_index];
            allocation_register_count_flat[(wave_index * 9) +: 9] = register_count[wave_index];
        end

        query_reserved = 1'b0;
        query_active = 1'b0;
        query_sanitized = 1'b0;
        query_row_base = '0;
        query_row_count = '0;
        query_register_count = '0;
        if ($unsigned(query_wave_slot) < RESIDENT_WAVE_SLOTS) begin
            query_reserved = state[query_wave_slot] == STATE_RESERVED;
            query_active = state[query_wave_slot] == STATE_ACTIVE;
            query_sanitized =
                (state[query_wave_slot] == STATE_RESERVED)
                && (row_count[query_wave_slot] != 0)
                && (invalidated_rows[query_wave_slot] == row_count[query_wave_slot]);
            query_row_base = row_base[query_wave_slot];
            query_row_count = row_count[query_wave_slot];
            query_register_count = register_count[query_wave_slot];
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            invalidate_rr_q <= '0;
            for (wave_index = 0; wave_index < RESIDENT_WAVE_SLOTS; wave_index = wave_index + 1) begin
                state[wave_index] <= STATE_FREE;
                row_base[wave_index] <= '0;
                row_count[wave_index] <= '0;
                register_count[wave_index] <= '0;
                invalidated_rows[wave_index] <= '0;
            end
        end else begin
            if (release_accepted) begin
                state[release_wave_slot] <= STATE_FREE;
                row_base[release_wave_slot] <= '0;
                row_count[release_wave_slot] <= '0;
                register_count[release_wave_slot] <= '0;
                invalidated_rows[release_wave_slot] <= '0;
            end

            if (reserve_accepted
                && !(release_accepted && (release_wave_slot == reserve_wave_slot))) begin
                state[reserve_wave_slot] <= STATE_RESERVED;
                row_base[reserve_wave_slot] <= fit_base;
                row_count[reserve_wave_slot] <= rows_needed;
                register_count[reserve_wave_slot] <= reserve_register_count;
                invalidated_rows[reserve_wave_slot] <= '0;
            end

            if (invalidate_valid && invalidate_ready) begin
                invalidated_rows[invalidate_wave_slot]
                    <= invalidated_rows[invalidate_wave_slot] + 1'b1;
                if ($unsigned(invalidate_wave_slot) == (RESIDENT_WAVE_SLOTS - 1)) begin
                    invalidate_rr_q <= '0;
                end else begin
                    invalidate_rr_q <= invalidate_wave_slot + 1'b1;
                end
            end

            if (activate_accepted
                && !(release_accepted && (release_wave_slot == activate_wave_slot))) begin
                state[activate_wave_slot] <= STATE_ACTIVE;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (PHYSICAL_ROWS < 1 || RESIDENT_WAVE_SLOTS < 1) begin
            $fatal(1, "pooled VGPR allocator dimensions must be nonzero");
        end
    end
`endif

endmodule
