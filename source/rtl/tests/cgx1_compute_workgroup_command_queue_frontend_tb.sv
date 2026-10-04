// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
`timescale 1ns/1ps
module cgx1_compute_workgroup_command_queue_frontend_tb;
    localparam integer QUEUES = 4;
    localparam integer RING_BYTES = 64;
    localparam integer COUNT_WIDTH = $clog2(RING_BYTES + 1);
    localparam integer SLOTS = 2;
    localparam integer WG_WIDTH = 16;
    localparam integer PC_WIDTH = 57;
    localparam integer WAVE_WIDTH = 2;
    localparam integer PACKET_BYTES = 128;

    logic clk = 0;
    logic reset_n = 0;
    always #5 clk = ~clk;

    logic register_valid = 0, register_ready;
    logic [5:0] register_context_id = 0;
    logic [63:0] register_process_id = 0, register_address_space_id = 0;
    logic [2:0] register_priority = 0;
    logic register_result_valid;
    logic register_result_ready = 0;
    logic [5:0] register_result_context_id;
    logic [1:0] register_result_status;
    logic [63:0] register_result_incarnation_id;

    logic byte_valid = 0, byte_ready;
    logic [5:0] byte_context_id = 0;
    logic [7:0] byte_data = 0;
    logic ingress_recovery_valid = 0, ingress_recovery_ready;
    logic [5:0] ingress_recovery_context_id = 0;
    logic [63:0] registered_context_mask, faulted_context_mask;
    logic [QUEUES*COUNT_WIDTH-1:0] unread_bytes_flat;
    logic [QUEUES*64-1:0] producer_position_flat, consumer_position_flat;

    logic submit_valid, submit_ready;
    logic [5:0] submit_queue_context_id;
    logic [63:0] submit_process_id, submit_address_space_id;
    logic [2:0] submit_priority;
    logic [WG_WIDTH-1:0] submit_workgroup_id;
    logic [63:0] submit_submission_id, submit_packet_byte_position;
    logic [63:0] submit_queue_incarnation_id;
    logic [PC_WIDTH-1:0] submit_start_pc;
    logic [WAVE_WIDTH-1:0] submit_wave_count;
    logic [(SLOTS*32)-1:0] submit_initial_live_lane_mask_flat;
    logic [(SLOTS*9)-1:0] submit_vgpr_register_counts_flat;
    logic [15:0] submit_scalar_state_units_per_wave;
    logic [31:0] submit_shared_local_bytes, submit_other_workgroup_state_units;

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

    logic tile_eligible = 0;
    logic dispatch_valid, dispatch_ready = 0;
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
    logic [31:0] dispatch_shared_local_bytes, dispatch_other_workgroup_state_units;
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
    integer invariant_queue;

    always @(negedge clk) begin
        if (reset_n) begin
            for (invariant_queue = 0; invariant_queue < QUEUES;
                 invariant_queue = invariant_queue + 1) begin
                if ((producer_position_flat[invariant_queue*64 +: 64]
                        - consumer_position_flat[invariant_queue*64 +: 64])
                    != unread_bytes_flat[invariant_queue*COUNT_WIDTH +: COUNT_WIDTH]
                    || unread_bytes_flat[invariant_queue*COUNT_WIDTH +: COUNT_WIDTH]
                        > RING_BYTES)
                    $fatal(1, "queue %0d ring occupancy/position invariant failed producer=%0d consumer=%0d unread=%0d",
                        invariant_queue,
                        producer_position_flat[invariant_queue*64 +: 64],
                        consumer_position_flat[invariant_queue*64 +: 64],
                        unread_bytes_flat[invariant_queue*COUNT_WIDTH +: COUNT_WIDTH]);
            end
        end
    end

    cgx1_compute_workgroup_command_queue_frontend #(
        .QUEUE_CONTEXT_COUNT(QUEUES),
        .RING_BYTES_PER_CONTEXT(RING_BYTES),
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .WORKGROUP_ID_WIDTH(WG_WIDTH),
        .VIRTUAL_ADDRESS_WIDTH(PC_WIDTH),
        .MAX_PACKET_BYTES(RING_BYTES)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .queue_register_valid(register_valid),
        .queue_register_ready(register_ready),
        .queue_register_context_id(register_context_id),
        .queue_register_process_id(register_process_id),
        .queue_register_address_space_id(register_address_space_id),
        .queue_register_priority(register_priority),
        .queue_register_result_valid(register_result_valid),
        .queue_register_result_ready(register_result_ready),
        .queue_register_result_context_id(register_result_context_id),
        .queue_register_result_status(register_result_status),
        .queue_register_result_incarnation_id(register_result_incarnation_id),
        .ingress_byte_valid(byte_valid), .ingress_byte_ready(byte_ready),
        .ingress_byte_context_id(byte_context_id), .ingress_byte_data(byte_data),
        .ingress_recovery_valid(ingress_recovery_valid),
        .ingress_recovery_ready(ingress_recovery_ready),
        .ingress_recovery_context_id(ingress_recovery_context_id),
        .registered_context_mask(registered_context_mask),
        .faulted_context_mask(faulted_context_mask),
        .unread_bytes_flat(unread_bytes_flat),
        .producer_position_flat(producer_position_flat),
        .consumer_position_flat(consumer_position_flat),
        .submit_valid(submit_valid), .submit_ready(submit_ready),
        .submit_queue_context_id(submit_queue_context_id),
        .submit_process_id(submit_process_id),
        .submit_address_space_id(submit_address_space_id),
        .submit_priority(submit_priority),
        .submit_workgroup_id(submit_workgroup_id),
        .submit_submission_id(submit_submission_id),
        .submit_packet_byte_position(submit_packet_byte_position),
        .submit_queue_incarnation_id(submit_queue_incarnation_id),
        .submit_start_pc(submit_start_pc), .submit_wave_count(submit_wave_count),
        .submit_initial_live_lane_mask_flat(submit_initial_live_lane_mask_flat),
        .submit_vgpr_register_counts_flat(submit_vgpr_register_counts_flat),
        .submit_scalar_state_units_per_wave(submit_scalar_state_units_per_wave),
        .submit_shared_local_bytes(submit_shared_local_bytes),
        .submit_other_workgroup_state_units(submit_other_workgroup_state_units),
        .parser_completion_valid(parser_completion_valid),
        .parser_completion_ready(parser_completion_ready),
        .parser_completion_queue_context_id(parser_completion_queue_context_id),
        .parser_completion_process_id(parser_completion_process_id),
        .parser_completion_address_space_id(parser_completion_address_space_id),
        .parser_completion_submission_id_valid(parser_completion_submission_id_valid),
        .parser_completion_submission_id(parser_completion_submission_id),
        .parser_completion_packet_byte_position(parser_completion_packet_byte_position),
        .parser_completion_queue_incarnation_id(parser_completion_queue_incarnation_id),
        .parser_completion_workgroup_id(parser_completion_workgroup_id),
        .parser_completion_status(parser_completion_status),
        .parser_completion_failure(parser_completion_failure)
    );

    cgx1_compute_workgroup_dispatch_scheduler #(
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .MAX_PENDING_ENTRIES(4),
        .WORKGROUP_ID_WIDTH(WG_WIDTH),
        .VIRTUAL_ADDRESS_WIDTH(PC_WIDTH),
        .AGING_INTERVAL_CYCLES(2)
    ) dispatcher (
        .clk(clk), .reset_n(reset_n), .tile_eligible(tile_eligible),
        .faulted_queue_mask(faulted_context_mask),
        .submit_valid(submit_valid), .submit_ready(submit_ready),
        .submit_queue_context_id(submit_queue_context_id),
        .submit_process_id(submit_process_id),
        .submit_address_space_id(submit_address_space_id),
        .submit_priority(submit_priority), .submit_graphics(1'b0),
        .submit_workgroup_id(submit_workgroup_id),
        .submit_wave_count(submit_wave_count), .submit_start_pc(submit_start_pc),
        .submit_initial_live_lane_mask_flat(submit_initial_live_lane_mask_flat),
        .submit_vgpr_register_counts_flat(submit_vgpr_register_counts_flat),
        .submit_scalar_state_units_per_wave(submit_scalar_state_units_per_wave),
        .submit_shared_local_bytes(submit_shared_local_bytes),
        .submit_other_workgroup_state_units(submit_other_workgroup_state_units),
        .submit_submission_id(submit_submission_id),
        .submit_packet_byte_position(submit_packet_byte_position),
        .submit_queue_incarnation_id(submit_queue_incarnation_id),
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
            packet[8*8 +: 8] = byte_count;
            for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
                packet[(12+byte_index)*8 +: 8] = token >> (byte_index*8);
                packet[(20+byte_index)*8 +: 8] = (64'h1000) >> (byte_index*8);
            end
            packet[28*8 +: 8] = 8'h01;
            packet[30*8 +: 8] = 8'h01;
            packet[32*8 +: 8] = 8'h00;
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

    task automatic register_queue(
        input logic [5:0] context_id,
        input logic [63:0] process_id,
        input logic [63:0] address_space_id,
        input logic [2:0] priority_value,
        input logic [63:0] expected_incarnation);
        integer guard;
        begin
            @(negedge clk);
            register_valid = 1;
            register_context_id = context_id;
            register_process_id = process_id;
            register_address_space_id = address_space_id;
            register_priority = priority_value;
            guard = 0;
            while (register_ready !== 1'b1 && guard < 100) begin
                @(negedge clk); #1; guard = guard + 1;
            end
            if (register_ready !== 1'b1)
                $fatal(1, "queue registration request stayed backpressured");
            @(posedge clk); #1;
            register_valid = 0;
            if (!register_result_valid || register_result_status !== 2'd0
                || register_result_context_id !== context_id
                || register_result_incarnation_id !== expected_incarnation)
                $fatal(1, "queue registration identity/incarnation mismatch");
            @(negedge clk); register_result_ready = 1;
            @(posedge clk); #1;
            @(negedge clk); register_result_ready = 0;
        end
    endtask

    task automatic write_fragment(
        input logic [5:0] context_id,
        input logic [PACKET_BYTES*8-1:0] packet,
        input integer start_byte,
        input integer byte_count);
        integer byte_index;
        integer guard;
        integer gap_state;
        begin
            gap_state = 32'h13579bdf ^ context_id ^ start_byte ^ byte_count
                ^ packet[(12*8) +: 32];
            for (byte_index = start_byte; byte_index < start_byte + byte_count;
                 byte_index = byte_index + 1) begin
                @(negedge clk);
                byte_valid = 1;
                byte_context_id = context_id;
                byte_data = packet[byte_index*8 +: 8];
                #1;
                guard = 0;
                while (byte_ready !== 1'b1 && guard < 100) begin
                    @(negedge clk); #1; guard = guard + 1;
                end
                if (byte_ready !== 1'b1)
                    $fatal(1, "ring byte ingress stayed backpressured before expected capacity");
                @(posedge clk); #1;
                byte_valid = 0;
                gap_state = (gap_state * 1103515245 + 12345) & 32'h7fffffff;
                repeat (gap_state & 3) @(negedge clk);
            end
            @(negedge clk); byte_valid = 0;
        end
    endtask

    task automatic wait_pending(input logic [2:0] expected_count);
        integer guard;
        begin
            guard = 0;
            while (pending_count !== expected_count && guard < 200) begin
                @(negedge clk); #1; guard = guard + 1;
            end
            if (pending_count !== expected_count)
                $fatal(1, "CU dispatcher pending count mismatch expected=%0d actual=%0d unread=%0d/%0d/%0d fault=%h submit_valid=%b submit_ready=%b parser_error=%b/%0d/%h feeder=%0d/%0d ring1=%0d/%0d header=%h/%h parser=%h/%h/%0d token=%h",
                    expected_count, pending_count,
                    unread_bytes_flat[0*COUNT_WIDTH +: COUNT_WIDTH],
                    unread_bytes_flat[1*COUNT_WIDTH +: COUNT_WIDTH],
                    unread_bytes_flat[2*COUNT_WIDTH +: COUNT_WIDTH],
                    faulted_context_mask, submit_valid, submit_ready,
                    parser_completion_valid, parser_completion_status,
                    parser_completion_packet_byte_position,
                    dut.feeder_context_id_q, dut.feeder_byte_index_q,
                    dut.ring_read_index_q[1], dut.ring_write_index_q[1],
                    dut.ring_memory[1][dut.ring_read_index_q[1]],
                    dut.ring_memory[1][dut.ring_read_index_q[1]+1],
                    dut.RingWordAt(1,0), dut.RingWordAt(1,8),
                    dut.parser.byte_index_q,
                    parser_completion_submission_id);
        end
    endtask

    task automatic service_one(
        input logic [5:0] context_id,
        input logic [63:0] token,
        input logic [63:0] position,
        input logic [WG_WIDTH-1:0] workgroup_id,
        input logic [63:0] process_id,
        input logic [63:0] address_space_id,
        input logic [63:0] incarnation);
        integer guard;
        begin
            @(negedge clk); tile_eligible = 1; dispatch_ready = 1; #1;
            guard = 0;
            while (dispatch_valid !== 1'b1 && guard < 100) begin
                @(negedge clk); #1; guard = guard + 1;
            end
            if (dispatch_valid !== 1'b1
                || dispatch_queue_context_id !== context_id
                || dispatch_submission_id !== token
                || dispatch_packet_byte_position !== position
                || dispatch_queue_incarnation_id !== incarnation
                || dispatch_process_id !== process_id
                || dispatch_address_space_id !== address_space_id
                || dispatch_workgroup_id !== workgroup_id
                || dispatch_start_pc !== 57'h1000
                || dispatch_wave_count !== 1)
                $fatal(1, "ring/parser/CUDS descriptor correlation mismatch");
            @(posedge clk); #1;
            @(negedge clk);
            dispatch_result_valid = 1;
            dispatch_accepted = 1;
            dispatch_failure = 0;
            @(posedge clk); #1;
            if (!completion_valid || completion_status !== 2'd0
                || completion_queue_context_id !== context_id
                || completion_submission_id !== token
                || completion_packet_byte_position !== position
                || completion_queue_incarnation_id !== incarnation)
                $fatal(1, "CU admission completion lost queue-ring correlation");
            @(negedge clk); dispatch_result_valid = 0; dispatch_accepted = 0;
        end
    endtask

    initial begin : run_test
        logic [PACKET_BYTES*8-1:0] packet0, packet1, packet2, packet3;
        integer byte_count;
        integer guard;
        integer random_index;
        logic [5:0] random_context;
        logic [63:0] random_start_position;
        logic [63:0] random_token;

        repeat (3) @(posedge clk);
        @(negedge clk); reset_n = 1;
        register_queue(0, 64'h100, 64'h200, 7, 1);
        register_queue(1, 64'h101, 64'h201, 2, 2);
        register_queue(2, 64'h102, 64'h202, 3, 3);
        if (registered_context_mask[2:0] !== 3'b111)
            $fatal(1, "registered context mask did not reflect accepted registrations");

        @(negedge clk);
        register_valid = 1;
        register_context_id = 0;
        register_process_id = 64'hdead;
        register_address_space_id = 64'hbeef;
        register_priority = 0;
        @(posedge clk); #1;
        register_valid = 0;
        if (!register_result_valid || register_result_status !== 2'd2
            || register_result_context_id !== 0
            || register_result_incarnation_id !== 0
            || registered_context_mask[0] !== 1'b1)
            $fatal(1, "duplicate queue registration replaced its original identity");
        @(negedge clk); register_result_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); register_result_ready = 0;

        @(negedge clk); byte_valid = 1; byte_context_id = 3; byte_data = 8'hff; #1;
        if (byte_ready !== 1'b0)
            $fatal(1, "unregistered queue context accepted ingress data");
        @(negedge clk); byte_valid = 0;

        // An incomplete lower-ID context must not block a complete packet from context 1.
        build_packet(64'h10, packet0, byte_count);
        write_fragment(0, packet0, 0, 20);
        repeat (5) @(posedge clk);
        if (pending_count != 0
            || unread_bytes_flat[0*COUNT_WIDTH +: COUNT_WIDTH] != 20
            || consumer_position_flat[0*64 +: 64] != 0)
            $fatal(1, "incomplete packet was consumed or entered dispatch pending=%0d unread=%0d consumer=%0d registered=%b faulted=%b",
                pending_count,
                unread_bytes_flat[0*COUNT_WIDTH +: COUNT_WIDTH],
                consumer_position_flat[0*64 +: 64],
                registered_context_mask[0], faulted_context_mask[0]);

        build_packet(64'h20, packet1, byte_count);
        write_fragment(1, packet1, 0, byte_count);
        wait_pending(1);
        if (unread_bytes_flat[1*COUNT_WIDTH +: COUNT_WIDTH] != 0
            || consumer_position_flat[1*64 +: 64] != 52
            || dispatch_queue_context_id != 1
            || dispatch_process_id != 64'h101
            || dispatch_address_space_id != 64'h201
            || dispatch_priority != 2
            || dispatch_submission_id != 64'h20
            || dispatch_packet_byte_position != 0
            || dispatch_queue_incarnation_id != 2)
            $fatal(1, "complete context did not progress with captured identity");

        write_fragment(0, packet0, 20, byte_count - 20);
        wait_pending(2);
        if (consumer_position_flat[0*64 +: 64] != 52
            || dispatch_queue_context_id != 0
            || dispatch_process_id != 64'h100
            || dispatch_submission_id != 64'h10
            || dispatch_priority != 7)
            $fatal(1, "completed partial packet lost ring order or was not the selected CUDS head pending=%0d consumer=%0d context=%0d process=%h token=%h priority=%0d",
                pending_count, consumer_position_flat[0*64 +: 64],
                dispatch_queue_context_id, dispatch_process_id,
                dispatch_submission_id, dispatch_priority);

        // Two more 52-byte packets force a physical ring wrap at byte 64.
        build_packet(64'h21, packet2, byte_count);
        write_fragment(1, packet2, 0, byte_count);
        wait_pending(3);
        build_packet(64'h22, packet3, byte_count);
        write_fragment(1, packet3, 0, byte_count);
        wait_pending(4);
        if (producer_position_flat[1*64 +: 64] != 156
            || consumer_position_flat[1*64 +: 64] != 156
            || unread_bytes_flat[1*COUNT_WIDTH +: COUNT_WIDTH] != 0)
            $fatal(1, "wrapped ring positions or consumer commit were incorrect");

        // A trustworthy unsupported frame waits for its completion handshake before consume.
        build_packet(64'h30, packet2, byte_count);
        packet2[4*8 +: 8] = 8'h02;
        write_fragment(2, packet2, 0, byte_count);
        guard = 0;
        while (!parser_completion_valid && guard < 200) begin
            @(negedge clk); #1; guard = guard + 1;
        end
        if (!parser_completion_valid || parser_completion_status !== 3'd1
            || parser_completion_queue_context_id !== 2
            || parser_completion_submission_id_valid !== 1'b0
            || parser_completion_submission_id !== 64'd0
            || unread_bytes_flat[2*COUNT_WIDTH +: COUNT_WIDTH] != 52
            || consumer_position_flat[2*64 +: 64] != 0)
            $fatal(1, "unsupported frame handshake/state mismatch valid=%b status=%0d ctx=%0d token=%h unread=%0d consumer=%0d fault=%h feeder=%0d/%0d start=%b data=%02x parser_state=%0d/%0d magic=%h length=%h",
                parser_completion_valid, parser_completion_status,
                parser_completion_queue_context_id, parser_completion_submission_id,
                unread_bytes_flat[2*COUNT_WIDTH +: COUNT_WIDTH],
                consumer_position_flat[2*64 +: 64], faulted_context_mask,
                dut.feeder_state_q, dut.feeder_byte_index_q,
                dut.parser_command_start, dut.parser_command_data,
                dut.parser.state_q, dut.parser.byte_index_q,
                dut.parser.magic_q, dut.parser.packet_length_q);
        @(negedge clk); parser_completion_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); parser_completion_ready = 0;
        guard = 0;
        while (unread_bytes_flat[2*COUNT_WIDTH +: COUNT_WIDTH] != 0 && guard < 100) begin
            @(negedge clk); #1; guard = guard + 1;
        end
        if (consumer_position_flat[2*64 +: 64] != 52)
            $fatal(1, "trusted unsupported frame did not commit its declared length");

        // An untrustworthy envelope pins its bytes and faults only its context.
        build_packet(64'h31, packet2, byte_count);
        packet2[0*8 +: 8] = 8'h00;
        write_fragment(2, packet2, 0, 12);
        guard = 0;
        while (!parser_completion_valid && guard < 100) begin
            @(negedge clk); #1; guard = guard + 1;
        end
        if (!parser_completion_valid || parser_completion_status !== 3'd3
            || !faulted_context_mask[2]
            || consumer_position_flat[2*64 +: 64] != 52
            || unread_bytes_flat[2*COUNT_WIDTH +: COUNT_WIDTH] != 12)
            $fatal(1, "untrustworthy frame was not pinned and faulted locally");
        @(negedge clk); parser_completion_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); parser_completion_ready = 0;
        repeat (2) @(posedge clk);
        ingress_recovery_context_id = 2;
        ingress_recovery_valid = 1;
        #1;
        if (ingress_recovery_ready !== 1'b1)
            $fatal(1, "idle faulted ring did not accept ingress recovery");
        @(posedge clk); #1;
        @(negedge clk); ingress_recovery_valid = 0;
        if (faulted_context_mask[2]
            || unread_bytes_flat[2*COUNT_WIDTH +: COUNT_WIDTH] != 0
            || consumer_position_flat[2*64 +: 64] != 64
            || pending_count != 4)
            $fatal(1, "ingress recovery lost scheduler descriptors or failed to discard ring bytes");

        // A full CUDS FIFO holds the parser result and pins the ring consumer.
        build_packet(64'h40, packet2, byte_count);
        write_fragment(2, packet2, 0, byte_count);
        guard = 0;
        while (!submit_valid && guard < 100) begin
            @(negedge clk); #1; guard = guard + 1;
        end
        if (!submit_valid || submit_ready
            || submit_submission_id !== 64'h40
            || submit_packet_byte_position !== 64'd64
            || unread_bytes_flat[2*COUNT_WIDTH +: COUNT_WIDTH] != 52
            || consumer_position_flat[2*64 +: 64] != 64)
            $fatal(1, "CUDS backpressure did not retain parser output valid=%b ready=%b token=%h pos=%0d unread=%0d consumer=%0d pending=%0d completion=%b/%0d/%0d fault=%h feeder=%0d/%0d parser=%0d/%0d magic=%h length=%h",
                submit_valid, submit_ready, submit_submission_id,
                submit_packet_byte_position,
                unread_bytes_flat[2*COUNT_WIDTH +: COUNT_WIDTH],
                consumer_position_flat[2*64 +: 64], pending_count,
                parser_completion_valid, parser_completion_status,
                parser_completion_queue_context_id, faulted_context_mask,
                dut.feeder_state_q, dut.feeder_byte_index_q,
                dut.parser.state_q, dut.parser.byte_index_q,
                dut.parser.magic_q, dut.parser.packet_length_q);
        if (ingress_recovery_ready)
            $fatal(1, "ingress recovery passed an active parser output transaction");

        build_packet(64'h41, packet3, byte_count);
        write_fragment(2, packet3, 0, 12);
        if (unread_bytes_flat[2*COUNT_WIDTH +: COUNT_WIDTH] != RING_BYTES
            || byte_ready)
            $fatal(1, "full ring did not apply ready/valid backpressure");

        // Servicing one queued descriptor frees a CUDS entry and commits the held packet.
        service_one(0, 64'h10, 0, 16'h8001, 64'h100, 64'h200, 1);
        guard = 0;
        while (consumer_position_flat[2*64 +: 64] != 116 && guard < 100) begin
            @(negedge clk); #1; guard = guard + 1;
        end
        if (consumer_position_flat[2*64 +: 64] != 116
            || unread_bytes_flat[2*COUNT_WIDTH +: COUNT_WIDTH] != 12
            || pending_count != 4)
            $fatal(1, "freed dispatcher slot did not accept and commit the held packet");

        // Hold one completion while a second context and another packet become ready.
        build_packet(64'h600, packet2, byte_count);
        packet2[4*8 +: 8] = 8'h02;
        packet2[8*8 +: 32] = 32'd12;
        write_fragment(0, packet2, 0, 12);
        guard = 0;
        while (!parser_completion_valid && guard < 100) begin
            @(negedge clk); #1; guard = guard + 1;
        end
        if (!parser_completion_valid || parser_completion_status !== 3'd1
            || parser_completion_queue_context_id !== 0
            || parser_completion_packet_byte_position !== 64'd52
            || consumer_position_flat[0*64 +: 64] != 52
            || unread_bytes_flat[0*COUNT_WIDTH +: COUNT_WIDTH] != 12)
            $fatal(1, "first held round-robin completion did not pin its ring bytes");

        build_packet(64'h601, packet3, byte_count);
        packet3[4*8 +: 8] = 8'h02;
        packet3[8*8 +: 32] = 32'd12;
        write_fragment(0, packet3, 0, 12);
        build_packet(64'h610, packet3, byte_count);
        packet3[4*8 +: 8] = 8'h02;
        packet3[8*8 +: 32] = 32'd12;
        write_fragment(1, packet3, 0, 12);

        @(negedge clk); parser_completion_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); parser_completion_ready = 0;
        if (consumer_position_flat[0*64 +: 64] != 64
            || unread_bytes_flat[0*COUNT_WIDTH +: COUNT_WIDTH] != 12)
            $fatal(1, "accepted short frame did not free only its committed ring bytes");

        guard = 0;
        while (!parser_completion_valid && guard < 100) begin
            @(negedge clk); #1; guard = guard + 1;
        end
        if (!parser_completion_valid || parser_completion_status !== 3'd1
            || parser_completion_queue_context_id !== 1
            || parser_completion_packet_byte_position !== 64'd156
            || consumer_position_flat[1*64 +: 64] != 156)
            $fatal(1, "round-robin feeder did not service the other ready context first");
        @(negedge clk); parser_completion_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); parser_completion_ready = 0;

        guard = 0;
        while (!parser_completion_valid && guard < 100) begin
            @(negedge clk); #1; guard = guard + 1;
        end
        if (!parser_completion_valid || parser_completion_status !== 3'd1
            || parser_completion_queue_context_id !== 0
            || parser_completion_packet_byte_position !== 64'd64)
            $fatal(1, "round-robin feeder did not preserve the remaining context packet");
        @(negedge clk); parser_completion_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); parser_completion_ready = 0;

        // Deterministic randomized gaps exercise repeated wraps and independent contexts.
        for (random_index = 0; random_index < 6; random_index = random_index + 1) begin
            random_context = (random_index % 2) == 0 ? 0 : 1;
            random_token = 64'h500 + random_index;
            random_start_position = consumer_position_flat[random_context*64 +: 64];
            build_packet(random_token, packet2, byte_count);
            packet2[4*8 +: 8] = 8'h02;
            write_fragment(random_context, packet2, 0, byte_count);
            guard = 0;
            while (!parser_completion_valid && guard < 200) begin
                @(negedge clk); #1; guard = guard + 1;
            end
            if (!parser_completion_valid
                || parser_completion_status !== 3'd1
                || parser_completion_queue_context_id !== random_context
                || parser_completion_packet_byte_position !== random_start_position
                || parser_completion_submission_id_valid !== 1'b0
                || unread_bytes_flat[random_context*COUNT_WIDTH +: COUNT_WIDTH] != 52
                || consumer_position_flat[random_context*64 +: 64] != random_start_position)
                $fatal(1, "randomized frame result/ownership mismatch context=%0d status=%0d position=%0d expected=%0d",
                    random_context, parser_completion_status,
                    parser_completion_packet_byte_position, random_start_position);
            @(negedge clk); parser_completion_ready = 1;
            @(posedge clk); #1;
            @(negedge clk); parser_completion_ready = 0;
            if (consumer_position_flat[random_context*64 +: 64]
                    != random_start_position + 52
                || unread_bytes_flat[random_context*COUNT_WIDTH +: COUNT_WIDTH] != 0)
                $fatal(1, "randomized frame consumer commit mismatch context=%0d", random_context);
        end
        if (producer_position_flat[0*64 +: 64] != 232
            || consumer_position_flat[0*64 +: 64] != 232
            || producer_position_flat[1*64 +: 64] != 324
            || consumer_position_flat[1*64 +: 64] != 324)
            $fatal(1, "randomized ring wrap positions did not remain monotonic and paired");

        @(negedge clk); reset_n = 0; #1;
        if (registered_context_mask != 0 || faulted_context_mask != 0
            || unread_bytes_flat != 0 || producer_position_flat != 0
            || consumer_position_flat != 0 || submit_valid
            || parser_completion_valid || pending_count != 0)
            $fatal(1, "reset did not clear ring, parser, and CU-dispatch state");

        $display("[pass] CGX1 bounded command queue-ring frontend checks passed.");
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "command queue-ring frontend test timed out");
    end
endmodule
