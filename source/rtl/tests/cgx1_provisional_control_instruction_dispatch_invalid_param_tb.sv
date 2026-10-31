// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_provisional_control_instruction_dispatch_invalid_param_tb;
    logic clk = 1'b0;
    logic reset_n = 1'b0;

    // Three resident slots require two bits. The original dispatcher
    // truncated slot 2 if a consumer incorrectly forced one bit.
    cgx1_provisional_control_instruction_dispatch #(
        .RESIDENT_WAVE_SLOTS(3),
        .WAVE_SLOT_WIDTH(1),
        .VIRTUAL_ADDRESS_WIDTH(57)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .external_control_event_valid(1'b0),
        .decoded_unhandled_valid('0),
        .decoded_class_flat('0),
        .decoded_opcode_flat('0),
        .decoded_word_flat('0),
        .decoded_pc_flat('0),
        .active_lane_mask_flat('0),
        .handler_ready('0),
        .control_flow_event_ready(1'b0),
        .control_flow_event_accepted(1'b0),
        .handler_valid(),
        .decoder_ready(),
        .control_instruction_event_valid(),
        .control_instruction_event_wave_slot(),
        .control_instruction_event_kind(),
        .control_instruction_event_target_pc(),
        .control_instruction_event_return_pc(),
        .control_instruction_event_fallthrough_pc(),
        .control_instruction_event_join_pc(),
        .control_instruction_event_taken_mask(),
        .control_instruction_event_accepted()
    );

    initial begin
        #1;
        $fatal(1, "dispatcher accepted an undersized wave-slot index");
    end
endmodule
