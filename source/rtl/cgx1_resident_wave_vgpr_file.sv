// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Parameterized banked resident-wave VGPR storage.
// This is synthesizable RTL organization, not a foundry SRAM/register-file macro claim.

module cgx1_resident_wave_vgpr_file #(
    parameter integer RESIDENT_WAVE_SLOTS = 4,
    parameter integer WAVE_SLOT_WIDTH = 2
) (
    input  logic                           clk,

    input  logic                           read_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]     read_wave_slot,
    input  logic [7:0]                     read_addr0,
    input  logic [7:0]                     read_addr1,
    output logic [1023:0]                  read_data0,
    output logic [1023:0]                  read_data1,

    input  logic                           write_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]     write_wave_slot,
    input  logic [7:0]                     write_addr,
    input  logic [1023:0]                  write_data
);

    localparam integer BANK_CLASSES = 8;
    localparam integer ROWS_PER_BANK = 32;
    localparam integer WAVE_LANES = 32;
    localparam integer LANE_BITS = 32;

    logic [LANE_BITS-1:0] storage
        [0:RESIDENT_WAVE_SLOTS-1]
        [0:BANK_CLASSES-1]
        [0:ROWS_PER_BANK-1]
        [0:WAVE_LANES-1];

    integer lane_index;

    always_comb begin
        read_data0 = '0;
        read_data1 = '0;

        if (read_valid && ($unsigned(read_wave_slot) < RESIDENT_WAVE_SLOTS)) begin
            for (lane_index = 0; lane_index < WAVE_LANES; lane_index = lane_index + 1) begin
                read_data0[(lane_index * LANE_BITS) +: LANE_BITS] =
                    storage
                        [read_wave_slot]
                        [read_addr0[2:0]]
                        [read_addr0[7:3]]
                        [lane_index];

                if (read_addr1 == read_addr0) begin
                    read_data1[(lane_index * LANE_BITS) +: LANE_BITS] =
                        storage
                            [read_wave_slot]
                            [read_addr0[2:0]]
                            [read_addr0[7:3]]
                            [lane_index];
                end else begin
                    read_data1[(lane_index * LANE_BITS) +: LANE_BITS] =
                        storage
                            [read_wave_slot]
                            [read_addr1[2:0]]
                            [read_addr1[7:3]]
                            [lane_index];
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (write_valid && ($unsigned(write_wave_slot) < RESIDENT_WAVE_SLOTS)) begin
            for (lane_index = 0; lane_index < WAVE_LANES; lane_index = lane_index + 1) begin
                storage
                    [write_wave_slot]
                    [write_addr[2:0]]
                    [write_addr[7:3]]
                    [lane_index]
                    <= write_data[(lane_index * LANE_BITS) +: LANE_BITS];
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (RESIDENT_WAVE_SLOTS < 1) begin
            $fatal(1, "resident-wave VGPR storage requires at least one wave slot");
        end
        if ((1 << WAVE_SLOT_WIDTH) < RESIDENT_WAVE_SLOTS) begin
            $fatal(1, "resident-wave VGPR storage wave-slot width is too small");
        end
    end

    always_ff @(posedge clk) begin
        if (read_valid) begin
            if ($unsigned(read_wave_slot) >= RESIDENT_WAVE_SLOTS) begin
                $fatal(1, "resident-wave VGPR read used an invalid wave slot");
            end
            if ((read_addr0 != read_addr1) && (read_addr0[2:0] == read_addr1[2:0])) begin
                $fatal(1, "resident-wave VGPR read pair conflicts in one modulo-8 bank class");
            end
        end

        if (write_valid && ($unsigned(write_wave_slot) >= RESIDENT_WAVE_SLOTS)) begin
            $fatal(1, "resident-wave VGPR write used an invalid wave slot");
        end
    end
`endif

endmodule
