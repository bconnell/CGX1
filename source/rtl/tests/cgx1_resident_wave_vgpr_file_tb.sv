// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_resident_wave_vgpr_file_tb;

    localparam integer RESIDENT_WAVE_SLOTS = 4;
    localparam integer WAVE_SLOT_WIDTH = 2;

    logic clk = 1'b0;

    logic read_valid;
    logic [WAVE_SLOT_WIDTH-1:0] read_wave_slot;
    logic [7:0] read_addr0;
    logic [7:0] read_addr1;
    logic [1023:0] read_data0;
    logic [1023:0] read_data1;

    logic write_valid;
    logic [WAVE_SLOT_WIDTH-1:0] write_wave_slot;
    logic [7:0] write_addr;
    logic [1023:0] write_data;

    always #5 clk = ~clk;

    cgx1_resident_wave_vgpr_file #(
        .RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),
        .WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)
    ) dut (
        .clk(clk),
        .read_valid(read_valid),
        .read_wave_slot(read_wave_slot),
        .read_addr0(read_addr0),
        .read_addr1(read_addr1),
        .read_data0(read_data0),
        .read_data1(read_data1),
        .write_valid(write_valid),
        .write_wave_slot(write_wave_slot),
        .write_addr(write_addr),
        .write_data(write_data)
    );

    function automatic [1023:0] make_wave(
        input logic [7:0] wave_tag,
        input logic [7:0] register_tag,
        input logic [7:0] salt
    );
        integer lane;
        begin
            make_wave = '0;
            for (lane = 0; lane < 32; lane = lane + 1) begin
                make_wave[(lane * 32) +: 32] = {
                    wave_tag,
                    register_tag,
                    salt,
                    lane[7:0]
                };
            end
        end
    endfunction

    task automatic write_register(
        input logic [WAVE_SLOT_WIDTH-1:0] slot,
        input logic [7:0] address,
        input logic [1023:0] value
    );
        begin
            @(negedge clk);
            write_valid = 1'b1;
            write_wave_slot = slot;
            write_addr = address;
            write_data = value;
            @(posedge clk);
            #1;
            @(negedge clk);
            write_valid = 1'b0;
        end
    endtask

    task automatic expect_pair(
        input logic [WAVE_SLOT_WIDTH-1:0] slot,
        input logic [7:0] address0,
        input logic [7:0] address1,
        input logic [1023:0] expected0,
        input logic [1023:0] expected1
    );
        begin
            read_valid = 1'b1;
            read_wave_slot = slot;
            read_addr0 = address0;
            read_addr1 = address1;
            #1;

            if (read_data0 !== expected0) begin
                $fatal(1, "resident-wave VGPR read0 mismatch for slot %0d register %0d", slot, address0);
            end
            if (read_data1 !== expected1) begin
                $fatal(1, "resident-wave VGPR read1 mismatch for slot %0d register %0d", slot, address1);
            end

            read_valid = 1'b0;
            #1;
            if (read_data0 !== '0 || read_data1 !== '0) begin
                $fatal(1, "resident-wave VGPR read outputs did not return to zero while inactive");
            end
        end
    endtask

    logic [1023:0] wave0_a;
    logic [1023:0] wave0_b;
    logic [1023:0] wave0_c0;
    logic [1023:0] wave0_c1;
    logic [1023:0] wave1_a;
    logic [1023:0] wave1_b;
    logic [1023:0] wave2_d;
    integer lane;

    initial begin
        read_valid = 1'b0;
        read_wave_slot = '0;
        read_addr0 = '0;
        read_addr1 = '0;

        write_valid = 1'b0;
        write_wave_slot = '0;
        write_addr = '0;
        write_data = '0;

        wave0_a = make_wave(8'h10, 8'd64, 8'hA1);
        wave0_b = make_wave(8'h10, 8'd68, 8'hB1);
        wave0_c0 = make_wave(8'h10, 8'd32, 8'hC0);
        wave0_c1 = make_wave(8'h10, 8'd33, 8'hC1);
        wave1_a = make_wave(8'h21, 8'd64, 8'hA2);
        wave1_b = make_wave(8'h21, 8'd68, 8'hB2);
        wave2_d = make_wave(8'h32, 8'd40, 8'hD0);

        write_register(2'd0, 8'd64, wave0_a);
        write_register(2'd0, 8'd68, wave0_b);
        write_register(2'd0, 8'd32, wave0_c0);
        write_register(2'd0, 8'd33, wave0_c1);

        write_register(2'd1, 8'd64, wave1_a);
        write_register(2'd1, 8'd68, wave1_b);
        write_register(2'd2, 8'd40, wave2_d);

        // Canonical A/B source bases occupy different modulo-8 bank classes.
        expect_pair(2'd0, 8'd64, 8'd68, wave0_a, wave0_b);

        // Exact A/B aliasing is a single stored value delivered to both read buses.
        expect_pair(2'd0, 8'd64, 8'd64, wave0_a, wave0_a);

        // C/D capture uses adjacent registers, which occupy different bank classes.
        expect_pair(2'd0, 8'd32, 8'd33, wave0_c0, wave0_c1);

        // Architectural VGPR numbers are independent between resident waves.
        expect_pair(2'd1, 8'd64, 8'd68, wave1_a, wave1_b);
        expect_pair(2'd0, 8'd64, 8'd68, wave0_a, wave0_b);

        // A one-register matrix writeback is visible on the same banked organization.
        expect_pair(2'd2, 8'd40, 8'd40, wave2_d, wave2_d);

        // The 1,024-bit whole-wave bus preserves canonical lane order.
        for (lane = 0; lane < 32; lane = lane + 1) begin
            if (wave0_a[(lane * 32) +: 32] !== {8'h10, 8'd64, 8'hA1, lane[7:0]}) begin
                $fatal(1, "resident-wave VGPR lane packing mismatch at lane %0d", lane);
            end
        end

        $display("[pass] CGX 1 resident-wave VGPR storage checks passed.");
        $finish;
    end

endmodule
