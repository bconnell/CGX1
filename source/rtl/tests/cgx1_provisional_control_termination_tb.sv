// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_provisional_control_termination_tb;
    localparam integer SLOTS = 3;
    localparam integer SLOT_WIDTH = 2;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic external_control_event_valid = 1'b0;
    logic [SLOTS-1:0] decoded_unhandled_valid = '0;
    logic [(SLOTS*4)-1:0] decoded_class_flat = '0;
    logic [(SLOTS*4)-1:0] decoded_opcode_flat = '0;
    logic [SLOTS-1:0] handler_ready = '0;
    logic control_flow_event_ready = 1'b0;
    logic control_flow_event_accepted = 1'b0;
    logic [SLOTS-1:0] handler_valid;
    logic [SLOTS-1:0] decoder_ready;
    logic terminate_event_valid;
    logic [SLOT_WIDTH-1:0] terminate_event_wave_slot;
    logic terminate_event_accepted;

    always #5 clk = ~clk;

    cgx1_provisional_control_termination #(
        .RESIDENT_WAVE_SLOTS(SLOTS), .WAVE_SLOT_WIDTH(SLOT_WIDTH)
    ) dut (.*);

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); reset_n = 1'b1;
        decoded_unhandled_valid = 3'b111;
        decoded_class_flat[0+:4] = 4'h3;
        decoded_opcode_flat[0+:4] = 4'h0;
        decoded_class_flat[4+:4] = 4'h2;
        decoded_opcode_flat[4+:4] = 4'h7;
        decoded_class_flat[8+:4] = 4'h3;
        decoded_opcode_flat[8+:4] = 4'h0;
        handler_ready = 3'b010;
        #1;
        if (handler_valid != 3'b010 || !terminate_event_valid
            || terminate_event_wave_slot != 0 || decoder_ready != 3'b010
            || terminate_event_accepted)
            $fatal(1, "termination arbitration did not hold both termination words and pass raw work");

        control_flow_event_ready = 1'b1;
        control_flow_event_accepted = 1'b1;
        #1;
        if (decoder_ready != 3'b011 || !terminate_event_accepted)
            $fatal(1, "termination handshake did not follow control-flow acceptance");
        @(posedge clk); #1;
        @(negedge clk);
        decoded_unhandled_valid[0] = 1'b0;
        control_flow_event_accepted = 1'b0;
        #1;
        if (!terminate_event_valid || terminate_event_wave_slot != 2
            || handler_valid != 3'b010 || decoder_ready != 3'b110)
            $fatal(1, "round-robin arbitration did not select the next waiting termination");

        external_control_event_valid = 1'b1;
        #1;
        if (terminate_event_valid || decoder_ready[2] || handler_valid[2])
            $fatal(1, "external control event priority exposed or consumed a fetched termination");

        external_control_event_valid = 1'b0;
        control_flow_event_ready = 1'b0;
        #1;
        if (!terminate_event_valid || terminate_event_wave_slot != 2 || decoder_ready[2])
            $fatal(1, "backpressured control flow consumed a fetched termination");
        control_flow_event_ready = 1'b1;
        control_flow_event_accepted = 1'b1;
        #1;
        if (!decoder_ready[2] || !terminate_event_accepted)
            $fatal(1, "second termination did not handshake when control flow became ready");
        @(posedge clk); #1;
        @(negedge clk);
        decoded_unhandled_valid = 3'b100;
        decoded_class_flat[8+:4] = 4'h3;
        decoded_opcode_flat[8+:4] = 4'h1;
        control_flow_event_accepted = 1'b0;
        handler_ready = 3'b100;
        #1;
        if (terminate_event_valid || handler_valid != 3'b100 || decoder_ready != 3'b100)
            $fatal(1, "unsupported Control opcode did not remain on the external handler boundary");

        @(negedge clk);
        decoded_unhandled_valid = 3'b011;
        decoded_class_flat[0+:4] = 4'h3;
        decoded_opcode_flat[0+:4] = 4'h0;
        decoded_class_flat[4+:4] = 4'h3;
        decoded_opcode_flat[4+:4] = 4'h0;
        handler_ready = '0;
        control_flow_event_ready = 1'b1;
        control_flow_event_accepted = 1'b1;
        #1;
        if (!terminate_event_accepted || terminate_event_wave_slot != 0)
            $fatal(1, "termination arbitration reset test did not accept slot zero");
        @(posedge clk); #1;
        control_flow_event_accepted = 1'b0;
        control_flow_event_ready = 1'b0;
        #1;
        if (!terminate_event_valid || terminate_event_wave_slot != 1)
            $fatal(1, "round-robin state did not advance before reset");
        reset_n = 1'b0;
        @(posedge clk); #1;
        #1;
        if (!terminate_event_valid || terminate_event_wave_slot != 0)
            $fatal(1, "reset did not restore the first termination arbitration slot");
        reset_n = 1'b1;

        $display("[pass] provisional fetched-control termination decode and fair acceptance passed.");
        $finish;
    end
endmodule
