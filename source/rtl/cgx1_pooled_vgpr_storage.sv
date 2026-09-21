// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Candidate pooled VGPR storage/validity RTL. Not a foundry memory-macro claim.

module cgx1_pooled_vgpr_storage #(
    parameter integer PHYSICAL_ROWS = 128,
    parameter integer ROW_WIDTH = (PHYSICAL_ROWS <= 1) ? 1 : $clog2(PHYSICAL_ROWS)
) (
    input  logic                   clk,
    input  logic                   reset_n,
    input  logic                   invalidate_valid,
    input  logic [ROW_WIDTH-1:0]   invalidate_row,
    output logic                   invalidate_ready,
    input  logic                   read_valid,
    input  logic [ROW_WIDTH-1:0]   read0_row,
    input  logic [2:0]             read0_bank,
    input  logic [ROW_WIDTH-1:0]   read1_row,
    input  logic [2:0]             read1_bank,
    output logic                   read_ready,
    output logic                   read_bank_conflict,
    output logic                   read0_initialized,
    output logic [1023:0]          read0_data,
    output logic                   read1_initialized,
    output logic [1023:0]          read1_data,
    input  logic                   write_valid,
    input  logic [ROW_WIDTH-1:0]   write_row,
    input  logic [2:0]             write_bank,
    input  logic [31:0]            write_lane_mask,
    input  logic [1023:0]          write_data,
    output logic                   write_ready,
    output logic [(PHYSICAL_ROWS*8)-1:0] valid_bitmap
);

    logic [1023:0] data [0:PHYSICAL_ROWS-1][0:7];
    logic [7:0] initialized [0:PHYSICAL_ROWS-1];
    integer lane;
    integer reset_row;
    integer valid_row;
    integer valid_bank;
    logic [1023:0] write_next_data;

    always_comb begin
        valid_bitmap = '0;
        for (valid_row = 0; valid_row < PHYSICAL_ROWS; valid_row = valid_row + 1) begin
            for (valid_bank = 0; valid_bank < 8; valid_bank = valid_bank + 1) begin
                valid_bitmap[(valid_row * 8) + valid_bank] = initialized[valid_row][valid_bank];
            end
        end
        invalidate_ready = reset_n && (invalidate_row < PHYSICAL_ROWS);
        read_bank_conflict = read_valid
            && (read0_bank == read1_bank)
            && (read0_row != read1_row);
        read_ready = reset_n
            && !write_valid
            && !read_bank_conflict
            && (read0_row < PHYSICAL_ROWS)
            && (read1_row < PHYSICAL_ROWS)
            && !(invalidate_valid
                && ((invalidate_row == read0_row)
                    || (invalidate_row == read1_row)));
        write_ready = reset_n
            && !read_valid
            && (write_row < PHYSICAL_ROWS)
            && !(invalidate_valid && (invalidate_row == write_row));

        read0_initialized = 1'b0;
        read0_data = '0;
        read1_initialized = 1'b0;
        read1_data = '0;

        if (read_valid && read_ready) begin
            read0_initialized = initialized[read0_row][read0_bank];
            if (initialized[read0_row][read0_bank]) begin
                read0_data = data[read0_row][read0_bank];
            end

            if ((read1_row == read0_row) && (read1_bank == read0_bank)) begin
                read1_initialized = read0_initialized;
                read1_data = read0_data;
            end else begin
                read1_initialized = initialized[read1_row][read1_bank];
                if (initialized[read1_row][read1_bank]) begin
                    read1_data = data[read1_row][read1_bank];
                end
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (reset_row = 0; reset_row < PHYSICAL_ROWS; reset_row = reset_row + 1) begin
                initialized[reset_row] <= 8'h00;
            end
        end else begin
            if (invalidate_valid && invalidate_ready) begin
                initialized[invalidate_row] <= 8'h00;
            end

            if (write_valid && write_ready && (|write_lane_mask)) begin
                if (initialized[write_row][write_bank]) begin
                    write_next_data = data[write_row][write_bank];
                end else begin
                    write_next_data = '0;
                end

                for (lane = 0; lane < 32; lane = lane + 1) begin
                    if (write_lane_mask[lane]) begin
                        write_next_data[(lane * 32) +: 32]
                            = write_data[(lane * 32) +: 32];
                    end
                end

                data[write_row][write_bank] <= write_next_data;
                initialized[write_row][write_bank] <= 1'b1;
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (invalidate_valid && (invalidate_row >= PHYSICAL_ROWS)) begin
            $fatal(1, "pooled VGPR invalidation row is out of range");
        end
        if (write_valid && (write_row >= PHYSICAL_ROWS)) begin
            $fatal(1, "pooled VGPR write row is out of range");
        end
    end
`endif

endmodule
