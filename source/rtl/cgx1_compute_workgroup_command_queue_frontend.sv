// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Bounded per-context command byte rings feeding one packet parser and CU scheduler.
module cgx1_compute_workgroup_command_queue_frontend #(
    parameter integer QUEUE_CONTEXT_COUNT = 64,
    parameter integer RING_BYTES_PER_CONTEXT = 4096,
    parameter integer RESIDENT_WAVE_SLOTS = 8,
    parameter integer WORKGROUP_ID_WIDTH = 16,
    parameter integer VIRTUAL_ADDRESS_WIDTH = 57,
    parameter integer MAX_PACKET_BYTES = RING_BYTES_PER_CONTEXT,
    parameter integer WAVE_COUNT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1)
        ? 1 : $clog2(RESIDENT_WAVE_SLOTS + 1),
    parameter integer RING_COUNT_WIDTH = (RING_BYTES_PER_CONTEXT <= 1)
        ? 1 : $clog2(RING_BYTES_PER_CONTEXT + 1),
    parameter integer RING_INDEX_WIDTH = (RING_BYTES_PER_CONTEXT <= 1)
        ? 1 : $clog2(RING_BYTES_PER_CONTEXT)
) (
    input logic clk,
    input logic reset_n,

    input logic queue_register_valid,
    output logic queue_register_ready,
    input logic [5:0] queue_register_context_id,
    input logic [63:0] queue_register_process_id,
    input logic [63:0] queue_register_address_space_id,
    input logic [2:0] queue_register_priority,
    output logic queue_register_result_valid,
    input logic queue_register_result_ready,
    output logic [5:0] queue_register_result_context_id,
    output logic [1:0] queue_register_result_status,
    output logic [63:0] queue_register_result_incarnation_id,

    input logic ingress_byte_valid,
    output logic ingress_byte_ready,
    input logic [5:0] ingress_byte_context_id,
    input logic [7:0] ingress_byte_data,
    input logic ingress_recovery_valid,
    output logic ingress_recovery_ready,
    input logic [5:0] ingress_recovery_context_id,

    input logic queue_reset_valid,
    output logic queue_reset_ready,
    input logic [5:0] queue_reset_context_id,
    output logic [63:0] queue_reset_pending_mask,
    input logic [63:0] queue_lifecycle_drained_mask,
    output logic queue_reset_complete_valid,
    input logic queue_reset_complete_ready,
    output logic [5:0] queue_reset_complete_context_id,
    output logic [63:0] queue_reset_complete_incarnation_id,
    output logic [63:0] queue_reset_discard_start_position,
    output logic [63:0] queue_reset_discard_end_position,

    output logic [63:0] registered_context_mask,
    // Parser framing faults are ingress-local; downstream scheduler fault or
    // cancellation inputs are separate lifecycle authorities.
    output logic [63:0] faulted_context_mask,
    output logic [(QUEUE_CONTEXT_COUNT*RING_COUNT_WIDTH)-1:0] unread_bytes_flat,
    output logic [(QUEUE_CONTEXT_COUNT*64)-1:0] producer_position_flat,
    output logic [(QUEUE_CONTEXT_COUNT*64)-1:0] consumer_position_flat,

    output logic submit_valid,
    input logic submit_ready,
    output logic [5:0] submit_queue_context_id,
    output logic [63:0] submit_process_id,
    output logic [63:0] submit_address_space_id,
    output logic [2:0] submit_priority,
    output logic [WORKGROUP_ID_WIDTH-1:0] submit_workgroup_id,
    output logic [63:0] submit_submission_id,
    output logic [63:0] submit_packet_byte_position,
    output logic [63:0] submit_queue_incarnation_id,
    output logic [VIRTUAL_ADDRESS_WIDTH-1:0] submit_start_pc,
    output logic [WAVE_COUNT_WIDTH-1:0] submit_wave_count,
    output logic [(RESIDENT_WAVE_SLOTS*32)-1:0] submit_initial_live_lane_mask_flat,
    output logic [(RESIDENT_WAVE_SLOTS*9)-1:0] submit_vgpr_register_counts_flat,
    output logic [15:0] submit_scalar_state_units_per_wave,
    output logic [31:0] submit_shared_local_bytes,
    output logic [31:0] submit_other_workgroup_state_units,

    output logic parser_completion_valid,
    input logic parser_completion_ready,
    output logic [5:0] parser_completion_queue_context_id,
    output logic [63:0] parser_completion_process_id,
    output logic [63:0] parser_completion_address_space_id,
    output logic parser_completion_submission_id_valid,
    output logic [63:0] parser_completion_submission_id,
    output logic [63:0] parser_completion_packet_byte_position,
    output logic [63:0] parser_completion_queue_incarnation_id,
    output logic [WORKGROUP_ID_WIDTH-1:0] parser_completion_workgroup_id,
    output logic [2:0] parser_completion_status,
    output logic [4:0] parser_completion_failure
);
    localparam logic [1:0] REGISTERED_OK = 2'd0;
    localparam logic [1:0] REGISTERED_INVALID_CONTEXT = 2'd1;
    localparam logic [1:0] REGISTERED_DUPLICATE_CONTEXT = 2'd2;
    localparam logic [1:0] REGISTERED_INCARNATION_EXHAUSTED = 2'd3;

    localparam logic [1:0] FEED_IDLE = 2'd0;
    localparam logic [1:0] FEED_PACKET = 2'd1;
    localparam logic [1:0] FEED_RESULT = 2'd2;

    localparam logic [31:0] PACKET_MAGIC = 32'h3158_4743;
    localparam logic [31:0] PACKET_HEADER_BYTES = 32'd12;

    logic [QUEUE_CONTEXT_COUNT-1:0] registered_q;
    logic [63:0] process_id_q [0:QUEUE_CONTEXT_COUNT-1];
    logic [63:0] address_space_id_q [0:QUEUE_CONTEXT_COUNT-1];
    logic [2:0] priority_q [0:QUEUE_CONTEXT_COUNT-1];
    logic [63:0] incarnation_id_q [0:QUEUE_CONTEXT_COUNT-1];
    logic [7:0] ring_memory [0:QUEUE_CONTEXT_COUNT-1][0:RING_BYTES_PER_CONTEXT-1];
    logic [RING_INDEX_WIDTH-1:0] ring_read_index_q [0:QUEUE_CONTEXT_COUNT-1];
    logic [RING_INDEX_WIDTH-1:0] ring_write_index_q [0:QUEUE_CONTEXT_COUNT-1];
    logic [RING_COUNT_WIDTH-1:0] ring_unread_count_q [0:QUEUE_CONTEXT_COUNT-1];
    logic [63:0] producer_position_q [0:QUEUE_CONTEXT_COUNT-1];
    logic [63:0] consumer_position_q [0:QUEUE_CONTEXT_COUNT-1];
    logic [QUEUE_CONTEXT_COUNT-1:0] reset_pending_q;
    logic [QUEUE_CONTEXT_COUNT-1:0] reset_cleanup_done_q;
    logic [63:0] reset_incarnation_id_q [0:QUEUE_CONTEXT_COUNT-1];
    logic [63:0] reset_discard_start_q [0:QUEUE_CONTEXT_COUNT-1];
    logic [63:0] reset_discard_end_q [0:QUEUE_CONTEXT_COUNT-1];

    logic [63:0] next_incarnation_id_q;
    logic incarnation_ids_exhausted_q;
    logic register_result_valid_q;
    logic [5:0] register_result_context_id_q;
    logic [1:0] register_result_status_q;
    logic [63:0] register_result_incarnation_id_q;

    logic reset_completion_valid_q;
    logic [5:0] reset_completion_context_id_q;
    logic [63:0] reset_completion_incarnation_id_q;
    logic [63:0] reset_completion_discard_start_q;
    logic [63:0] reset_completion_discard_end_q;

    logic [1:0] feeder_state_q;
    logic [5:0] feeder_context_id_q;
    logic [31:0] feeder_packet_bytes_q;
    logic [31:0] feeder_byte_index_q;
    logic [5:0] round_robin_cursor_q;
    logic parser_recovery_valid;
    logic [5:0] parser_recovery_context_id;
    logic external_recovery_fire;
    logic reset_cleanup_valid;
    logic [5:0] reset_cleanup_context_id;

    logic parser_command_valid;
    logic parser_command_ready;
    logic parser_command_start;
    logic [7:0] parser_command_data;
    logic [5:0] parser_command_context_id;
    logic [63:0] parser_command_process_id;
    logic [63:0] parser_command_address_space_id;
    logic [2:0] parser_command_priority;
    logic [63:0] parser_command_incarnation_id;
    logic [63:0] parser_command_packet_position;

    logic selected_packet_valid;
    logic [5:0] selected_packet_context_id;
    logic [31:0] selected_packet_bytes;

    integer comb_context;
    integer scan_offset;
    integer scan_context;
    integer packet_magic_candidate;
    integer packet_length_candidate;
    integer comb_queue;
    integer seq_queue;
    integer seq_index;
    integer current_ring_index;
    integer selected_consume_bytes;
    integer parser_ring_index;
    integer reset_cleanup_scan;
    integer reset_completion_scan;
    integer reset_cleanup_candidate;
    integer reset_completion_candidate;

    function automatic integer RingIndexAfter(
        input integer index_value,
        input integer byte_count);
        integer result_index;
        begin
            result_index = (index_value + byte_count) % RING_BYTES_PER_CONTEXT;
            RingIndexAfter = result_index;
        end
    endfunction

    function automatic logic [7:0] RingByteAt(
        input integer context_index,
        input integer byte_offset);
        integer physical_index;
        begin
            physical_index = RingIndexAfter(
                ring_read_index_q[context_index], byte_offset);
            RingByteAt = ring_memory[context_index][physical_index];
        end
    endfunction

    function automatic logic [31:0] RingWordAt(
        input integer context_index,
        input integer byte_offset);
        begin
            RingWordAt = {
                RingByteAt(context_index, byte_offset + 3),
                RingByteAt(context_index, byte_offset + 2),
                RingByteAt(context_index, byte_offset + 1),
                RingByteAt(context_index, byte_offset + 0)
            };
        end
    endfunction

    assign queue_register_result_valid = register_result_valid_q;
    assign queue_register_result_context_id = register_result_context_id_q;
    assign queue_register_result_status = register_result_status_q;
    assign queue_register_result_incarnation_id = register_result_incarnation_id_q;
    assign queue_reset_complete_valid = reset_completion_valid_q;
    assign queue_reset_complete_context_id = reset_completion_context_id_q;
    assign queue_reset_complete_incarnation_id = reset_completion_incarnation_id_q;
    assign queue_reset_discard_start_position = reset_completion_discard_start_q;
    assign queue_reset_discard_end_position = reset_completion_discard_end_q;

    assign queue_register_ready = reset_n
        && (!register_result_valid_q || queue_register_result_ready)
        && !(queue_register_valid
            && queue_register_context_id < QUEUE_CONTEXT_COUNT
            && reset_pending_q[queue_register_context_id]);

    assign queue_reset_ready = reset_n
        && (queue_reset_context_id < QUEUE_CONTEXT_COUNT)
        && registered_q[queue_reset_context_id]
        && !reset_pending_q[queue_reset_context_id]
        && !(register_result_valid_q
            && register_result_context_id_q == queue_reset_context_id)
        && !reset_completion_valid_q;

    assign external_recovery_fire = ingress_recovery_valid && ingress_recovery_ready;
    assign parser_recovery_valid = external_recovery_fire || reset_cleanup_valid;
    assign parser_recovery_context_id = external_recovery_fire
        ? ingress_recovery_context_id : reset_cleanup_context_id;

    always_comb begin : choose_reset_cleanup
        reset_cleanup_candidate = -1;
        reset_cleanup_context_id = '0;
        for (reset_cleanup_scan = 0; reset_cleanup_scan < QUEUE_CONTEXT_COUNT;
             reset_cleanup_scan = reset_cleanup_scan + 1) begin
            if (reset_cleanup_candidate < 0 && reset_n && !external_recovery_fire
                && reset_pending_q[reset_cleanup_scan] && !reset_cleanup_done_q[reset_cleanup_scan]
                && (feeder_state_q == FEED_IDLE || feeder_context_id_q != reset_cleanup_scan)
                && !(submit_valid && submit_queue_context_id == reset_cleanup_scan)
                && !(parser_completion_valid
                    && parser_completion_queue_context_id == reset_cleanup_scan)) begin
                reset_cleanup_candidate = reset_cleanup_scan;
                reset_cleanup_context_id = reset_cleanup_scan[5:0];
            end
        end
        reset_cleanup_valid = (reset_cleanup_candidate >= 0);
    end

    always_comb begin : choose_reset_completion
        reset_completion_candidate = -1;
        if (!reset_completion_valid_q) begin
            for (reset_completion_scan = 0; reset_completion_scan < QUEUE_CONTEXT_COUNT;
                 reset_completion_scan = reset_completion_scan + 1) begin
                if (reset_completion_candidate < 0 && reset_n
                    && reset_pending_q[reset_completion_scan] && reset_cleanup_done_q[reset_completion_scan]
                    && queue_lifecycle_drained_mask[reset_completion_scan]
                    && (feeder_state_q == FEED_IDLE || feeder_context_id_q != reset_completion_scan)
                    && !(submit_valid && submit_queue_context_id == reset_completion_scan)
                    && !(parser_completion_valid
                        && parser_completion_queue_context_id == reset_completion_scan))
                    reset_completion_candidate = reset_completion_scan;
            end
        end
    end

    assign parser_command_valid = (feeder_state_q == FEED_PACKET)
        && (feeder_byte_index_q < feeder_packet_bytes_q)
        && !parser_completion_valid;
    assign parser_command_start = (feeder_byte_index_q == 0);
    assign parser_command_context_id = feeder_context_id_q;
    assign parser_command_process_id = process_id_q[feeder_context_id_q];
    assign parser_command_address_space_id = address_space_id_q[feeder_context_id_q];
    assign parser_command_priority = priority_q[feeder_context_id_q];
    assign parser_command_incarnation_id = incarnation_id_q[feeder_context_id_q];
    assign parser_command_packet_position = consumer_position_q[feeder_context_id_q];

    always_comb begin : choose_complete_packet
        logic envelope_untrustworthy;
        selected_packet_valid = 1'b0;
        selected_packet_context_id = '0;
        selected_packet_bytes = '0;
        packet_magic_candidate = 0;
        packet_length_candidate = 0;
        scan_context = 0;
        envelope_untrustworthy = 1'b0;
        for (scan_offset = 0; scan_offset < 64; scan_offset = scan_offset + 1) begin
            scan_context = (round_robin_cursor_q + scan_offset) % 64;
            if (!selected_packet_valid && scan_context < QUEUE_CONTEXT_COUNT
                && registered_q[scan_context]
                && !reset_pending_q[scan_context]
                && !(queue_reset_valid && queue_reset_context_id == scan_context)
                && !faulted_context_mask[scan_context]
                && ring_unread_count_q[scan_context] >= PACKET_HEADER_BYTES) begin
                packet_magic_candidate = RingWordAt(scan_context, 0);
                packet_length_candidate = RingWordAt(scan_context, 8);
                envelope_untrustworthy = (packet_magic_candidate != PACKET_MAGIC)
                    || (packet_length_candidate < PACKET_HEADER_BYTES)
                    || (packet_length_candidate > MAX_PACKET_BYTES)
                    || (packet_length_candidate[1:0] != 0);
                if (envelope_untrustworthy
                    || ring_unread_count_q[scan_context] >= packet_length_candidate) begin
                    selected_packet_valid = 1'b1;
                    selected_packet_context_id = scan_context[5:0];
                    selected_packet_bytes = envelope_untrustworthy
                        ? PACKET_HEADER_BYTES : packet_length_candidate;
                end
            end
        end
    end

    always_comb begin : byte_ingress_control
        logic recovery_accepts_this_context;
        ingress_recovery_ready = 1'b0;
        if (reset_n && ingress_recovery_context_id < QUEUE_CONTEXT_COUNT
            && registered_q[ingress_recovery_context_id]
            && !reset_pending_q[ingress_recovery_context_id]
            && !(queue_reset_valid
                && queue_reset_context_id == ingress_recovery_context_id)
            && !((feeder_state_q != FEED_IDLE)
                && feeder_context_id_q == ingress_recovery_context_id)
            && !(submit_valid
                && submit_queue_context_id == ingress_recovery_context_id)
            && !(parser_completion_valid
                && parser_completion_queue_context_id == ingress_recovery_context_id))
            ingress_recovery_ready = 1'b1;

        recovery_accepts_this_context = ingress_recovery_valid
            && ingress_recovery_ready
            && ingress_recovery_context_id == ingress_byte_context_id;
        ingress_byte_ready = 1'b0;
        if (reset_n && ingress_byte_context_id < QUEUE_CONTEXT_COUNT
            && registered_q[ingress_byte_context_id]
            && !reset_pending_q[ingress_byte_context_id]
            && !(queue_reset_valid && queue_reset_context_id == ingress_byte_context_id)
            && !faulted_context_mask[ingress_byte_context_id]
            && ring_unread_count_q[ingress_byte_context_id] < RING_BYTES_PER_CONTEXT
            && producer_position_q[ingress_byte_context_id] != 64'hffffffffffffffff
            && !recovery_accepts_this_context)
            ingress_byte_ready = 1'b1;

    end

    always_comb begin : parser_ring_byte
        parser_command_data = '0;
        parser_ring_index = 0;
        if (feeder_context_id_q < QUEUE_CONTEXT_COUNT) begin
            parser_ring_index = RingIndexAfter(
                ring_read_index_q[feeder_context_id_q], feeder_byte_index_q);
            parser_command_data = ring_memory[feeder_context_id_q][parser_ring_index];
        end
    end

    always_comb begin : flattened_state
        registered_context_mask = '0;
        queue_reset_pending_mask = '0;
        unread_bytes_flat = '0;
        producer_position_flat = '0;
        consumer_position_flat = '0;
        for (comb_context = 0; comb_context < QUEUE_CONTEXT_COUNT;
             comb_context = comb_context + 1) begin
            registered_context_mask[comb_context] = registered_q[comb_context];
            queue_reset_pending_mask[comb_context] = reset_pending_q[comb_context];
            unread_bytes_flat[comb_context*RING_COUNT_WIDTH +: RING_COUNT_WIDTH]
                = ring_unread_count_q[comb_context];
            producer_position_flat[comb_context*64 +: 64]
                = producer_position_q[comb_context];
            consumer_position_flat[comb_context*64 +: 64]
                = consumer_position_q[comb_context];
        end
    end

    cgx1_compute_workgroup_command_packet_parser #(
        .RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),
        .WORKGROUP_ID_WIDTH(WORKGROUP_ID_WIDTH),
        .VIRTUAL_ADDRESS_WIDTH(VIRTUAL_ADDRESS_WIDTH),
        .MAX_PACKET_BYTES(MAX_PACKET_BYTES),
        .WAVE_COUNT_WIDTH(WAVE_COUNT_WIDTH)
    ) parser (
        .clk(clk), .reset_n(reset_n),
        .command_valid(parser_command_valid), .command_ready(parser_command_ready),
        .command_start(parser_command_start), .command_data(parser_command_data),
        .command_queue_context_id(parser_command_context_id),
        .command_process_id(parser_command_process_id),
        .command_address_space_id(parser_command_address_space_id),
        .command_priority(parser_command_priority),
        .command_queue_incarnation_id(parser_command_incarnation_id),
        .command_packet_byte_position(parser_command_packet_position),
        .parser_recovery_valid(parser_recovery_valid),
        .parser_recovery_context_id(parser_recovery_context_id),
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
        .parser_completion_failure(parser_completion_failure),
        .queue_faulted_mask(faulted_context_mask)
    );

    always_ff @(posedge clk or negedge reset_n) begin : queue_ring_state
        if (!reset_n) begin
            registered_q <= '0;
            reset_pending_q <= '0;
            reset_cleanup_done_q <= '0;
            next_incarnation_id_q <= 64'd1;
            incarnation_ids_exhausted_q <= 1'b0;
            register_result_valid_q <= 1'b0;
            register_result_context_id_q <= '0;
            register_result_status_q <= '0;
            register_result_incarnation_id_q <= '0;
            reset_completion_valid_q <= 1'b0;
            reset_completion_context_id_q <= '0;
            reset_completion_incarnation_id_q <= '0;
            reset_completion_discard_start_q <= '0;
            reset_completion_discard_end_q <= '0;
            feeder_state_q <= FEED_IDLE;
            feeder_context_id_q <= '0;
            feeder_packet_bytes_q <= '0;
            feeder_byte_index_q <= '0;
            round_robin_cursor_q <= '0;
            for (seq_queue = 0; seq_queue < QUEUE_CONTEXT_COUNT;
                 seq_queue = seq_queue + 1) begin
                process_id_q[seq_queue] <= '0;
                address_space_id_q[seq_queue] <= '0;
                priority_q[seq_queue] <= '0;
                incarnation_id_q[seq_queue] <= '0;
                ring_read_index_q[seq_queue] <= '0;
                ring_write_index_q[seq_queue] <= '0;
                ring_unread_count_q[seq_queue] <= '0;
                producer_position_q[seq_queue] <= '0;
                consumer_position_q[seq_queue] <= '0;
                reset_incarnation_id_q[seq_queue] <= '0;
                reset_discard_start_q[seq_queue] <= '0;
                reset_discard_end_q[seq_queue] <= '0;
            end
        end else begin
            if (register_result_valid_q && queue_register_result_ready)
                register_result_valid_q <= 1'b0;

            if (queue_reset_complete_valid && queue_reset_complete_ready) begin
                reset_completion_valid_q <= 1'b0;
                registered_q[reset_completion_context_id_q] <= 1'b0;
                reset_pending_q[reset_completion_context_id_q] <= 1'b0;
                reset_cleanup_done_q[reset_completion_context_id_q] <= 1'b0;
            end else if (reset_completion_candidate >= 0) begin
                reset_completion_valid_q <= 1'b1;
                reset_completion_context_id_q <= reset_completion_candidate[5:0];
                reset_completion_incarnation_id_q
                    <= reset_incarnation_id_q[reset_completion_candidate];
                reset_completion_discard_start_q
                    <= reset_discard_start_q[reset_completion_candidate];
                reset_completion_discard_end_q
                    <= reset_discard_end_q[reset_completion_candidate];
            end

            if (queue_reset_valid && queue_reset_ready) begin
                reset_pending_q[queue_reset_context_id] <= 1'b1;
                reset_cleanup_done_q[queue_reset_context_id] <= 1'b0;
                reset_incarnation_id_q[queue_reset_context_id]
                    <= incarnation_id_q[queue_reset_context_id];
            end

            if (queue_register_valid && queue_register_ready) begin
                register_result_valid_q <= 1'b1;
                register_result_context_id_q <= queue_register_context_id;
                register_result_incarnation_id_q <= '0;
                if (queue_register_context_id >= QUEUE_CONTEXT_COUNT) begin
                    register_result_status_q <= REGISTERED_INVALID_CONTEXT;
                end else if (registered_q[queue_register_context_id]) begin
                    register_result_status_q <= REGISTERED_DUPLICATE_CONTEXT;
                end else if (incarnation_ids_exhausted_q) begin
                    register_result_status_q <= REGISTERED_INCARNATION_EXHAUSTED;
                end else begin
                    register_result_status_q <= REGISTERED_OK;
                    register_result_incarnation_id_q <= next_incarnation_id_q;
                    registered_q[queue_register_context_id] <= 1'b1;
                    process_id_q[queue_register_context_id] <= queue_register_process_id;
                    address_space_id_q[queue_register_context_id]
                        <= queue_register_address_space_id;
                    priority_q[queue_register_context_id] <= queue_register_priority;
                    incarnation_id_q[queue_register_context_id] <= next_incarnation_id_q;
                    ring_read_index_q[queue_register_context_id] <= '0;
                    ring_write_index_q[queue_register_context_id] <= '0;
                    ring_unread_count_q[queue_register_context_id] <= '0;
                    producer_position_q[queue_register_context_id] <= '0;
                    consumer_position_q[queue_register_context_id] <= '0;
                    if (next_incarnation_id_q == 64'hffffffffffffffff)
                        incarnation_ids_exhausted_q <= 1'b1;
                    else
                        next_incarnation_id_q <= next_incarnation_id_q + 1'b1;
                end
            end

            if (external_recovery_fire) begin
                ring_read_index_q[ingress_recovery_context_id]
                    <= ring_write_index_q[ingress_recovery_context_id];
                ring_unread_count_q[ingress_recovery_context_id] <= '0;
                consumer_position_q[ingress_recovery_context_id]
                    <= producer_position_q[ingress_recovery_context_id];
            end else if (reset_cleanup_valid) begin
                ring_read_index_q[reset_cleanup_context_id]
                    <= ring_write_index_q[reset_cleanup_context_id];
                ring_unread_count_q[reset_cleanup_context_id] <= '0;
                consumer_position_q[reset_cleanup_context_id]
                    <= producer_position_q[reset_cleanup_context_id];
                reset_cleanup_done_q[reset_cleanup_context_id] <= 1'b1;
                reset_discard_start_q[reset_cleanup_context_id]
                    <= consumer_position_q[reset_cleanup_context_id];
                reset_discard_end_q[reset_cleanup_context_id]
                    <= producer_position_q[reset_cleanup_context_id];
            end else begin
                for (seq_queue = 0; seq_queue < QUEUE_CONTEXT_COUNT;
                     seq_queue = seq_queue + 1) begin
                    selected_consume_bytes = 0;
                    if ((submit_valid && submit_ready)
                        || (parser_completion_valid && parser_completion_ready
                            && parser_completion_status != 3'd3)) begin
                        if (feeder_state_q != FEED_IDLE
                            && feeder_context_id_q == seq_queue)
                            selected_consume_bytes = feeder_packet_bytes_q;
                    end

                    if (ingress_byte_valid && ingress_byte_ready
                        && ingress_byte_context_id == seq_queue) begin
                        current_ring_index = ring_write_index_q[seq_queue];
                        ring_memory[seq_queue][current_ring_index] <= ingress_byte_data;
                        ring_write_index_q[seq_queue]
                            <= RingIndexAfter(current_ring_index, 1);
                        producer_position_q[seq_queue]
                            <= producer_position_q[seq_queue] + 1'b1;
                    end

                    if (selected_consume_bytes != 0) begin
                        ring_read_index_q[seq_queue] <= RingIndexAfter(
                            ring_read_index_q[seq_queue], selected_consume_bytes);
                        consumer_position_q[seq_queue]
                            <= consumer_position_q[seq_queue] + selected_consume_bytes;
                    end

                    case ({(ingress_byte_valid && ingress_byte_ready
                                && ingress_byte_context_id == seq_queue),
                            (selected_consume_bytes != 0)})
                        2'b10: ring_unread_count_q[seq_queue]
                            <= ring_unread_count_q[seq_queue] + 1'b1;
                        2'b01: ring_unread_count_q[seq_queue]
                            <= ring_unread_count_q[seq_queue] - selected_consume_bytes;
                        2'b11: ring_unread_count_q[seq_queue]
                            <= ring_unread_count_q[seq_queue] + 1'b1
                                - selected_consume_bytes;
                        default: begin end
                    endcase
                end
            end

            if (submit_valid && submit_ready && feeder_state_q != FEED_IDLE) begin
                feeder_state_q <= FEED_IDLE;
                feeder_byte_index_q <= '0;
                round_robin_cursor_q <= feeder_context_id_q + 1'b1;
            end else if (parser_completion_valid && parser_completion_ready
                && feeder_state_q != FEED_IDLE) begin
                feeder_state_q <= FEED_IDLE;
                feeder_byte_index_q <= '0;
                round_robin_cursor_q <= feeder_context_id_q + 1'b1;
            end else if (feeder_state_q == FEED_PACKET) begin
                if (parser_completion_valid) begin
                    feeder_state_q <= FEED_RESULT;
                end else if (parser_command_valid && parser_command_ready) begin
                    if (feeder_byte_index_q + 1'b1 >= feeder_packet_bytes_q)
                        feeder_state_q <= FEED_RESULT;
                    feeder_byte_index_q <= feeder_byte_index_q + 1'b1;
                end
            end else if (feeder_state_q == FEED_IDLE && selected_packet_valid
                && !submit_valid && !parser_completion_valid) begin
                feeder_state_q <= FEED_PACKET;
                feeder_context_id_q <= selected_packet_context_id;
                feeder_packet_bytes_q <= selected_packet_bytes;
                feeder_byte_index_q <= '0;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (QUEUE_CONTEXT_COUNT < 1 || QUEUE_CONTEXT_COUNT > 64)
            $fatal(1, "command queue frontend context count must be in 1..64");
        if (RING_BYTES_PER_CONTEXT < 52 || RING_BYTES_PER_CONTEXT > 65536)
            $fatal(1, "command queue frontend ring capacity must be in 52..65536 bytes");
        if ((QUEUE_CONTEXT_COUNT * RING_BYTES_PER_CONTEXT) > (4 * 1024 * 1024))
            $fatal(1, "command queue frontend aggregate rings exceed 4 MiB");
        if (MAX_PACKET_BYTES < 52 || MAX_PACKET_BYTES > RING_BYTES_PER_CONTEXT)
            $fatal(1, "command queue frontend packet limit must fit its ring");
        if (RING_INDEX_WIDTH < $clog2(RING_BYTES_PER_CONTEXT)
            || RING_INDEX_WIDTH > 16
            || RING_COUNT_WIDTH < $clog2(RING_BYTES_PER_CONTEXT + 1)
            || RING_COUNT_WIDTH > 17)
            $fatal(1, "command queue frontend ring counter widths cannot represent configured capacity");
        if (WORKGROUP_ID_WIDTH < 1 || VIRTUAL_ADDRESS_WIDTH < 1
            || VIRTUAL_ADDRESS_WIDTH > 57)
            $fatal(1, "command queue frontend parser identity widths are invalid");
    end
`endif
endmodule
