// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_provisional_control_instruction_dispatch_tb;
    localparam integer SLOTS = 3;
    localparam integer SLOT_WIDTH = 2;
    localparam integer VA_WIDTH = 57;
    localparam logic [VA_WIDTH-1:0] MAX_ALIGNED_PC
        = {1'b1, {(VA_WIDTH-3){1'b1}}, 2'b00};

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic external_control_event_valid = 1'b0;
    logic [SLOTS-1:0] decoded_unhandled_valid = '0;
    logic [(SLOTS*4)-1:0] decoded_class_flat = '0;
    logic [(SLOTS*4)-1:0] decoded_opcode_flat = '0;
    logic [(SLOTS*32)-1:0] decoded_word_flat = '0;
    logic [(SLOTS*VA_WIDTH)-1:0] decoded_pc_flat = '0;
    logic [(SLOTS*32)-1:0] active_lane_mask_flat = '0;
    logic [SLOTS-1:0] handler_ready = '0;
    logic control_flow_event_ready = 1'b0;
    logic control_flow_event_accepted = 1'b0;
    logic [SLOTS-1:0] handler_valid;
    logic [SLOTS-1:0] decoder_ready;
    logic control_instruction_event_valid;
    logic [SLOT_WIDTH-1:0] control_instruction_event_wave_slot;
    logic [2:0] control_instruction_event_kind;
    logic [VA_WIDTH-1:0] control_instruction_event_target_pc;
    logic [VA_WIDTH-1:0] control_instruction_event_fallthrough_pc;
    logic [VA_WIDTH-1:0] control_instruction_event_join_pc;
    logic [31:0] control_instruction_event_taken_mask;
    logic control_instruction_event_accepted;

    always #5 clk = ~clk;

    cgx1_provisional_control_instruction_dispatch #(
        .RESIDENT_WAVE_SLOTS(SLOTS), .WAVE_SLOT_WIDTH(SLOT_WIDTH),
        .VIRTUAL_ADDRESS_WIDTH(VA_WIDTH)
    ) dut (.*);

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); reset_n = 1'b1;
        decoded_unhandled_valid = 3'b111;
        decoded_class_flat[0+:4] = 4'h3;
        decoded_opcode_flat[0+:4] = 4'h1;
        decoded_word_flat[0+:32] = 32'h3100_0008;
        decoded_pc_flat[0+:VA_WIDTH] = 57'h1000;
        active_lane_mask_flat[0+:32] = 32'h0000_000f;
        decoded_class_flat[4+:4] = 4'h2;
        decoded_opcode_flat[4+:4] = 4'h7;
        decoded_word_flat[32+:32] = 32'h2700_0000;
        decoded_class_flat[8+:4] = 4'h3;
        decoded_opcode_flat[8+:4] = 4'h0;
        decoded_word_flat[64+:32] = 32'h3000_0000;
        handler_ready = 3'b010;
        #1;
        if (handler_valid != 3'b010 || !control_instruction_event_valid
            || control_instruction_event_wave_slot != 0
            || control_instruction_event_kind != 3'd1
            || control_instruction_event_target_pc != 57'h100c
            || control_instruction_event_fallthrough_pc != 57'h100c
            || control_instruction_event_join_pc != 57'h100c
            || control_instruction_event_taken_mask != 32'h0000_000f
            || decoder_ready != 3'b010 || control_instruction_event_accepted)
            $fatal(1, "branch decode or raw-handler isolation was incorrect under backpressure");

        control_flow_event_ready = 1'b1;
        #1;
        if (decoder_ready != 3'b010 || control_instruction_event_accepted)
            $fatal(1, "fetched branch was consumed before the control-flow event was accepted");
        control_flow_event_accepted = 1'b1;
        #1;
        if (decoder_ready != 3'b011 || !control_instruction_event_accepted)
            $fatal(1, "branch handshake did not follow control-flow acceptance");
        @(posedge clk); #1;
        @(negedge clk);
        decoded_unhandled_valid[0] = 1'b0;
        control_flow_event_accepted = 1'b0;
        #1;
        if (!control_instruction_event_valid || control_instruction_event_wave_slot != 2
            || control_instruction_event_kind != 3'd7 || handler_valid != 3'b010
            || decoder_ready != 3'b010)
            $fatal(1, "round-robin arbitration did not select the waiting termination");

        external_control_event_valid = 1'b1;
        #1;
        if (control_instruction_event_valid || decoder_ready[2] || handler_valid[2])
            $fatal(1, "external control event priority exposed or consumed a fetched instruction");

        external_control_event_valid = 1'b0;
        control_flow_event_ready = 1'b0;
        #1;
        if (!control_instruction_event_valid || control_instruction_event_wave_slot != 2
            || decoder_ready[2])
            $fatal(1, "backpressured control flow consumed a fetched termination");
        control_flow_event_ready = 1'b1;
        control_flow_event_accepted = 1'b1;
        #1;
        if (!decoder_ready[2] || !control_instruction_event_accepted)
            $fatal(1, "termination handshake did not follow control-flow acceptance");
        @(posedge clk); #1;
        @(negedge clk);
        decoded_unhandled_valid = 3'b100;
        decoded_class_flat[8+:4] = 4'h3;
        decoded_opcode_flat[8+:4] = 4'h2;
        control_flow_event_accepted = 1'b0;
        handler_ready = 3'b100;
        #1;
        if (control_instruction_event_valid || handler_valid != 3'b100 || decoder_ready != 3'b100)
            $fatal(1, "unsupported Control opcode did not remain on the external handler boundary");

        @(negedge clk);
        decoded_unhandled_valid = 3'b011;
        decoded_class_flat[0+:4] = 4'h3;
        decoded_opcode_flat[0+:4] = 4'h1;
        decoded_word_flat[0+:32] = 32'h3100_0008;
        decoded_pc_flat[0+:VA_WIDTH] = 57'h2000;
        active_lane_mask_flat[0+:32] = 32'h0000_0003;
        decoded_class_flat[4+:4] = 4'h3;
        decoded_opcode_flat[4+:4] = 4'h1;
        decoded_word_flat[32+:32] = 32'h31ff_fff8;
        decoded_pc_flat[VA_WIDTH+:VA_WIDTH] = 57'h3000;
        active_lane_mask_flat[32+:32] = 32'h0000_00f0;
        handler_ready = '0;
        control_flow_event_ready = 1'b1;
        control_flow_event_accepted = 1'b1;
        #1;
        if (!control_instruction_event_accepted || control_instruction_event_wave_slot != 0)
            $fatal(1, "round-robin branch selection did not start at slot zero");
        @(posedge clk); #1;
        control_flow_event_accepted = 1'b0;
        #1;
        if (!control_instruction_event_valid || control_instruction_event_wave_slot != 1
            || control_instruction_event_target_pc != 57'h2ffc)
            $fatal(1, "round-robin arbitration did not advance to the signed backward branch");
        reset_n = 1'b0;
        @(posedge clk); #1;
        #1;
        if (!control_instruction_event_valid || control_instruction_event_wave_slot != 0)
            $fatal(1, "reset did not restore the first control-instruction arbitration slot");
        reset_n = 1'b1;

        @(negedge clk);
        decoded_unhandled_valid = 3'b001;
        decoded_class_flat[0+:4] = 4'h3;
        decoded_opcode_flat[0+:4] = 4'h1;
        decoded_word_flat[0+:32] = 32'h31ff_fffc;
        decoded_pc_flat[0+:VA_WIDTH] = MAX_ALIGNED_PC;
        active_lane_mask_flat[0+:32] = 32'h1;
        control_flow_event_ready = 1'b0;
        #1;
        if (!control_instruction_event_valid
            || control_instruction_event_target_pc != MAX_ALIGNED_PC)
            $fatal(1, "negative branch from the final aligned PC lost its valid 57-bit target");

        $display("[pass] provisional fetched branch/termination decode, arbitration, and handshake passed.");
        $finish;
    end
endmodule
