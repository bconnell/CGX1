// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_resident_wave_vgpr_allocator_tb;
    localparam integer PHYSICAL_ROWS = 16;
    localparam integer RESIDENT_WAVE_SLOTS = 4;
    localparam integer ROW_WIDTH = 4;
    localparam integer WAVE_SLOT_WIDTH = 2;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic reserve_valid;
    logic [WAVE_SLOT_WIDTH-1:0] reserve_wave_slot;
    logic [8:0] reserve_register_count;
    logic reserve_ready;
    logic reserve_accepted;
    logic activate_valid;
    logic [WAVE_SLOT_WIDTH-1:0] activate_wave_slot;
    logic activate_ready;
    logic activate_accepted;
    logic release_valid;
    logic [WAVE_SLOT_WIDTH-1:0] release_wave_slot;
    logic release_quiescent;
    logic release_ready;
    logic release_accepted;
    logic invalidate_valid;
    logic [ROW_WIDTH-1:0] invalidate_row;
    logic invalidate_ready;
    logic [WAVE_SLOT_WIDTH-1:0] query_wave_slot;
    logic query_reserved;
    logic query_active;
    logic query_sanitized;
    logic [ROW_WIDTH-1:0] query_row_base;
    logic [ROW_WIDTH:0] query_row_count;
    logic [8:0] query_register_count;
    logic [RESIDENT_WAVE_SLOTS-1:0] allocation_reserved_bitmap;
    logic [RESIDENT_WAVE_SLOTS-1:0] allocation_active_bitmap;
    logic [RESIDENT_WAVE_SLOTS-1:0] allocation_sanitized_bitmap;
    logic [(RESIDENT_WAVE_SLOTS*ROW_WIDTH)-1:0] allocation_row_base_flat;
    logic [(RESIDENT_WAVE_SLOTS*9)-1:0] allocation_register_count_flat;

    logic mapper_active;
    logic [ROW_WIDTH-1:0] mapper_row_base;
    logic [8:0] mapper_register_count;
    logic [7:0] mapper_register;
    logic mapper_valid;
    logic [ROW_WIDTH-1:0] mapper_row;
    logic [2:0] mapper_bank;

    logic [7:0] guard_d;
    logic [7:0] guard_a;
    logic [7:0] guard_b;
    logic guard_layout_legal;
    logic guard_range_legal;
    logic guard_legal;

    integer timeout;

    always #5 clk = ~clk;

    cgx1_resident_wave_vgpr_allocator #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS),
        .RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),
        .ROW_WIDTH(ROW_WIDTH),
        .WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)
    ) allocator (
        .clk(clk), .reset_n(reset_n),
        .reserve_valid(reserve_valid),
        .reserve_wave_slot(reserve_wave_slot),
        .reserve_register_count(reserve_register_count),
        .reserve_ready(reserve_ready),
        .reserve_accepted(reserve_accepted),
        .activate_valid(activate_valid),
        .activate_wave_slot(activate_wave_slot),
        .activate_ready(activate_ready),
        .activate_accepted(activate_accepted),
        .release_valid(release_valid),
        .release_wave_slot(release_wave_slot),
        .release_quiescent(release_quiescent),
        .release_ready(release_ready),
        .release_accepted(release_accepted),
        .invalidate_valid(invalidate_valid),
        .invalidate_row(invalidate_row),
        .invalidate_ready(invalidate_ready),
        .query_wave_slot(query_wave_slot),
        .query_reserved(query_reserved),
        .query_active(query_active),
        .query_sanitized(query_sanitized),
        .query_row_base(query_row_base),
        .query_row_count(query_row_count),
        .query_register_count(query_register_count),
        .allocation_reserved_bitmap(allocation_reserved_bitmap),
        .allocation_active_bitmap(allocation_active_bitmap),
        .allocation_sanitized_bitmap(allocation_sanitized_bitmap),
        .allocation_row_base_flat(allocation_row_base_flat),
        .allocation_register_count_flat(allocation_register_count_flat)
    );

    cgx1_pooled_vgpr_mapper #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS),
        .ROW_WIDTH(ROW_WIDTH)
    ) mapper (
        .allocation_active(mapper_active),
        .allocation_row_base(mapper_row_base),
        .allocation_register_count(mapper_register_count),
        .architectural_register(mapper_register),
        .address_valid(mapper_valid),
        .physical_row(mapper_row),
        .bank_class(mapper_bank)
    );

    cgx1_matrix_vgpr_allocation_guard guard (
        .allocation_active(mapper_active),
        .allocation_register_count(mapper_register_count),
        .destination_base(guard_d),
        .source_a_base(guard_a),
        .source_b_base(guard_b),
        .layout_legal(guard_layout_legal),
        .allocation_range_legal(guard_range_legal),
        .matrix_vgpr_legal(guard_legal)
    );

    task automatic reserve_wave(input logic [WAVE_SLOT_WIDTH-1:0] slot, input logic [8:0] count);
        begin
            @(negedge clk);
            reserve_wave_slot = slot;
            reserve_register_count = count;
            reserve_valid = 1'b1;
            #1;
            if (!reserve_ready) $fatal(1, "reserve request was unexpectedly blocked");
            @(posedge clk); #1;
            if (!reserve_accepted) $fatal(1, "reserve request was not accepted");
            @(negedge clk);
            reserve_valid = 1'b0;
        end
    endtask

    task automatic wait_invalidation_complete(input logic [WAVE_SLOT_WIDTH-1:0] slot);
        begin
            activate_wave_slot = slot;
            timeout = 0;
            while (!activate_ready) begin
                @(posedge clk); #1;
                timeout = timeout + 1;
                if (timeout > 32) $fatal(1, "allocation invalidation did not complete");
            end
        end
    endtask

    task automatic activate_wave(input logic [WAVE_SLOT_WIDTH-1:0] slot);
        begin
            wait_invalidation_complete(slot);
            @(negedge clk);
            activate_wave_slot = slot;
            activate_valid = 1'b1;
            #1;
            if (!activate_ready) $fatal(1, "activate request was unexpectedly blocked");
            @(posedge clk); #1;
            if (!activate_accepted) $fatal(1, "activate request was not accepted");
            @(negedge clk);
            activate_valid = 1'b0;
        end
    endtask

    task automatic release_wave(input logic [WAVE_SLOT_WIDTH-1:0] slot);
        begin
            @(negedge clk);
            release_wave_slot = slot;
            release_valid = 1'b1;
            release_quiescent = 1'b1;
            #1;
            if (!release_ready) $fatal(1, "release request was unexpectedly blocked");
            @(posedge clk); #1;
            if (!release_accepted) $fatal(1, "release request was not accepted");
            @(negedge clk);
            release_valid = 1'b0;
        end
    endtask

    initial begin
        reserve_valid = 1'b0;
        reserve_wave_slot = '0;
        reserve_register_count = '0;
        activate_valid = 1'b0;
        activate_wave_slot = '0;
        release_valid = 1'b0;
        release_wave_slot = '0;
        release_quiescent = 1'b0;
        invalidate_ready = 1'b1;
        query_wave_slot = '0;
        mapper_active = 1'b0;
        mapper_row_base = '0;
        mapper_register_count = '0;
        mapper_register = '0;
        guard_d = '0;
        guard_a = '0;
        guard_b = '0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        reserve_wave(2'd0, 9'd9);
        query_wave_slot = 2'd0;
        #1;
        if (!query_reserved || query_row_base != 0 || query_row_count != 2 || query_register_count != 9)
            $fatal(1, "9-VGPR reservation metadata mismatch");

        wait_invalidation_complete(2'd0);
        activate_wave(2'd0);
        query_wave_slot = 2'd0;
        #1;
        if (!query_active || query_reserved) $fatal(1, "wave 0 did not become active");

        mapper_active = query_active;
        mapper_row_base = query_row_base;
        mapper_register_count = query_register_count;
        mapper_register = 8'd8;
        #1;
        if (!mapper_valid || mapper_row != 1 || mapper_bank != 0)
            $fatal(1, "VGPR 8 translation mismatch for 9-register allocation");
        mapper_register = 8'd9;
        #1;
        if (mapper_valid) $fatal(1, "row rounding widened exact 9-register allocation");

        guard_d = 8'd0;
        guard_a = 8'd0;
        guard_b = 8'd8;
        #1;
        if (guard_range_legal) $fatal(1, "matrix range guard ignored exact allocation count");

        release_wave(2'd0);
        reserve_wave(2'd1, 9'd72);
        activate_wave(2'd1);
        query_wave_slot = 2'd1;
        #1;
        if (!allocation_active_bitmap[1]
            || allocation_row_base_flat[(1*ROW_WIDTH) +: ROW_WIDTH] != query_row_base
            || allocation_register_count_flat[(1*9) +: 9] != query_register_count)
            $fatal(1, "flattened allocation metadata diverged from query port");
        mapper_active = query_active;
        mapper_row_base = query_row_base;
        mapper_register_count = query_register_count;
        guard_d = 8'd32;
        guard_a = 8'd64;
        guard_b = 8'd68;
        #1;
        if (!guard_layout_legal || !guard_range_legal || !guard_legal)
            $fatal(1, "canonical matrix allocation was rejected");

        release_wave_slot = 2'd1;
        release_quiescent = 1'b0;
        release_valid = 1'b1;
        #1;
        if (release_ready || release_accepted)
            $fatal(1, "active release ignored the quiescent requirement");
        release_quiescent = 1'b1;

        release_wave_slot = 2'd1;
        release_valid = 1'b1;
        activate_wave_slot = 2'd1;
        activate_valid = 1'b1;
        #1;
        if (!release_accepted || activate_accepted)
            $fatal(1, "same-wave release/activate precedence is incorrect");
        @(posedge clk); #1;
        @(negedge clk);
        release_valid = 1'b0;
        release_quiescent = 1'b0;
        activate_valid = 1'b0;

        reserve_wave(2'd2, 9'd8);
        query_wave_slot = 2'd2;
        #1;
        if (query_row_base != 0) $fatal(1, "first-fit allocator did not reuse released row zero");

        $display("[pass] CGX 1 pooled VGPR allocator/mapper/range checks passed.");
        $finish;
    end
endmodule
