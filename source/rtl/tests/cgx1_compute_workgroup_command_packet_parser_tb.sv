// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
`timescale 1ns/1ps
module cgx1_compute_workgroup_command_packet_parser_tb #(
    parameter integer PC_WIDTH = 57
);
    localparam integer SLOTS = 2;
    localparam integer WG_WIDTH = 8;
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

    logic submit_valid, submit_ready = 0;
    logic [5:0] submit_queue_context_id;
    logic [63:0] submit_process_id, submit_address_space_id;
    logic [2:0] submit_priority;
    logic [WG_WIDTH-1:0] submit_workgroup_id;
    logic [63:0] submit_submission_id;
    logic [63:0] submit_packet_byte_position, submit_queue_incarnation_id;
    logic [PC_WIDTH-1:0] submit_start_pc;
    logic [WAVE_WIDTH-1:0] submit_wave_count;
    logic [(SLOTS*32)-1:0] submit_initial_live_lane_mask_flat;
    logic [(SLOTS*9)-1:0] submit_vgpr_register_counts_flat;
    logic [15:0] submit_scalar_state_units_per_wave;
    logic [31:0] submit_shared_local_bytes;
    logic [31:0] submit_other_workgroup_state_units;

    logic parser_completion_valid, parser_completion_ready = 0;
    logic [5:0] parser_completion_queue_context_id;
    logic [63:0] parser_completion_process_id, parser_completion_address_space_id;
    logic parser_completion_submission_id_valid;
    logic [63:0] parser_completion_submission_id;
    logic [63:0] parser_completion_packet_byte_position;
    logic [63:0] parser_completion_queue_incarnation_id;
    logic [WG_WIDTH-1:0] parser_completion_workgroup_id;
    logic [2:0] parser_completion_status;
    logic [4:0] parser_completion_failure;
    logic [63:0] queue_faulted_mask;
    integer deterministic_gap_state;

    cgx1_compute_workgroup_command_packet_parser #(
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .WORKGROUP_ID_WIDTH(WG_WIDTH),
        .VIRTUAL_ADDRESS_WIDTH(PC_WIDTH),
        .MAX_PACKET_BYTES(PACKET_BYTES),
        .INITIAL_WORKGROUP_ID(8'hfc)
    ) dut (.*);

    task automatic build_packet(
        input logic [63:0] token,
        input logic [63:0] pc,
        input integer wave_count,
        output logic [PACKET_BYTES*8-1:0] packet,
        output integer byte_count);
        integer byte_index;
        integer wave;
        begin
            packet = '0;
            byte_count = 44 + (wave_count * 8);
            packet[0*8 +: 8] = 8'h43;
            packet[1*8 +: 8] = 8'h47;
            packet[2*8 +: 8] = 8'h58;
            packet[3*8 +: 8] = 8'h31;
            packet[4*8 +: 8] = 8'h01;
            packet[5*8 +: 8] = 8'h00;
            packet[6*8 +: 8] = 8'h01;
            packet[7*8 +: 8] = 8'h00;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                packet[(8+byte_index)*8 +: 8] = byte_count >> (byte_index*8);
            for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
                packet[(12+byte_index)*8 +: 8] = token >> (byte_index*8);
                packet[(20+byte_index)*8 +: 8] = pc >> (byte_index*8);
            end
            packet[28*8 +: 8] = wave_count;
            packet[29*8 +: 8] = wave_count >> 8;
            packet[30*8 +: 8] = 8'h04;
            packet[31*8 +: 8] = 8'h00;
            packet[32*8 +: 8] = 8'h44;
            packet[33*8 +: 8] = 8'h33;
            packet[34*8 +: 8] = 8'h22;
            packet[35*8 +: 8] = 8'h11;
            packet[36*8 +: 8] = 8'h55;
            packet[37*8 +: 8] = 8'h66;
            packet[38*8 +: 8] = 8'h77;
            packet[39*8 +: 8] = 8'h88;
            for (byte_index = 40; byte_index < 44; byte_index = byte_index + 1)
                packet[byte_index*8 +: 8] = 8'h00;
            for (wave = 0; wave < wave_count; wave = wave + 1) begin
                packet[(44 + wave*8 + 0)*8 +: 8] = wave + 4;
                packet[(44 + wave*8 + 1)*8 +: 8] = 8'h03;
                packet[(44 + wave*8 + 2)*8 +: 8] = 8'h02;
                packet[(44 + wave*8 + 3)*8 +: 8] = 8'h01;
                packet[(44 + wave*8 + 4)*8 +: 8] = (wave == 0) ? 8'd16 : 8'd0;
                packet[(44 + wave*8 + 5)*8 +: 8] = (wave == 0) ? 8'd0 : 8'd1;
                packet[(44 + wave*8 + 6)*8 +: 8] = 8'h00;
                packet[(44 + wave*8 + 7)*8 +: 8] = 8'h00;
            end
        end
    endtask

    task automatic drive_byte(
        input logic [7:0] data_value,
        input logic first_byte,
        input logic [5:0] context_id,
        input logic [63:0] process_id,
        input logic [63:0] address_space_id,
        input logic [2:0] priority_value,
        input logic [63:0] incarnation,
        input logic [63:0] byte_position);
        integer guard;
        integer gap_cycles;
        begin
            deterministic_gap_state = deterministic_gap_state
                ^ (deterministic_gap_state << 13);
            deterministic_gap_state = deterministic_gap_state
                ^ (deterministic_gap_state >> 17);
            deterministic_gap_state = deterministic_gap_state
                ^ (deterministic_gap_state << 5);
            gap_cycles = deterministic_gap_state & 3;
            repeat (gap_cycles) @(negedge clk);
            @(negedge clk);
            command_valid = 1;
            command_start = first_byte;
            command_data = data_value;
            command_queue_context_id = context_id;
            command_process_id = first_byte ? process_id : ~process_id;
            command_address_space_id = first_byte ? address_space_id : ~address_space_id;
            command_priority = first_byte ? priority_value : ~priority_value;
            command_queue_incarnation_id = first_byte ? incarnation : ~incarnation;
            command_packet_byte_position = first_byte ? byte_position : ~byte_position;
            #1;
            guard = 0;
            while (!command_ready && guard < 100) begin
                @(negedge clk); #1; guard = guard + 1;
            end
            if (!command_ready)
                $fatal(1, "packet byte ingress remained backpressured");
            @(posedge clk); #1;
            @(negedge clk);
            command_valid = 0;
            command_start = 0;
        end
    endtask

    task automatic send_packet(
        input logic [PACKET_BYTES*8-1:0] packet,
        input integer byte_count,
        input logic [5:0] context_id,
        input logic [63:0] process_id,
        input logic [63:0] address_space_id,
        input logic [2:0] priority_value,
        input logic [63:0] incarnation,
        input logic [63:0] byte_position);
        integer byte_index;
        begin
            for (byte_index = 0; byte_index < byte_count; byte_index = byte_index + 1)
                drive_byte(packet[byte_index*8 +: 8], byte_index == 0,
                    context_id, process_id, address_space_id, priority_value,
                    incarnation, byte_position);
        end
    endtask

    task automatic send_prefix(
        input logic [PACKET_BYTES*8-1:0] packet,
        input integer byte_count,
        input logic [5:0] context_id);
        integer byte_index;
        begin
            for (byte_index = 0; byte_index < byte_count; byte_index = byte_index + 1)
                drive_byte(packet[byte_index*8 +: 8], byte_index == 0,
                    context_id, 64'h1111, 64'h2222, 3, 64'h3333, 64'h40);
        end
    endtask

    task automatic await_submit(input logic [63:0] token, input logic [WG_WIDTH-1:0] id);
        integer guard;
        begin
            guard = 0;
            while (!submit_valid && guard < 100) begin
                @(negedge clk); #1; guard = guard + 1;
            end
            if (!submit_valid || submit_submission_id !== token
                || submit_workgroup_id !== id)
                $fatal(1, "decoded descriptor identity mismatch: valid=%b token=%h id=%h",
                    submit_valid, submit_submission_id, submit_workgroup_id);
        end
    endtask

    task automatic accept_submit;
        begin
            @(negedge clk); submit_ready = 1;
            @(posedge clk); #1;
            @(negedge clk); submit_ready = 0;
        end
    endtask

    task automatic expect_parser_completion(
        input logic [2:0] expected_status,
        input logic expected_token_valid,
        input logic [63:0] expected_token,
        input logic [WG_WIDTH-1:0] expected_workgroup_id,
        input logic [4:0] expected_failure,
        input logic [5:0] expected_context,
        input logic [63:0] expected_position,
        input logic [63:0] expected_incarnation);
        integer guard;
        begin
            guard = 0;
            while (!parser_completion_valid && guard < 100) begin
                @(negedge clk); #1; guard = guard + 1;
            end
            if (!parser_completion_valid
                || parser_completion_status !== expected_status
                || parser_completion_submission_id_valid !== expected_token_valid
                || (expected_token_valid
                    && parser_completion_submission_id !== expected_token)
                || parser_completion_workgroup_id !== expected_workgroup_id
                || parser_completion_failure !== expected_failure
                || parser_completion_queue_context_id !== expected_context
                || parser_completion_packet_byte_position !== expected_position
                || parser_completion_queue_incarnation_id !== expected_incarnation)
                $fatal(1, "parser completion mismatch: valid=%b status=%0d token_valid=%b token=%h workgroup=%h failure=%0d",
                    parser_completion_valid, parser_completion_status,
                    parser_completion_submission_id_valid,
                    parser_completion_submission_id,
                    parser_completion_workgroup_id, parser_completion_failure);
        end
    endtask

    task automatic accept_parser_completion;
        begin
            @(negedge clk); parser_completion_ready = 1;
            @(posedge clk); #1;
            @(negedge clk); parser_completion_ready = 0;
        end
    endtask

    task automatic recover_parser_queue(input logic [5:0] context_id);
        begin
            @(negedge clk);
            parser_recovery_valid = 1;
            parser_recovery_context_id = context_id;
            @(posedge clk); #1;
            @(negedge clk);
            parser_recovery_valid = 0;
        end
    endtask

    initial begin : run_test
        logic [PACKET_BYTES*8-1:0] packet;
        integer byte_count;
        logic [63:0] original_incarnation;
        logic [63:0] original_position;
        integer byte_index;

        deterministic_gap_state = 32'h5a17_c9e3;
        original_incarnation = 64'h123456789abcdef0;
        original_position = 64'h0000000000000040;
        repeat (3) @(posedge clk);
        @(negedge clk); reset_n = 1;

        // Maximum-fit workgroup decodes exactly and holds stable under scheduler backpressure.
        build_packet(64'h0807060504030201, 64'h1000, 2, packet, byte_count);
        if (packet[0*8 +: 8] !== 8'h43 || packet[8*8 +: 8] !== 8'h3c
            || packet[12*8 +: 8] !== 8'h01 || packet[19*8 +: 8] !== 8'h08
            || packet[44*8 +: 8] !== 8'h04 || byte_count != 60)
            $fatal(1, "test golden packet vector is malformed");
        send_packet(packet, byte_count, 3, 64'h1111, 64'h2222, 5,
            original_incarnation, original_position);
        await_submit(64'h0807060504030201, 8'hfc);
        if (submit_queue_context_id !== 3 || submit_process_id !== 64'h1111
            || submit_address_space_id !== 64'h2222 || submit_priority !== 5
            || submit_packet_byte_position !== original_position
            || submit_queue_incarnation_id !== original_incarnation
            || submit_start_pc !== 57'h1000 || submit_wave_count !== 2
            || submit_scalar_state_units_per_wave !== 4
            || submit_shared_local_bytes !== 32'h11223344
            || submit_other_workgroup_state_units !== 32'h88776655
            || submit_initial_live_lane_mask_flat[31:0] !== 32'h01020304
            || submit_initial_live_lane_mask_flat[63:32] !== 32'h01020305
            || submit_vgpr_register_counts_flat[8:0] !== 9'd16
            || submit_vgpr_register_counts_flat[17:9] !== 9'd256)
            $fatal(1, "decoded packet fields mismatch ctx=%0d process=%h asid=%h priority=%0d pos=%h incarnation=%h pc=%h waves=%0d scalar=%0d shared=%h other=%h lanes=%h vgpr=%h",
                submit_queue_context_id, submit_process_id,
                submit_address_space_id, submit_priority,
                submit_packet_byte_position, submit_queue_incarnation_id,
                submit_start_pc, submit_wave_count,
                submit_scalar_state_units_per_wave, submit_shared_local_bytes,
                submit_other_workgroup_state_units,
                submit_initial_live_lane_mask_flat,
                submit_vgpr_register_counts_flat);
        repeat (2) begin
            @(posedge clk); #1;
            if (!submit_valid || submit_submission_id !== 64'h0807060504030201
                || submit_queue_incarnation_id !== original_incarnation)
                $fatal(1, "decoded descriptor changed under downstream backpressure");
        end
        recover_parser_queue(3);
        if (!submit_valid || submit_submission_id !== 64'h0807060504030201
            || submit_workgroup_id !== 8'hfc)
            $fatal(1, "parser recovery withdrew a complete descriptor under backpressure");
        accept_submit();

        // Parser recovery abandons a fragmented packet but does not rewind the workgroup ID sequence.
        build_packet(64'h2, 64'h2000, 1, packet, byte_count);
        send_prefix(packet, 5, 3);
        repeat (2) begin
            @(posedge clk); #1;
            if (submit_valid || parser_completion_valid)
                $fatal(1, "fragmented packet completed before all bytes arrived");
        end
        recover_parser_queue(3);
        send_packet(packet, byte_count, 3, 64'h3333, 64'h4444, 2,
            64'h5555, 64'h80);
        await_submit(64'h2, 8'hfd);
        if (submit_process_id !== 64'h3333 || submit_packet_byte_position !== 64'h80
            || submit_queue_incarnation_id !== 64'h5555)
            $fatal(1, "queue metadata was not captured at packet start");
        accept_submit();

        // Framed reserved flags are a malformed completion, not a queue fault.
        build_packet(64'h3, 64'h3000, 1, packet, byte_count);
        packet[7*8 +: 8] = 8'h01;
        send_prefix(packet, 13, 4);
        repeat (2) begin
            @(posedge clk); #1;
            if (parser_completion_valid || submit_valid)
                $fatal(1, "incomplete framed packet was prematurely completed");
        end
        for (byte_index = 13; byte_index < byte_count; byte_index = byte_index + 1)
            drive_byte(packet[byte_index*8 +: 8], 0, 4,
                64'h0, 64'h0, 0, 64'h0, 64'h0);
        expect_parser_completion(3'd2, 1, 64'h3, '0, 0, 4, 64'h40, 64'h3333);
        if (queue_faulted_mask[4]) $fatal(1, "framed bad flags faulted the queue");
        repeat (2) begin
            @(posedge clk); #1;
            if (!parser_completion_valid || parser_completion_submission_id !== 64'h3)
                $fatal(1, "parser completion changed under completion backpressure");
        end
        accept_parser_completion();

        // A valid packet immediately after a rejected framed packet remains dispatchable.
        build_packet(64'h4, 64'h4000, 1, packet, byte_count);
        send_packet(packet, byte_count, 4, 64'h4444, 64'h5555, 1,
            64'h6666, 64'hc0);
        await_submit(64'h4, 8'hfe);
        accept_submit();

        // Unsupported commands consume their frame and do not claim a v1 submission token.
        build_packet(64'h5, 64'h5000, 1, packet, byte_count);
        packet[4*8 +: 8] = 8'h02;
        send_packet(packet, byte_count, 5, 64'h5001, 64'h5002, 3,
            64'h5003, 64'h100);
        expect_parser_completion(3'd1, 0, 64'h0, '0, 0, 5, 64'h100, 64'h5003);
        if (queue_faulted_mask[5]) $fatal(1, "unsupported command faulted its queue");
        accept_parser_completion();

        // Framed v1 payload errors retain their token and consume the full declared boundary.
        build_packet(64'h51, 64'h5100, 1, packet, byte_count);
        packet[44*8 +: 32] = 0;
        send_packet(packet, byte_count, 5, 64'h5101, 64'h5102, 1,
            64'h5103, 64'h1c0);
        expect_parser_completion(3'd2, 1, 64'h51, '0, 0,
            5, 64'h1c0, 64'h5103);
        accept_parser_completion();

        build_packet(64'h52, 64'h5200, 1, packet, byte_count);
        packet[48*8 +: 8] = 8'h01;
        packet[49*8 +: 8] = 8'h01; // 257 VGPRs is outside the architectural range.
        send_packet(packet, byte_count, 5, 64'h5201, 64'h5202, 1,
            64'h5203, 64'h200);
        expect_parser_completion(3'd2, 1, 64'h52, '0, 0,
            5, 64'h200, 64'h5203);
        accept_parser_completion();

        build_packet(64'h53, 64'h5300, 1, packet, byte_count);
        packet[40*8 +: 8] = 8'h01; // Fixed-prefix reserved word must be zero.
        send_packet(packet, byte_count, 5, 64'h5301, 64'h5302, 1,
            64'h5303, 64'h240);
        expect_parser_completion(3'd2, 1, 64'h53, '0, 0,
            5, 64'h240, 64'h5303);
        accept_parser_completion();

        build_packet(64'h54, 64'h5401, 1, packet, byte_count);
        send_packet(packet, byte_count, 5, 64'h5401, 64'h5402, 1,
            64'h5403, 64'h280);
        expect_parser_completion(3'd2, 1, 64'h54, '0, 0,
            5, 64'h280, 64'h5403);
        accept_parser_completion();

        if (PC_WIDTH == 57) begin
            build_packet(64'h57, 64'h0200000000000000, 1, packet, byte_count);
            send_packet(packet, byte_count, 5, 64'h5701, 64'h5702, 1,
                64'h5703, 64'h340);
            expect_parser_completion(3'd2, 1, 64'h57, '0, 0,
                5, 64'h340, 64'h5703);
            accept_parser_completion();
        end

        if (PC_WIDTH < 57) begin
            build_packet(64'h59, (64'h1 << PC_WIDTH), 1, packet, byte_count);
            send_packet(packet, byte_count, 5, 64'h5901, 64'h5902, 1,
                64'h5903, 64'h3c0);
            if (submit_valid)
                $fatal(1, "PC bits above the configured width were accepted after truncation");
            expect_parser_completion(3'd2, 1, 64'h59, '0, 0,
                5, 64'h3c0, 64'h5903);
            accept_parser_completion();
        end

        build_packet(64'h58, 64'h5800, 1, packet, byte_count);
        packet[50*8 +: 8] = 8'h01; // Wave-record reserved word must be zero.
        send_packet(packet, byte_count, 5, 64'h5801, 64'h5802, 1,
            64'h5803, 64'h380);
        expect_parser_completion(3'd2, 1, 64'h58, '0, 0,
            5, 64'h380, 64'h5803);
        accept_parser_completion();

        // A trustworthy short v1 frame has no complete fixed prefix and therefore no token.
        build_packet(64'h55, 64'h5500, 1, packet, byte_count);
        packet[8*8 +: 8] = 8'd20;
        for (byte_index = 9; byte_index < 12; byte_index = byte_index + 1)
            packet[byte_index*8 +: 8] = 0;
        send_packet(packet, 20, 5, 64'h5501, 64'h5502, 1,
            64'h5503, 64'h2c0);
        expect_parser_completion(3'd2, 0, 64'h0, '0, 0,
            5, 64'h2c0, 64'h5503);
        accept_parser_completion();

        // A declared boundary shorter than the wave list is malformed but still consumed exactly.
        build_packet(64'h56, 64'h5600, 1, packet, byte_count);
        packet[8*8 +: 8] = 8'd44;
        for (byte_index = 9; byte_index < 12; byte_index = byte_index + 1)
            packet[byte_index*8 +: 8] = 0;
        send_packet(packet, 44, 5, 64'h5601, 64'h5602, 1,
            64'h5603, 64'h300);
        expect_parser_completion(3'd2, 1, 64'h56, '0, 0,
            5, 64'h300, 64'h5603);
        accept_parser_completion();

        if (queue_faulted_mask[5])
            $fatal(1, "framed payload errors incorrectly faulted the queue");

        // Over-capacity workgroups complete with the architectural capacity failure, never truncation.
        build_packet(64'h6, 64'h6000, 3, packet, byte_count);
        send_packet(packet, byte_count, 6, 64'h6001, 64'h6002, 2,
            64'h6003, 64'h140);
        expect_parser_completion(3'd0, 1, 64'h6, 8'hff, 5'd2,
            6, 64'h140, 64'h6003);
        if (submit_valid || queue_faulted_mask[6])
            $fatal(1, "oversized valid workgroup was dispatched or faulted");
        accept_parser_completion();

        // A valid descriptor after exhausting the internal ID sequence faults instead of reusing an ID.
        build_packet(64'h7, 64'h7000, 1, packet, byte_count);
        send_packet(packet, byte_count, 6, 64'h7001, 64'h7002, 2,
            64'h7003, 64'h180);
        expect_parser_completion(3'd3, 1, 64'h7, '0, 0,
            6, 64'h180, 64'h7003);
        if (!queue_faulted_mask[6]) $fatal(1, "ID exhaustion did not fault the queue");
        accept_parser_completion();
        @(negedge clk);
        command_valid = 1;
        command_start = 1;
        command_queue_context_id = 6;
        #1;
        if (command_ready) $fatal(1, "faulted queue accepted a new packet");
        command_valid = 0;
        command_start = 0;
        recover_parser_queue(6);
        if (queue_faulted_mask[6]) $fatal(1, "parser recovery did not clear parser fault");

        // An untrustworthy envelope faults only its captured queue and is resettable.
        build_packet(64'h8, 64'h8000, 1, packet, byte_count);
        packet[0*8 +: 8] = 8'h00;
        send_prefix(packet, 12, 7);
        expect_parser_completion(3'd3, 0, 64'h0, '0, 0, 7, 64'h40, 64'h3333);
        if (!queue_faulted_mask[7] || queue_faulted_mask[8])
            $fatal(1, "bad envelope faulted the wrong queue set");
        accept_parser_completion();
        recover_parser_queue(7);
        if (queue_faulted_mask[7]) $fatal(1, "framing fault survived parser recovery");

        // Unaligned, short, and over-limit lengths are rejected as untrustworthy framing.
        build_packet(64'h9, 64'h9000, 1, packet, byte_count);
        packet[8*8 +: 8] = 8'h35;
        send_prefix(packet, 12, 8);
        expect_parser_completion(3'd3, 0, 64'h0, '0, 0, 8, 64'h40, 64'h3333);
        accept_parser_completion();
        recover_parser_queue(8);
        build_packet(64'ha, 64'ha000, 1, packet, byte_count);
        packet[8*8 +: 8] = 8'h08;
        packet[9*8 +: 8] = 8'h00;
        send_prefix(packet, 12, 8);
        expect_parser_completion(3'd3, 0, 64'h0, '0, 0, 8, 64'h40, 64'h3333);
        accept_parser_completion();
        recover_parser_queue(8);
        build_packet(64'hb, 64'hb000, 1, packet, byte_count);
        packet[8*8 +: 8] = 8'h84; // 132 bytes, greater than this parser's 128-byte bound.
        packet[9*8 +: 8] = 8'h00;
        packet[10*8 +: 8] = 8'h00;
        packet[11*8 +: 8] = 8'h00;
        send_prefix(packet, 12, 8);
        expect_parser_completion(3'd3, 0, 64'h0, '0, 0, 8, 64'h40, 64'h3333);
        accept_parser_completion();

        $display("[pass] CGX1 workgroup command packet parser RTL checks passed.");
        $finish;
    end
endmodule
