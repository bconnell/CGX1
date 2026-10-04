// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
`timescale 1ns/1ps
module cgx1_compute_workgroup_command_runtime_tb;
    localparam integer SLOTS = 2;
    localparam integer WG_WIDTH = 16;
    localparam integer PC_WIDTH = 57;
    localparam integer WAVE_WIDTH = 2;
    localparam integer PACKET_BYTES = 128;

    logic clk = 0;
    logic reset_n = 0;
    always #5 clk = ~clk;

    logic command_valid = 0, command_ready;
    logic command_start = 0;
    logic [7:0] command_data = 0;
    logic [5:0] command_queue_context_id = 0;
    logic [63:0] command_process_id = 0, command_address_space_id = 0;
    logic [2:0] command_priority = 0;
    logic [63:0] command_queue_incarnation_id = 0;
    logic [63:0] command_packet_byte_position = 0;
    logic parser_recovery_valid = 0;
    logic [5:0] parser_recovery_context_id = 0;
    logic [63:0] parser_faulted_mask;

    logic parser_submit_valid, parser_submit_ready;
    logic [5:0] parser_submit_queue_context_id;
    logic [63:0] parser_submit_process_id, parser_submit_address_space_id;
    logic [2:0] parser_submit_priority;
    logic [WG_WIDTH-1:0] parser_submit_workgroup_id;
    logic [63:0] parser_submit_submission_id;
    logic [63:0] parser_submit_packet_byte_position;
    logic [63:0] parser_submit_queue_incarnation_id;
    logic [PC_WIDTH-1:0] parser_submit_start_pc;
    logic [WAVE_WIDTH-1:0] parser_submit_wave_count;
    logic [(SLOTS*32)-1:0] parser_submit_initial_live_lane_mask_flat;
    logic [(SLOTS*9)-1:0] parser_submit_vgpr_register_counts_flat;
    logic [15:0] parser_submit_scalar_state_units_per_wave;
    logic [31:0] parser_submit_shared_local_bytes;
    logic [31:0] parser_submit_other_workgroup_state_units;
    logic parser_completion_valid;
    logic parser_completion_ready = 0;
    logic [2:0] parser_completion_status;
    logic parser_completion_submission_id_valid;
    logic [63:0] parser_completion_submission_id;

    logic tile_eligible = 1;
    logic submit_graphics = 0;
    logic dispatch_valid, dispatch_ready = 1;
    logic [5:0] dispatch_queue_context_id;
    logic [63:0] dispatch_process_id, dispatch_address_space_id;
    logic [2:0] dispatch_priority;
    logic [WG_WIDTH-1:0] dispatch_workgroup_id;
    logic [63:0] dispatch_submission_id, dispatch_packet_byte_position;
    logic [63:0] dispatch_queue_incarnation_id;
    logic [WAVE_WIDTH-1:0] dispatch_wave_count;
    logic [PC_WIDTH-1:0] dispatch_start_pc;
    logic [(SLOTS*32)-1:0] dispatch_initial_live_lane_mask_flat;
    logic [(SLOTS*9)-1:0] dispatch_vgpr_register_counts_flat;
    logic [15:0] dispatch_scalar_state_units_per_wave;
    logic [31:0] dispatch_shared_local_bytes;
    logic [31:0] dispatch_other_workgroup_state_units;
    logic dispatch_result_valid = 0, dispatch_accepted = 0;
    logic [4:0] dispatch_failure = 0;
    logic completion_valid;
    logic [5:0] completion_queue_context_id;
    logic [63:0] completion_process_id, completion_address_space_id;
    logic [WG_WIDTH-1:0] completion_workgroup_id;
    logic [63:0] completion_submission_id, completion_packet_byte_position;
    logic [63:0] completion_queue_incarnation_id;
    logic [1:0] completion_status;
    logic [4:0] completion_failure;
    logic [2:0] pending_count;

    cgx1_compute_workgroup_command_packet_parser #(
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .WORKGROUP_ID_WIDTH(WG_WIDTH),
        .VIRTUAL_ADDRESS_WIDTH(PC_WIDTH),
        .MAX_PACKET_BYTES(PACKET_BYTES)
    ) parser (
        .clk(clk), .reset_n(reset_n),
        .command_valid(command_valid), .command_ready(command_ready),
        .command_start(command_start), .command_data(command_data),
        .command_queue_context_id(command_queue_context_id),
        .command_process_id(command_process_id),
        .command_address_space_id(command_address_space_id),
        .command_priority(command_priority),
        .command_queue_incarnation_id(command_queue_incarnation_id),
        .command_packet_byte_position(command_packet_byte_position),
        .parser_recovery_valid(parser_recovery_valid),
        .parser_recovery_context_id(parser_recovery_context_id),
        .submit_valid(parser_submit_valid), .submit_ready(parser_submit_ready),
        .submit_queue_context_id(parser_submit_queue_context_id),
        .submit_process_id(parser_submit_process_id),
        .submit_address_space_id(parser_submit_address_space_id),
        .submit_priority(parser_submit_priority),
        .submit_workgroup_id(parser_submit_workgroup_id),
        .submit_submission_id(parser_submit_submission_id),
        .submit_packet_byte_position(parser_submit_packet_byte_position),
        .submit_queue_incarnation_id(parser_submit_queue_incarnation_id),
        .submit_start_pc(parser_submit_start_pc),
        .submit_wave_count(parser_submit_wave_count),
        .submit_initial_live_lane_mask_flat(parser_submit_initial_live_lane_mask_flat),
        .submit_vgpr_register_counts_flat(parser_submit_vgpr_register_counts_flat),
        .submit_scalar_state_units_per_wave(parser_submit_scalar_state_units_per_wave),
        .submit_shared_local_bytes(parser_submit_shared_local_bytes),
        .submit_other_workgroup_state_units(parser_submit_other_workgroup_state_units),
        .parser_completion_valid(parser_completion_valid),
        .parser_completion_ready(parser_completion_ready),
        .parser_completion_queue_context_id(),
        .parser_completion_process_id(), .parser_completion_address_space_id(),
        .parser_completion_submission_id_valid(parser_completion_submission_id_valid),
        .parser_completion_submission_id(parser_completion_submission_id),
        .parser_completion_packet_byte_position(),
        .parser_completion_queue_incarnation_id(),
        .parser_completion_workgroup_id(),
        .parser_completion_status(parser_completion_status),
        .parser_completion_failure(),
        .queue_faulted_mask(parser_faulted_mask)
    );

    cgx1_compute_workgroup_dispatch_scheduler #(
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .MAX_PENDING_ENTRIES(4),
        .WORKGROUP_ID_WIDTH(WG_WIDTH),
        .VIRTUAL_ADDRESS_WIDTH(PC_WIDTH),
        .AGING_INTERVAL_CYCLES(2)
    ) dispatcher (
        .clk(clk), .reset_n(reset_n), .tile_eligible(tile_eligible),
        .faulted_queue_mask(parser_faulted_mask),
        .submit_valid(parser_submit_valid), .submit_ready(parser_submit_ready),
        .submit_queue_context_id(parser_submit_queue_context_id),
        .submit_process_id(parser_submit_process_id),
        .submit_address_space_id(parser_submit_address_space_id),
        .submit_priority(parser_submit_priority), .submit_graphics(submit_graphics),
        .submit_workgroup_id(parser_submit_workgroup_id),
        .submit_wave_count(parser_submit_wave_count),
        .submit_start_pc(parser_submit_start_pc),
        .submit_initial_live_lane_mask_flat(parser_submit_initial_live_lane_mask_flat),
        .submit_vgpr_register_counts_flat(parser_submit_vgpr_register_counts_flat),
        .submit_scalar_state_units_per_wave(parser_submit_scalar_state_units_per_wave),
        .submit_shared_local_bytes(parser_submit_shared_local_bytes),
        .submit_other_workgroup_state_units(parser_submit_other_workgroup_state_units),
        .submit_submission_id(parser_submit_submission_id),
        .submit_packet_byte_position(parser_submit_packet_byte_position),
        .submit_queue_incarnation_id(parser_submit_queue_incarnation_id),
        .dispatch_valid(dispatch_valid), .dispatch_ready(dispatch_ready),
        .dispatch_queue_context_id(dispatch_queue_context_id),
        .dispatch_process_id(dispatch_process_id),
        .dispatch_address_space_id(dispatch_address_space_id),
        .dispatch_priority(dispatch_priority),
        .dispatch_workgroup_id(dispatch_workgroup_id),
        .dispatch_submission_id(dispatch_submission_id),
        .dispatch_packet_byte_position(dispatch_packet_byte_position),
        .dispatch_queue_incarnation_id(dispatch_queue_incarnation_id),
        .dispatch_wave_count(dispatch_wave_count), .dispatch_start_pc(dispatch_start_pc),
        .dispatch_initial_live_lane_mask_flat(dispatch_initial_live_lane_mask_flat),
        .dispatch_vgpr_register_counts_flat(dispatch_vgpr_register_counts_flat),
        .dispatch_scalar_state_units_per_wave(dispatch_scalar_state_units_per_wave),
        .dispatch_shared_local_bytes(dispatch_shared_local_bytes),
        .dispatch_other_workgroup_state_units(dispatch_other_workgroup_state_units),
        .dispatch_result_valid(dispatch_result_valid),
        .dispatch_accepted(dispatch_accepted), .dispatch_failure(dispatch_failure),
        .completion_valid(completion_valid), .completion_ready(1'b1),
        .completion_queue_context_id(completion_queue_context_id),
        .completion_process_id(completion_process_id),
        .completion_address_space_id(completion_address_space_id),
        .completion_workgroup_id(completion_workgroup_id),
        .completion_submission_id(completion_submission_id),
        .completion_packet_byte_position(completion_packet_byte_position),
        .completion_queue_incarnation_id(completion_queue_incarnation_id),
        .completion_status(completion_status), .completion_failure(completion_failure),
        .pending_count(pending_count)
    );

    task automatic build_packet(
        input logic [63:0] token,
        output logic [PACKET_BYTES*8-1:0] packet,
        output integer byte_count);
        integer byte_index;
        begin
            packet = '0;
            byte_count = 52;
            packet[0*8 +: 8] = 8'h43;
            packet[1*8 +: 8] = 8'h47;
            packet[2*8 +: 8] = 8'h58;
            packet[3*8 +: 8] = 8'h31;
            packet[4*8 +: 8] = 8'h01;
            packet[5*8 +: 8] = 8'h00;
            packet[6*8 +: 8] = 8'h01;
            packet[7*8 +: 8] = 8'h00;
            packet[8*8 +: 8] = 8'h34;
            for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
                packet[(12+byte_index)*8 +: 8] = token >> (byte_index*8);
                packet[(20+byte_index)*8 +: 8] = (64'h1000) >> (byte_index*8);
            end
            packet[28*8 +: 8] = 8'h01;
            packet[30*8 +: 8] = 8'h01;
            packet[36*8 +: 8] = 8'h44;
            packet[37*8 +: 8] = 8'h33;
            packet[38*8 +: 8] = 8'h22;
            packet[39*8 +: 8] = 8'h11;
            packet[44*8 +: 8] = 8'hff;
            packet[45*8 +: 8] = 8'hff;
            packet[46*8 +: 8] = 8'hff;
            packet[47*8 +: 8] = 8'hff;
            packet[48*8 +: 8] = 8'h10;
        end
    endtask

    task automatic send_packet(
        input logic [PACKET_BYTES*8-1:0] packet,
        input integer byte_count,
        input logic [63:0] token_position);
        integer byte_index;
        integer guard;
        begin
            for (byte_index = 0; byte_index < byte_count; byte_index = byte_index + 1) begin
                @(negedge clk);
                command_valid = 1;
                command_start = byte_index == 0;
                command_data = packet[byte_index*8 +: 8];
                command_queue_context_id = 9;
                command_process_id = byte_index == 0 ? 64'h1111 : 64'hdead;
                command_address_space_id = byte_index == 0 ? 64'h2222 : 64'hbeef;
                command_priority = byte_index == 0 ? 3 : 7;
                command_queue_incarnation_id = byte_index == 0 ? 64'habc9 : 64'h0;
                command_packet_byte_position = byte_index == 0 ? token_position : 64'h0;
                #1;
                guard = 0;
                while (!command_ready && guard < 100) begin
                    @(negedge clk); #1; guard = guard + 1;
                end
                if (!command_ready) $fatal(1, "runtime parser ingress stayed backpressured");
                @(posedge clk); #1;
                @(negedge clk);
                command_valid = 0;
                command_start = 0;
            end
        end
    endtask

    task automatic service_and_check(
        input logic [63:0] token,
        input logic [63:0] byte_position,
        input logic [WG_WIDTH-1:0] expected_workgroup);
        integer guard;
        begin
            guard = 0;
            while (dispatch_valid !== 1'b1 && guard < 100) begin
                @(negedge clk); #1; guard = guard + 1;
            end
            if (dispatch_valid !== 1'b1 || dispatch_workgroup_id !== expected_workgroup
                || dispatch_submission_id !== token
                || dispatch_packet_byte_position !== byte_position
                || dispatch_queue_incarnation_id !== 64'habc9
                || dispatch_queue_context_id !== 9
                || dispatch_process_id !== 64'h1111
                || dispatch_address_space_id !== 64'h2222
                || dispatch_start_pc !== 57'h1000
                || dispatch_wave_count !== 1
                || dispatch_other_workgroup_state_units !== 32'h11223344)
                $fatal(1, "parser to dispatcher descriptor/correlation mismatch valid=%b workgroup=%h/%h token=%h/%h position=%h/%h incarnation=%h context=%0d process=%h address=%h pc=%h waves=%0d other=%h pending=%0d",
                    dispatch_valid, expected_workgroup, dispatch_workgroup_id,
                    token, dispatch_submission_id,
                    byte_position, dispatch_packet_byte_position,
                    dispatch_queue_incarnation_id, dispatch_queue_context_id,
                    dispatch_process_id, dispatch_address_space_id,
                    dispatch_start_pc, dispatch_wave_count,
                    dispatch_other_workgroup_state_units, pending_count);
            @(posedge clk); #1;
            @(negedge clk);
            dispatch_result_valid = 1;
            dispatch_accepted = 1;
            dispatch_failure = 0;
            @(posedge clk); #1;
            if (!completion_valid || completion_status !== 2'd0
                || completion_workgroup_id !== expected_workgroup
                || completion_submission_id !== token
                || completion_packet_byte_position !== byte_position
                || completion_queue_incarnation_id !== 64'habc9
                || completion_queue_context_id !== 9
                || completion_process_id !== 64'h1111
                || completion_address_space_id !== 64'h2222)
                $fatal(1, "CU admission result lost command packet identity");
            @(negedge clk);
            dispatch_result_valid = 0;
            dispatch_accepted = 0;
            dispatch_failure = 0;
        end
    endtask

    initial begin : run_test
        logic [PACKET_BYTES*8-1:0] packet;
        integer byte_count;
        repeat (3) @(posedge clk);
        @(negedge clk); reset_n = 1;

        build_packet(64'hfeedface12345678, packet, byte_count);
        send_packet(packet, byte_count, 64'h40);
        service_and_check(64'hfeedface12345678, 64'h40, 16'h8000);

        // A duplicate submission token is unambiguous at a different ring position.
        build_packet(64'hfeedface12345678, packet, byte_count);
        send_packet(packet, byte_count, 64'h74);
        service_and_check(64'hfeedface12345678, 64'h74, 16'h8001);

        // Parser errors use their own completion boundary and do not enter the dispatcher.
        build_packet(64'hbad, packet, byte_count);
        packet[4*8 +: 8] = 8'h02;
        send_packet(packet, byte_count, 64'ha8);
        repeat (2) @(posedge clk);
        if (!parser_completion_valid || parser_completion_status !== 3'd1
            || parser_completion_submission_id_valid)
            $fatal(1, "unsupported parser completion was not explicit");
        if (pending_count != 0 || dispatch_valid)
            $fatal(1, "unsupported packet entered CU dispatch");
        @(negedge clk); parser_completion_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); parser_completion_ready = 0;

        // Parser recovery is parser-local: it clears framing state but leaves a
        // complete scheduler-owned descriptor pending for later admission.
        tile_eligible = 0;
        build_packet(64'hcafe, packet, byte_count);
        send_packet(packet, byte_count, 64'hdc);
        repeat (2) @(posedge clk);
        if (pending_count != 1 || dispatch_valid)
            $fatal(1, "test descriptor did not remain queued while CU was ineligible");

        packet[0*8 +: 8] = 8'h00;
        send_packet(packet, 12, 64'he0);
        if (!parser_completion_valid || parser_completion_status !== 3'd3
            || parser_completion_submission_id_valid || !parser_faulted_mask[9])
            $fatal(1, "untrustworthy packet did not enter parser fault state");
        if (pending_count != 1)
            $fatal(1, "parser fault changed the scheduler-owned pending descriptor");
        @(negedge clk); parser_completion_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); parser_completion_ready = 0;

        parser_recovery_context_id = 9;
        parser_recovery_valid = 1;
        @(posedge clk); #1;
        if (parser_faulted_mask[9] || pending_count != 1 || dispatch_valid)
            $fatal(1, "parser recovery acted like downstream queue cancellation");
        @(negedge clk); parser_recovery_valid = 0;
        tile_eligible = 1;
        #1;
        service_and_check(64'hcafe, 64'hdc, 16'h8002);

        $display("[pass] CGX1 command parser to CU dispatcher integration checks passed.");
        $finish;
    end
endmodule
