// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_pooled_vgpr_storage_tb;
    localparam integer PHYSICAL_ROWS = 8;
    localparam integer ROW_WIDTH = 3;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic invalidate_valid;
    logic [ROW_WIDTH-1:0] invalidate_row;
    logic invalidate_ready;
    logic read_valid;
    logic [ROW_WIDTH-1:0] read0_row;
    logic [2:0] read0_bank;
    logic [ROW_WIDTH-1:0] read1_row;
    logic [2:0] read1_bank;
    logic read_ready;
    logic read_bank_conflict;
    logic read0_initialized;
    logic [1023:0] read0_data;
    logic read1_initialized;
    logic [1023:0] read1_data;
    logic write_valid;
    logic [ROW_WIDTH-1:0] write_row;
    logic [2:0] write_bank;
    logic [31:0] write_lane_mask;
    logic [1023:0] write_data;
    logic write_ready;
    logic [(PHYSICAL_ROWS*8)-1:0] valid_bitmap;

    logic [1023:0] wave_a;
    logic [1023:0] wave_b;
    integer lane;

    always #5 clk = ~clk;

    cgx1_pooled_vgpr_storage #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS),
        .ROW_WIDTH(ROW_WIDTH)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .invalidate_valid(invalidate_valid),
        .invalidate_row(invalidate_row),
        .invalidate_ready(invalidate_ready),
        .read_valid(read_valid),
        .read0_row(read0_row), .read0_bank(read0_bank),
        .read1_row(read1_row), .read1_bank(read1_bank),
        .read_ready(read_ready), .read_bank_conflict(read_bank_conflict),
        .read0_initialized(read0_initialized), .read0_data(read0_data),
        .read1_initialized(read1_initialized), .read1_data(read1_data),
        .write_valid(write_valid), .write_row(write_row), .write_bank(write_bank),
        .write_lane_mask(write_lane_mask), .write_data(write_data), .write_ready(write_ready),
        .valid_bitmap(valid_bitmap)
    );

    function automatic [1023:0] pattern(input logic [7:0] tag);
        integer i;
        begin
            pattern = '0;
            for (i = 0; i < 32; i = i + 1)
                pattern[(i * 32) +: 32] = {tag, 16'hCAFE, i[7:0]};
        end
    endfunction

    task automatic invalidate(input logic [ROW_WIDTH-1:0] row);
        begin
            @(negedge clk);
            invalidate_row = row;
            invalidate_valid = 1'b1;
            #1;
            if (!invalidate_ready) $fatal(1, "valid invalidation row was not ready");
            @(posedge clk); #1;
            @(negedge clk);
            invalidate_valid = 1'b0;
        end
    endtask

    task automatic write_full(input logic [ROW_WIDTH-1:0] row, input logic [2:0] bank, input logic [1023:0] value);
        begin
            @(negedge clk);
            write_row = row;
            write_bank = bank;
            write_lane_mask = 32'hFFFFFFFF;
            write_data = value;
            write_valid = 1'b1;
            #1;
            if (!write_ready) $fatal(1, "valid pooled VGPR write was not ready");
            @(posedge clk); #1;
            @(negedge clk);
            write_valid = 1'b0;
        end
    endtask

    initial begin
        invalidate_valid = 1'b0;
        invalidate_row = '0;
        read_valid = 1'b0;
        read0_row = '0;
        read0_bank = '0;
        read1_row = '0;
        read1_bank = '0;
        write_valid = 1'b0;
        write_row = '0;
        write_bank = '0;
        write_lane_mask = '0;
        write_data = '0;
        wave_a = pattern(8'hA1);
        wave_b = pattern(8'hB2);

        repeat (2) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        invalidate(3'd0);
        invalidate(3'd1);
        invalidate(3'd2);
        invalidate(3'd3);
        write_full(3'd0, 3'd0, wave_a);
        write_full(3'd0, 3'd4, wave_b);

        read_valid = 1'b1;
        read0_row = 3'd0; read0_bank = 3'd0;
        read1_row = 3'd0; read1_bank = 3'd4;
        #1;
        if (!read_ready || read_bank_conflict || !read0_initialized || !read1_initialized)
            $fatal(1, "conflict-free pooled read pair was rejected");
        if (read0_data !== wave_a || read1_data !== wave_b)
            $fatal(1, "pooled read pair data mismatch");

        read1_row = 3'd0; read1_bank = 3'd0;
        #1;
        if (!read_ready || read_bank_conflict || read1_data !== wave_a)
            $fatal(1, "exact alias was not broadcast");

        read1_row = 3'd1; read1_bank = 3'd0;
        #1;
        if (read_ready || !read_bank_conflict)
            $fatal(1, "distinct same-bank read pair was not rejected");
        read_valid = 1'b0;

        @(negedge clk);
        write_row = 3'd2;
        write_bank = 3'd3;
        write_lane_mask = 32'h00000001;
        write_data = wave_b;
        write_valid = 1'b1;
        @(posedge clk); #1;
        @(negedge clk);
        write_valid = 1'b0;

        read_valid = 1'b1;
        read0_row = 3'd2; read0_bank = 3'd3;
        read1_row = 3'd2; read1_bank = 3'd3;
        #1;
        if (!read_ready || !read0_initialized || read0_data[31:0] !== wave_b[31:0])
            $fatal(1, "first masked write did not initialize lane zero");
        for (lane = 1; lane < 32; lane = lane + 1)
            if (read0_data[(lane * 32) +: 32] !== 32'd0)
                $fatal(1, "first masked write exposed stale inactive lane %0d", lane);
        read_valid = 1'b0;

        @(negedge clk);
        write_row = 3'd3;
        write_bank = 3'd2;
        write_lane_mask = 32'd0;
        write_data = wave_a;
        write_valid = 1'b1;
        @(posedge clk); #1;
        @(negedge clk);
        write_valid = 1'b0;
        read_valid = 1'b1;
        read0_row = 3'd3; read0_bank = 3'd2;
        read1_row = 3'd3; read1_bank = 3'd2;
        #1;
        if (read0_initialized || read1_initialized)
            $fatal(1, "zero-lane write incorrectly initialized a register");
        read_valid = 1'b0;

        read_valid = 1'b1;
        read0_row = 3'd0; read0_bank = 3'd0;
        read1_row = 3'd0; read1_bank = 3'd4;
        write_valid = 1'b1;
        write_row = 3'd1; write_bank = 3'd1;
        write_lane_mask = 32'hFFFFFFFF;
        #1;
        if (read_ready || write_ready)
            $fatal(1, "simultaneous matrix read/write was not backpressured");
        read_valid = 1'b0;
        write_valid = 1'b0;

        invalidate_valid = 1'b1;
        invalidate_row = 3'd0;
        read_valid = 1'b1;
        read0_row = 3'd0; read0_bank = 3'd0;
        read1_row = 3'd0; read1_bank = 3'd4;
        #1;
        if (!invalidate_ready || read_ready)
            $fatal(1, "invalidation/read collision did not apply invalidation priority");
        invalidate_valid = 1'b0;
        read_valid = 1'b0;

        $display("[pass] CGX 1 pooled VGPR storage checks passed.");
        $finish;
    end
endmodule
