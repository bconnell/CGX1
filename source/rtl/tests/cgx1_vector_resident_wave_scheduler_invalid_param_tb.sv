// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_vector_resident_wave_scheduler_invalid_param_tb;
    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic [2:0] request_valid = '0;
    logic [2:0] dependency_ready = '0;
    logic selected_valid;
    logic selected_wave_slot;
    logic selected_accepted = 1'b0;

    cgx1_vector_resident_wave_scheduler #(
        .RESIDENT_WAVE_SLOTS(3),
        .WAVE_SLOT_WIDTH(1)
    ) dut (.*);

    initial begin
        #1;
        $fatal(1, "scheduler did not reject an undersized wave-slot index");
    end
endmodule
