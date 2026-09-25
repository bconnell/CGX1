// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_vector_resident_wave_scheduler_tb;
    localparam integer SLOTS = 3;
    localparam integer SLOT_WIDTH = 2;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic [SLOTS-1:0] request_valid;
    logic [SLOTS-1:0] dependency_ready;
    logic selected_valid;
    logic [SLOT_WIDTH-1:0] selected_wave_slot;
    logic selected_accepted;
    integer issue_index;

    always #5 clk = ~clk;

    cgx1_vector_resident_wave_scheduler #(
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .WAVE_SLOT_WIDTH(SLOT_WIDTH)
    ) dut (.*);

    initial begin
        request_valid = '1;
        dependency_ready = '1;
        selected_accepted = 1'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        for (issue_index = 0; issue_index < 9; issue_index = issue_index + 1) begin
            #1;
            if (!selected_valid || selected_wave_slot != (issue_index % SLOTS)) begin
                $fatal(1, "non-power-of-two round-robin mismatch at issue %0d", issue_index);
            end
            selected_accepted = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            selected_accepted = 1'b0;
        end

        #1;
        if (!selected_valid || selected_wave_slot != 0) begin
            $fatal(1, "scheduler did not wrap after a complete issue round");
        end
        repeat (2) begin
            @(posedge clk);
            #1;
            if (!selected_valid || selected_wave_slot != 0) begin
                $fatal(1, "unaccepted selection advanced the round-robin pointer");
            end
        end

        @(negedge clk);
        selected_accepted = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        selected_accepted = 1'b0;

        dependency_ready = 3'b101;
        #1;
        if (!selected_valid || selected_wave_slot != 2) begin
            $fatal(1, "scheduler did not skip the dependency-blocked wave");
        end

        repeat (2) begin
            @(posedge clk);
            #1;
            if (!selected_valid || selected_wave_slot != 2) begin
                $fatal(1, "blocked selection changed before issue acceptance");
            end
        end

        @(negedge clk);
        dependency_ready = 3'b010;
        #1;
        if (!selected_valid || selected_wave_slot != 1) begin
            $fatal(1, "scheduler did not resume the previously blocked wave");
        end
        selected_accepted = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        selected_accepted = 1'b0;

        request_valid = '0;
        #1;
        if (selected_valid) begin
            $fatal(1, "scheduler selected a wave with no request");
        end

        $display("[pass] CGX 1 resident vector scheduler checks passed.");
        $finish;
    end
endmodule
