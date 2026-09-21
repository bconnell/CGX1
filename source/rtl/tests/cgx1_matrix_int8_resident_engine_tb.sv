// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_matrix_int8_resident_engine_tb;

    localparam integer RESIDENT_WAVE_SLOTS = 4;
    localparam integer WAVE_SLOT_WIDTH = 2;

    logic clk = 1'b0;
    logic reset_n = 1'b0;

    logic [RESIDENT_WAVE_SLOTS-1:0] matrix_request_valid;
    logic [RESIDENT_WAVE_SLOTS-1:0] matrix_request_full_wave_active;
    logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_d_base;
    logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_a_base;
    logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_b_base;
    logic [RESIDENT_WAVE_SLOTS-1:0] matrix_request_ready;
    logic [RESIDENT_WAVE_SLOTS-1:0] matrix_request_accepted;

    logic illegal_issue;
    logic [WAVE_SLOT_WIDTH-1:0] illegal_wave_slot;

    logic rf_read_valid;
    logic [7:0] rf_read_addr0;
    logic [7:0] rf_read_addr1;
    logic [WAVE_SLOT_WIDTH-1:0] rf_read_wave_slot;
    logic [1023:0] rf_read_data0;
    logic [1023:0] rf_read_data1;

    logic rf_write_valid;
    logic [7:0] rf_write_addr;
    logic [WAVE_SLOT_WIDTH-1:0] rf_write_wave_slot;
    logic [1023:0] rf_write_data;

    logic ordinary_issue_valid;
    logic [WAVE_SLOT_WIDTH-1:0] ordinary_wave_slot;
    logic [255:0] ordinary_read_mask;
    logic [255:0] ordinary_write_mask;
    logic ordinary_uses_read_ports;
    logic ordinary_uses_write_port;
    logic ordinary_raw_hazard;
    logic ordinary_waw_hazard;
    logic ordinary_war_hazard;
    logic ordinary_read_port_conflict;
    logic ordinary_write_port_conflict;
    logic ordinary_ready;
    logic ordinary_issue_accepted;

    logic [RESIDENT_WAVE_SLOTS-1:0] resident_wave_busy;

    logic [1023:0] vgpr [0:RESIDENT_WAVE_SLOTS-1][0:255];

    integer wave_index;
    integer reg_index;
    integer accepted_count;
    integer accepted_slots [0:7];
    integer write_count [0:RESIDENT_WAVE_SLOTS-1];
    integer timeout;

    always #5 clk = ~clk;

    assign rf_read_data0 = vgpr[rf_read_wave_slot][rf_read_addr0];
    assign rf_read_data1 = vgpr[rf_read_wave_slot][rf_read_addr1];

    always_ff @(posedge clk) begin
        if (reset_n && rf_write_valid) begin
            vgpr[rf_write_wave_slot][rf_write_addr] <= rf_write_data;
            write_count[rf_write_wave_slot] <=
                write_count[rf_write_wave_slot] + 1;
        end
    end

    always @(posedge clk) begin
        if (reset_n) begin
            for (wave_index = 0; wave_index < RESIDENT_WAVE_SLOTS; wave_index = wave_index + 1) begin
                if (matrix_request_accepted[wave_index]) begin
                    accepted_slots[accepted_count] = wave_index;
                    accepted_count = accepted_count + 1;
                end
            end
        end
    end

    cgx1_matrix_int8_resident_engine #(
        .RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),
        .WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .matrix_request_valid(matrix_request_valid),
        .matrix_request_full_wave_active(matrix_request_full_wave_active),
        .matrix_request_d_base(matrix_request_d_base),
        .matrix_request_a_base(matrix_request_a_base),
        .matrix_request_b_base(matrix_request_b_base),
        .matrix_request_ready(matrix_request_ready),
        .matrix_request_accepted(matrix_request_accepted),
        .illegal_issue(illegal_issue),
        .illegal_wave_slot(illegal_wave_slot),
        .rf_read_valid(rf_read_valid),
        .rf_read_addr0(rf_read_addr0),
        .rf_read_addr1(rf_read_addr1),
        .rf_read_wave_slot(rf_read_wave_slot),
        .rf_read_data0(rf_read_data0),
        .rf_read_data1(rf_read_data1),
        .rf_write_valid(rf_write_valid),
        .rf_write_addr(rf_write_addr),
        .rf_write_wave_slot(rf_write_wave_slot),
        .rf_write_data(rf_write_data),
        .ordinary_issue_valid(ordinary_issue_valid),
        .ordinary_wave_slot(ordinary_wave_slot),
        .ordinary_read_mask(ordinary_read_mask),
        .ordinary_write_mask(ordinary_write_mask),
        .ordinary_uses_read_ports(ordinary_uses_read_ports),
        .ordinary_uses_write_port(ordinary_uses_write_port),
        .ordinary_raw_hazard(ordinary_raw_hazard),
        .ordinary_waw_hazard(ordinary_waw_hazard),
        .ordinary_war_hazard(ordinary_war_hazard),
        .ordinary_read_port_conflict(ordinary_read_port_conflict),
        .ordinary_write_port_conflict(ordinary_write_port_conflict),
        .ordinary_ready(ordinary_ready),
        .ordinary_issue_accepted(ordinary_issue_accepted),
        .resident_wave_busy(resident_wave_busy)
    );

    task automatic set_request(
        input integer slot,
        input logic full_wave,
        input logic [7:0] d_base,
        input logic [7:0] a_base,
        input logic [7:0] b_base
    );
        begin
            matrix_request_full_wave_active[slot] = full_wave;
            matrix_request_d_base[(slot * 8) +: 8] = d_base;
            matrix_request_a_base[(slot * 8) +: 8] = a_base;
            matrix_request_b_base[(slot * 8) +: 8] = b_base;
        end
    endtask

    task automatic set_one_read(
        input integer slot,
        input integer reg_number
    );
        begin
            ordinary_issue_valid = 1'b1;
            ordinary_wave_slot = slot[WAVE_SLOT_WIDTH-1:0];
            ordinary_read_mask = '0;
            ordinary_write_mask = '0;
            ordinary_read_mask[reg_number] = 1'b1;
            ordinary_uses_read_ports = 1'b1;
            ordinary_uses_write_port = 1'b0;
        end
    endtask

    task automatic clear_ordinary;
        begin
            ordinary_issue_valid = 1'b0;
            ordinary_wave_slot = '0;
            ordinary_read_mask = '0;
            ordinary_write_mask = '0;
            ordinary_uses_read_ports = 1'b0;
            ordinary_uses_write_port = 1'b0;
        end
    endtask

    initial begin
        matrix_request_valid = '0;
        matrix_request_full_wave_active = '0;
        matrix_request_d_base = '0;
        matrix_request_a_base = '0;
        matrix_request_b_base = '0;
        clear_ordinary();

        accepted_count = 0;
        for (wave_index = 0; wave_index < RESIDENT_WAVE_SLOTS; wave_index = wave_index + 1) begin
            write_count[wave_index] = 0;
            for (reg_index = 0; reg_index < 256; reg_index = reg_index + 1) begin
                vgpr[wave_index][reg_index] = '0;
            end
        end

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        // Two resident waves request the engine together. Round-robin starts at slot 0.
        set_request(0, 1'b1, 8'd32, 8'd64, 8'd68);
        set_request(1, 1'b1, 8'd64, 8'd32, 8'd36);
        matrix_request_valid[0] = 1'b1;
        matrix_request_valid[1] = 1'b1;

        #1;
        if (!matrix_request_ready[0] || matrix_request_ready[1]) begin
            $fatal(1, "resident-wave arbiter did not select slot 0 first");
        end

        @(posedge clk);
        #1;
        @(negedge clk);
        matrix_request_valid[0] = 1'b0;

        timeout = 0;
        while (!resident_wave_busy[0]) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
            if (timeout > 8) begin
                $fatal(1, "wave 0 reservation was not recorded");
            end
        end

        // Wait for an execute-only cycle so the VGPR port itself is not the reason for a stall.
        timeout = 0;
        while (rf_read_valid || rf_write_valid) begin
            @(negedge clk);
            #1;
            timeout = timeout + 1;
            if (timeout > 16) begin
                $fatal(1, "did not reach an idle VGPR-port cycle");
            end
        end

        // D32 is pending for wave 0.
        set_one_read(0, 32);
        #1;
        if (!ordinary_raw_hazard || ordinary_ready || ordinary_issue_accepted) begin
            $fatal(1, "ordinary issue read a pending destination in the same wave");
        end

        // The same architectural VGPR number belongs to a different wave and is independent.
        set_one_read(1, 32);
        #1;
        if (ordinary_raw_hazard || !ordinary_ready || !ordinary_issue_accepted) begin
            $fatal(1, "ordinary issue falsely inherited another wave's VGPR hazard");
        end
        clear_ordinary();

        // Wave 1 uses A32 while wave 0 still owns D32. This must not create
        // a cross-wave matrix dependency.
        timeout = 0;
        while (!matrix_request_ready[1]) begin
            @(negedge clk);
            #1;
            timeout = timeout + 1;
            if (timeout > 24) begin
                $fatal(1, "wave 1 matrix request was not admitted at the next issue interval");
            end
        end
        if (!resident_wave_busy[0]) begin
            $fatal(1, "wave 0 completed before the cross-wave dependency check");
        end

        @(posedge clk);
        #1;
        @(negedge clk);
        matrix_request_valid[1] = 1'b0;

        timeout = 0;
        while (accepted_count < 2) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
            if (timeout > 4) begin
                $fatal(1, "second resident-wave request did not produce an acceptance pulse");
            end
        end
        if (accepted_slots[0] != 0 || accepted_slots[1] != 1) begin
            $fatal(1, "resident-wave round-robin acceptance order mismatch");
        end

        // During wave 1's pending D64 window, only wave 1 sees the RAW hazard.
        timeout = 0;
        while (!resident_wave_busy[1] || rf_read_valid || rf_write_valid) begin
            @(negedge clk);
            #1;
            timeout = timeout + 1;
            if (timeout > 24) begin
                $fatal(1, "did not reach wave 1 execute window");
            end
        end
        set_one_read(1, 64);
        #1;
        if (!ordinary_raw_hazard || ordinary_ready) begin
            $fatal(1, "wave 1 pending destination was not enforced");
        end
        set_one_read(0, 64);
        #1;
        if (ordinary_raw_hazard || !ordinary_ready) begin
            $fatal(1, "wave 0 falsely inherited wave 1 destination state");
        end
        clear_ordinary();

        // Queue a same-wave dependency on wave 0's still-pending D32.
        set_request(0, 1'b1, 8'd96, 8'd32, 8'd36);
        matrix_request_valid[0] = 1'b1;

        timeout = 0;
        while (!matrix_request_ready[0]) begin
            if (resident_wave_busy[0] && matrix_request_ready[0]) begin
                $fatal(1, "same-wave dependent request became ready before D32 completed");
            end
            @(negedge clk);
            #1;
            timeout = timeout + 1;
            if (timeout > 32) begin
                $fatal(1, "same-wave dependent request did not become ready after completion");
            end
        end
        if (resident_wave_busy[0]) begin
            $fatal(1, "same-wave dependent request bypassed the pending destination");
        end

        @(posedge clk);
        #1;
        @(negedge clk);
        matrix_request_valid[0] = 1'b0;

        timeout = 0;
        while (|resident_wave_busy) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
            if (timeout > 96) begin
                $fatal(1, "resident-wave engine did not drain");
            end
        end

        if (write_count[0] != 16 || write_count[1] != 8) begin
            $fatal(
                1,
                "wave-tagged writeback count mismatch: wave0=%0d wave1=%0d",
                write_count[0],
                write_count[1]);
        end

        // Invalid full-wave state is consumed and reported against the selected slot.
        set_request(2, 1'b0, 8'd128, 8'd160, 8'd164);
        matrix_request_valid[2] = 1'b1;

        timeout = 0;
        while (!matrix_request_ready[2]) begin
            @(negedge clk);
            #1;
            timeout = timeout + 1;
            if (timeout > 24) begin
                $fatal(1, "invalid resident-wave request was not presented for rejection");
            end
        end

        @(posedge clk);
        #1;
        if (!illegal_issue || illegal_wave_slot != 2) begin
            $fatal(1, "illegal resident-wave request was not tagged correctly");
        end
        if (matrix_request_accepted[2]) begin
            $fatal(1, "illegal resident-wave request was accepted");
        end
        @(negedge clk);
        matrix_request_valid[2] = 1'b0;

        $display("[pass] CGX 1 resident-wave INT8 matrix engine checks passed.");
        $finish;
    end

endmodule
