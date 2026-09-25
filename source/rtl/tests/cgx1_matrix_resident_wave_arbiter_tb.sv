// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_matrix_resident_wave_arbiter_tb;
    localparam integer SLOTS = 3;
    localparam integer SLOT_WIDTH = 2;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic [SLOTS-1:0] request_valid;
    logic [SLOTS-1:0] request_full_wave_active;
    logic [(SLOTS*8)-1:0] request_d_base;
    logic [(SLOTS*8)-1:0] request_a_base;
    logic [(SLOTS*8)-1:0] request_b_base;
    logic [SLOTS-1:0] request_ready;
    logic grant_valid;
    logic [SLOT_WIDTH-1:0] grant_wave_slot;
    logic grant_full_wave_active;
    logic [7:0] grant_d_base;
    logic [7:0] grant_a_base;
    logic [7:0] grant_b_base;
    logic grant_ready;

    always #5 clk = ~clk;

    cgx1_matrix_resident_wave_arbiter #(
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .WAVE_SLOT_WIDTH(SLOT_WIDTH)
    ) dut (.*);

    initial begin
        request_valid = '0;
        request_full_wave_active = '0;
        request_d_base = '0;
        request_a_base = '0;
        request_b_base = '0;
        grant_ready = 1'b0;

        request_full_wave_active[0] = 1'b1;
        request_full_wave_active[2] = 1'b1;
        request_d_base[0 +: 8] = 8'd8;
        request_d_base[16 +: 8] = 8'd40;
        request_a_base[0 +: 8] = 8'd64;
        request_a_base[16 +: 8] = 8'd96;
        request_b_base[0 +: 8] = 8'd68;
        request_b_base[16 +: 8] = 8'd100;

        repeat (2) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        request_valid = 3'b101;
        #1;
        if (!grant_valid || grant_wave_slot != 0 || request_ready != '0
            || !grant_full_wave_active || grant_d_base != 8'd8
            || grant_a_base != 8'd64 || grant_b_base != 8'd68) begin
            $fatal(1, "arbiter did not hold and route the first round-robin request");
        end

        repeat (2) begin
            @(posedge clk);
            #1;
            if (!grant_valid || grant_wave_slot != 0 || request_ready != '0) begin
                $fatal(1, "arbiter changed selection while the grant was blocked");
            end
        end

        @(negedge clk);
        grant_ready = 1'b1;
        #1;
        if (request_ready != 3'b001) begin
            $fatal(1, "arbiter did not return ready for the selected slot only");
        end

        @(posedge clk);
        #1;
        if (!grant_valid || grant_wave_slot != 2 || request_ready != 3'b100
            || grant_d_base != 8'd40 || grant_a_base != 8'd96 || grant_b_base != 8'd100) begin
            $fatal(1, "arbiter did not advance past an empty slot");
        end

        @(posedge clk);
        #1;
        request_valid = 3'b010;
        #1;
        if (!grant_valid || grant_wave_slot != 1 || request_ready != 3'b010) begin
            $fatal(1, "arbiter did not wrap after accepting the last non-power-of-two slot");
        end

        @(posedge clk);
        #1;
        request_valid = '0;
        #1;
        if (grant_valid || request_ready != '0) begin
            $fatal(1, "arbiter reported a grant with no resident-wave request");
        end

        $display("[pass] CGX 1 resident-wave matrix arbiter checks passed.");
        $finish;
    end
endmodule
