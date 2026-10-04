// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Bounded streaming decoder for the provisional little-endian workgroup packet.
module cgx1_compute_workgroup_command_packet_parser #(
    parameter integer RESIDENT_WAVE_SLOTS = 8,
    parameter integer WORKGROUP_ID_WIDTH = 64,
    parameter integer VIRTUAL_ADDRESS_WIDTH = 57,
    parameter integer MAX_PACKET_BYTES = 4096,
    parameter integer WAVE_COUNT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1)
        ? 1 : $clog2(RESIDENT_WAVE_SLOTS + 1),
    parameter logic [WORKGROUP_ID_WIDTH-1:0] INITIAL_WORKGROUP_ID =
        {1'b1, {(WORKGROUP_ID_WIDTH-1){1'b0}}}
) (
    input logic clk,
    input logic reset_n,

    input logic command_valid,
    output logic command_ready,
    input logic command_start,
    input logic [7:0] command_data,
    input logic [5:0] command_queue_context_id,
    input logic [63:0] command_process_id,
    input logic [63:0] command_address_space_id,
    input logic [2:0] command_priority,
    input logic [63:0] command_queue_incarnation_id,
    input logic [63:0] command_packet_byte_position,

    input logic parser_recovery_valid,
    input logic [5:0] parser_recovery_context_id,

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
    output logic [4:0] parser_completion_failure,
    output logic [63:0] queue_faulted_mask
);
    localparam logic [1:0] ST_IDLE = 2'd0;
    localparam logic [1:0] ST_HEADER = 2'd1;
    localparam logic [1:0] ST_BODY = 2'd2;

    localparam logic [31:0] PACKET_MAGIC = 32'h3158_4743;
    localparam logic [15:0] WORKGROUP_DISPATCH_OPCODE = 16'd1;
    localparam logic [7:0] WORKGROUP_DISPATCH_VERSION = 8'd1;

    localparam logic [2:0] COMPLETION_ADMISSION_REJECTED = 3'd0;
    localparam logic [2:0] COMPLETION_UNSUPPORTED = 3'd1;
    localparam logic [2:0] COMPLETION_MALFORMED = 3'd2;
    localparam logic [2:0] COMPLETION_QUEUE_FAULTED = 3'd3;
    localparam logic [4:0] FAILURE_WORKGROUP_WAVE_LIMIT = 5'd2;

    logic [1:0] state_q;
    logic [63:0] queue_faulted_mask_q;
    logic [31:0] byte_index_q;
    logic [31:0] magic_q;
    logic [15:0] opcode_q;
    logic [7:0] version_q;
    logic [7:0] flags_q;
    logic [31:0] packet_length_q;
    logic [63:0] submission_id_q;
    logic [63:0] entry_pc_q;
    logic [15:0] wave_count_q;
    logic [15:0] scalar_units_q;
    logic [31:0] shared_bytes_q;
    logic [31:0] other_state_units_q;
    logic payload_malformed_q;
    logic [31:0] record_live_mask_q;
    logic [7:0] record_vgpr_low_q;
    logic [31:0] live_mask_by_wave_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [8:0] vgpr_count_by_wave_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [WORKGROUP_ID_WIDTH-1:0] next_workgroup_id_q;
    logic workgroup_id_exhausted_q;

    logic [5:0] captured_queue_context_id_q;
    logic [63:0] captured_process_id_q;
    logic [63:0] captured_address_space_id_q;
    logic [2:0] captured_priority_q;
    logic [63:0] captured_queue_incarnation_id_q;
    logic [63:0] captured_packet_byte_position_q;

    logic submit_valid_q;
    logic [5:0] submit_queue_context_id_q;
    logic [63:0] submit_process_id_q;
    logic [63:0] submit_address_space_id_q;
    logic [2:0] submit_priority_q;
    logic [WORKGROUP_ID_WIDTH-1:0] submit_workgroup_id_q;
    logic [63:0] submit_submission_id_q;
    logic [63:0] submit_packet_byte_position_q;
    logic [63:0] submit_queue_incarnation_id_q;
    logic [VIRTUAL_ADDRESS_WIDTH-1:0] submit_start_pc_q;
    logic [WAVE_COUNT_WIDTH-1:0] submit_wave_count_q;
    logic [15:0] submit_scalar_units_q;
    logic [31:0] submit_shared_bytes_q;
    logic [31:0] submit_other_state_units_q;

    logic parser_completion_valid_q;
    logic [5:0] parser_completion_queue_context_id_q;
    logic [63:0] parser_completion_process_id_q;
    logic [63:0] parser_completion_address_space_id_q;
    logic parser_completion_submission_id_valid_q;
    logic [63:0] parser_completion_submission_id_q;
    logic [63:0] parser_completion_packet_byte_position_q;
    logic [63:0] parser_completion_queue_incarnation_id_q;
    logic [WORKGROUP_ID_WIDTH-1:0] parser_completion_workgroup_id_q;
    logic [2:0] parser_completion_status_q;
    logic [4:0] parser_completion_failure_q;

    logic [31:0] header_length_candidate;
    logic [63:0] submission_id_after_byte;
    logic [63:0] entry_pc_after_byte;
    logic current_byte_payload_invalid;
    logic payload_malformed_after_byte;
    logic [15:0] current_wave_count;
    logic [15:0] current_vgpr_count;
    logic [31:0] current_expected_length;
    logic [31:0] record_relative_byte;
    integer current_wave_index;
    integer output_wave_index;
    integer reset_wave_index;

    assign submit_valid = submit_valid_q;
    assign submit_queue_context_id = submit_queue_context_id_q;
    assign submit_process_id = submit_process_id_q;
    assign submit_address_space_id = submit_address_space_id_q;
    assign submit_priority = submit_priority_q;
    assign submit_workgroup_id = submit_workgroup_id_q;
    assign submit_submission_id = submit_submission_id_q;
    assign submit_packet_byte_position = submit_packet_byte_position_q;
    assign submit_queue_incarnation_id = submit_queue_incarnation_id_q;
    assign submit_start_pc = submit_start_pc_q;
    assign submit_wave_count = submit_wave_count_q;
    assign submit_scalar_state_units_per_wave = submit_scalar_units_q;
    assign submit_shared_local_bytes = submit_shared_bytes_q;
    assign submit_other_workgroup_state_units = submit_other_state_units_q;

    assign parser_completion_valid = parser_completion_valid_q;
    assign parser_completion_queue_context_id = parser_completion_queue_context_id_q;
    assign parser_completion_process_id = parser_completion_process_id_q;
    assign parser_completion_address_space_id = parser_completion_address_space_id_q;
    assign parser_completion_submission_id_valid = parser_completion_submission_id_valid_q;
    assign parser_completion_submission_id = parser_completion_submission_id_q;
    assign parser_completion_packet_byte_position = parser_completion_packet_byte_position_q;
    assign parser_completion_queue_incarnation_id = parser_completion_queue_incarnation_id_q;
    assign parser_completion_workgroup_id = parser_completion_workgroup_id_q;
    assign parser_completion_status = parser_completion_status_q;
    assign parser_completion_failure = parser_completion_failure_q;
    assign queue_faulted_mask = queue_faulted_mask_q;

    always_comb begin
        command_ready = 1'b0;
        if (reset_n && !parser_recovery_valid && !submit_valid_q
            && !parser_completion_valid_q) begin
            if (state_q == ST_IDLE) begin
                if (command_start && !queue_faulted_mask_q[command_queue_context_id])
                    command_ready = 1'b1;
            end else if (!command_start) begin
                command_ready = 1'b1;
            end
        end

        submit_initial_live_lane_mask_flat = '0;
        submit_vgpr_register_counts_flat = '0;
        for (output_wave_index = 0; output_wave_index < RESIDENT_WAVE_SLOTS;
             output_wave_index = output_wave_index + 1) begin
            submit_initial_live_lane_mask_flat[output_wave_index*32 +: 32]
                = live_mask_by_wave_q[output_wave_index];
            submit_vgpr_register_counts_flat[output_wave_index*9 +: 9]
                = vgpr_count_by_wave_q[output_wave_index];
        end

        header_length_candidate = {command_data, packet_length_q[23:0]};
        submission_id_after_byte = submission_id_q;
        if (state_q == ST_BODY && byte_index_q >= 12 && byte_index_q <= 19)
            submission_id_after_byte[(byte_index_q - 12) * 8 +: 8] = command_data;

        current_byte_payload_invalid = 1'b0;
        entry_pc_after_byte = entry_pc_q;
        if (state_q == ST_BODY && byte_index_q >= 20 && byte_index_q <= 27)
            entry_pc_after_byte[(byte_index_q - 20) * 8 +: 8] = command_data;
        current_wave_count = wave_count_q;
        if (state_q == ST_BODY && byte_index_q == 29)
            current_wave_count = {command_data, wave_count_q[7:0]};
        current_vgpr_count = {command_data, record_vgpr_low_q};
        current_expected_length = 32'd44 + ({16'b0, current_wave_count} << 3);
        record_relative_byte = 0;
        current_wave_index = 0;

        if (state_q == ST_BODY) begin
            if (byte_index_q == 20 && command_data[1:0] != 2'b00)
                current_byte_payload_invalid = 1'b1;
            if (byte_index_q >= 20 && byte_index_q <= 27
                && (entry_pc_after_byte >> VIRTUAL_ADDRESS_WIDTH) != 0)
                current_byte_payload_invalid = 1'b1;
            if (byte_index_q == 29
                && (current_wave_count == 0
                    || current_expected_length != packet_length_q))
                current_byte_payload_invalid = 1'b1;
            if (byte_index_q >= 40 && byte_index_q <= 43 && command_data != 0)
                current_byte_payload_invalid = 1'b1;

            if (byte_index_q >= 44) begin
                record_relative_byte = byte_index_q - 44;
                current_wave_index = record_relative_byte >> 3;
                case (record_relative_byte[2:0])
                    3'd3: begin
                        if ({command_data, record_live_mask_q[23:0]} == 0)
                            current_byte_payload_invalid = 1'b1;
                    end
                    3'd5: begin
                        if (current_vgpr_count == 0 || current_vgpr_count > 16'd256)
                            current_byte_payload_invalid = 1'b1;
                    end
                    3'd6, 3'd7: begin
                        if (command_data != 0)
                            current_byte_payload_invalid = 1'b1;
                    end
                    default: begin end
                endcase
            end
        end
        payload_malformed_after_byte = payload_malformed_q | current_byte_payload_invalid;
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= ST_IDLE;
            queue_faulted_mask_q <= '0;
            byte_index_q <= '0;
            magic_q <= '0;
            opcode_q <= '0;
            version_q <= '0;
            flags_q <= '0;
            packet_length_q <= '0;
            submission_id_q <= '0;
            entry_pc_q <= '0;
            wave_count_q <= '0;
            scalar_units_q <= '0;
            shared_bytes_q <= '0;
            other_state_units_q <= '0;
            payload_malformed_q <= 1'b0;
            record_live_mask_q <= '0;
            record_vgpr_low_q <= '0;
            next_workgroup_id_q <= INITIAL_WORKGROUP_ID;
            workgroup_id_exhausted_q <= 1'b0;
            captured_queue_context_id_q <= '0;
            captured_process_id_q <= '0;
            captured_address_space_id_q <= '0;
            captured_priority_q <= '0;
            captured_queue_incarnation_id_q <= '0;
            captured_packet_byte_position_q <= '0;
            submit_valid_q <= 1'b0;
            submit_queue_context_id_q <= '0;
            submit_process_id_q <= '0;
            submit_address_space_id_q <= '0;
            submit_priority_q <= '0;
            submit_workgroup_id_q <= '0;
            submit_submission_id_q <= '0;
            submit_packet_byte_position_q <= '0;
            submit_queue_incarnation_id_q <= '0;
            submit_start_pc_q <= '0;
            submit_wave_count_q <= '0;
            submit_scalar_units_q <= '0;
            submit_shared_bytes_q <= '0;
            submit_other_state_units_q <= '0;
            parser_completion_valid_q <= 1'b0;
            parser_completion_queue_context_id_q <= '0;
            parser_completion_process_id_q <= '0;
            parser_completion_address_space_id_q <= '0;
            parser_completion_submission_id_valid_q <= 1'b0;
            parser_completion_submission_id_q <= '0;
            parser_completion_packet_byte_position_q <= '0;
            parser_completion_queue_incarnation_id_q <= '0;
            parser_completion_workgroup_id_q <= '0;
            parser_completion_status_q <= '0;
            parser_completion_failure_q <= '0;
            for (reset_wave_index = 0; reset_wave_index < RESIDENT_WAVE_SLOTS;
                 reset_wave_index = reset_wave_index + 1) begin
                live_mask_by_wave_q[reset_wave_index] <= '0;
                vgpr_count_by_wave_q[reset_wave_index] <= '0;
            end
        end else begin
            if (submit_valid_q && submit_ready)
                submit_valid_q <= 1'b0;
            if (parser_completion_valid_q && parser_completion_ready)
                parser_completion_valid_q <= 1'b0;

            if (parser_recovery_valid) begin
                // Parser recovery clears framing fault state; downstream scheduler entries
                // remain owned by the scheduler and are not cancelled by this pulse.
                queue_faulted_mask_q[parser_recovery_context_id] <= 1'b0;
                if (state_q != ST_IDLE
                    && captured_queue_context_id_q == parser_recovery_context_id) begin
                    state_q <= ST_IDLE;
                    byte_index_q <= '0;
                    payload_malformed_q <= 1'b0;
                end
            end else if (command_valid && command_ready) begin
                if (state_q == ST_IDLE) begin
                    state_q <= ST_HEADER;
                    byte_index_q <= 32'd1;
                    magic_q <= {24'b0, command_data};
                    opcode_q <= '0;
                    version_q <= '0;
                    flags_q <= '0;
                    packet_length_q <= '0;
                    submission_id_q <= '0;
                    entry_pc_q <= '0;
                    wave_count_q <= '0;
                    scalar_units_q <= '0;
                    shared_bytes_q <= '0;
                    other_state_units_q <= '0;
                    payload_malformed_q <= 1'b0;
                    record_live_mask_q <= '0;
                    record_vgpr_low_q <= '0;
                    captured_queue_context_id_q <= command_queue_context_id;
                    captured_process_id_q <= command_process_id;
                    captured_address_space_id_q <= command_address_space_id;
                    captured_priority_q <= command_priority;
                    captured_queue_incarnation_id_q <= command_queue_incarnation_id;
                    captured_packet_byte_position_q <= command_packet_byte_position;
                    for (reset_wave_index = 0; reset_wave_index < RESIDENT_WAVE_SLOTS;
                         reset_wave_index = reset_wave_index + 1) begin
                        live_mask_by_wave_q[reset_wave_index] <= '0;
                        vgpr_count_by_wave_q[reset_wave_index] <= '0;
                    end
                end else if (state_q == ST_HEADER) begin
                    case (byte_index_q)
                        32'd1: magic_q[15:8] <= command_data;
                        32'd2: magic_q[23:16] <= command_data;
                        32'd3: magic_q[31:24] <= command_data;
                        32'd4: opcode_q[7:0] <= command_data;
                        32'd5: opcode_q[15:8] <= command_data;
                        32'd6: version_q <= command_data;
                        32'd7: flags_q <= command_data;
                        32'd8: packet_length_q[7:0] <= command_data;
                        32'd9: packet_length_q[15:8] <= command_data;
                        32'd10: packet_length_q[23:16] <= command_data;
                        default: begin end
                    endcase

                    if (byte_index_q == 32'd11) begin
                        if (magic_q != PACKET_MAGIC
                            || header_length_candidate < 12
                            || header_length_candidate > MAX_PACKET_BYTES
                            || header_length_candidate[1:0] != 2'b00) begin
                            queue_faulted_mask_q[captured_queue_context_id_q] <= 1'b1;
                            state_q <= ST_IDLE;
                            byte_index_q <= '0;
                            parser_completion_valid_q <= 1'b1;
                            parser_completion_queue_context_id_q <= captured_queue_context_id_q;
                            parser_completion_process_id_q <= captured_process_id_q;
                            parser_completion_address_space_id_q <= captured_address_space_id_q;
                            parser_completion_submission_id_valid_q <= 1'b0;
                            parser_completion_submission_id_q <= '0;
                            parser_completion_packet_byte_position_q <= captured_packet_byte_position_q;
                            parser_completion_queue_incarnation_id_q <= captured_queue_incarnation_id_q;
                            parser_completion_workgroup_id_q <= '0;
                            parser_completion_status_q <= COMPLETION_QUEUE_FAULTED;
                            parser_completion_failure_q <= '0;
                        end else begin
                            packet_length_q <= header_length_candidate;
                            if (header_length_candidate == 12) begin
                                state_q <= ST_IDLE;
                                byte_index_q <= '0;
                                parser_completion_valid_q <= 1'b1;
                                parser_completion_queue_context_id_q <= captured_queue_context_id_q;
                                parser_completion_process_id_q <= captured_process_id_q;
                                parser_completion_address_space_id_q <= captured_address_space_id_q;
                                parser_completion_submission_id_valid_q <= 1'b0;
                                parser_completion_submission_id_q <= '0;
                                parser_completion_packet_byte_position_q <= captured_packet_byte_position_q;
                                parser_completion_queue_incarnation_id_q <= captured_queue_incarnation_id_q;
                                parser_completion_workgroup_id_q <= '0;
                                parser_completion_failure_q <= '0;
                                if (flags_q != 0)
                                    parser_completion_status_q <= COMPLETION_MALFORMED;
                                else if (opcode_q != WORKGROUP_DISPATCH_OPCODE
                                    || version_q != WORKGROUP_DISPATCH_VERSION)
                                    parser_completion_status_q <= COMPLETION_UNSUPPORTED;
                                else
                                    parser_completion_status_q <= COMPLETION_MALFORMED;
                            end else begin
                                state_q <= ST_BODY;
                                byte_index_q <= 32'd12;
                            end
                        end
                    end else begin
                        byte_index_q <= byte_index_q + 1'b1;
                    end
                end else if (state_q == ST_BODY) begin
                    if (byte_index_q >= 12 && byte_index_q <= 19)
                        submission_id_q[(byte_index_q - 12) * 8 +: 8] <= command_data;
                    if (byte_index_q >= 20 && byte_index_q <= 27)
                        entry_pc_q[(byte_index_q - 20) * 8 +: 8] <= command_data;
                    if (byte_index_q == 28)
                        wave_count_q[7:0] <= command_data;
                    if (byte_index_q == 29)
                        wave_count_q[15:8] <= command_data;
                    if (byte_index_q == 30)
                        scalar_units_q[7:0] <= command_data;
                    if (byte_index_q == 31)
                        scalar_units_q[15:8] <= command_data;
                    if (byte_index_q >= 32 && byte_index_q <= 35)
                        shared_bytes_q[(byte_index_q - 32) * 8 +: 8] <= command_data;
                    if (byte_index_q >= 36 && byte_index_q <= 39)
                        other_state_units_q[(byte_index_q - 36) * 8 +: 8] <= command_data;

                    if (byte_index_q >= 44) begin
                        case (record_relative_byte[2:0])
                            3'd0: record_live_mask_q <= {24'b0, command_data};
                            3'd1: record_live_mask_q[15:8] <= command_data;
                            3'd2: record_live_mask_q[23:16] <= command_data;
                            3'd3: begin
                                record_live_mask_q[31:24] <= command_data;
                                if (current_wave_index < RESIDENT_WAVE_SLOTS)
                                    live_mask_by_wave_q[current_wave_index]
                                        <= {command_data, record_live_mask_q[23:0]};
                            end
                            3'd4: record_vgpr_low_q <= command_data;
                            3'd5: begin
                                if (current_wave_index < RESIDENT_WAVE_SLOTS)
                                    vgpr_count_by_wave_q[current_wave_index]
                                        <= {command_data[0], record_vgpr_low_q};
                            end
                            default: begin end
                        endcase
                    end

                    if (payload_malformed_after_byte)
                        payload_malformed_q <= 1'b1;

                    if (byte_index_q == packet_length_q - 1'b1) begin
                        state_q <= ST_IDLE;
                        byte_index_q <= '0;
                        if (flags_q != 0) begin
                            parser_completion_valid_q <= 1'b1;
                            parser_completion_queue_context_id_q <= captured_queue_context_id_q;
                            parser_completion_process_id_q <= captured_process_id_q;
                            parser_completion_address_space_id_q <= captured_address_space_id_q;
                            parser_completion_submission_id_valid_q <= packet_length_q >= 20;
                            parser_completion_submission_id_q <= submission_id_after_byte;
                            parser_completion_packet_byte_position_q <= captured_packet_byte_position_q;
                            parser_completion_queue_incarnation_id_q <= captured_queue_incarnation_id_q;
                            parser_completion_workgroup_id_q <= '0;
                            parser_completion_status_q <= COMPLETION_MALFORMED;
                            parser_completion_failure_q <= '0;
                        end else if (opcode_q != WORKGROUP_DISPATCH_OPCODE
                            || version_q != WORKGROUP_DISPATCH_VERSION) begin
                            parser_completion_valid_q <= 1'b1;
                            parser_completion_queue_context_id_q <= captured_queue_context_id_q;
                            parser_completion_process_id_q <= captured_process_id_q;
                            parser_completion_address_space_id_q <= captured_address_space_id_q;
                            parser_completion_submission_id_valid_q <= 1'b0;
                            parser_completion_submission_id_q <= '0;
                            parser_completion_packet_byte_position_q <= captured_packet_byte_position_q;
                            parser_completion_queue_incarnation_id_q <= captured_queue_incarnation_id_q;
                            parser_completion_workgroup_id_q <= '0;
                            parser_completion_status_q <= COMPLETION_UNSUPPORTED;
                            parser_completion_failure_q <= '0;
                        end else if (packet_length_q < 44 || payload_malformed_after_byte) begin
                            parser_completion_valid_q <= 1'b1;
                            parser_completion_queue_context_id_q <= captured_queue_context_id_q;
                            parser_completion_process_id_q <= captured_process_id_q;
                            parser_completion_address_space_id_q <= captured_address_space_id_q;
                            parser_completion_submission_id_valid_q <= packet_length_q >= 44;
                            parser_completion_submission_id_q <= submission_id_after_byte;
                            parser_completion_packet_byte_position_q <= captured_packet_byte_position_q;
                            parser_completion_queue_incarnation_id_q <= captured_queue_incarnation_id_q;
                            parser_completion_workgroup_id_q <= '0;
                            parser_completion_status_q <= COMPLETION_MALFORMED;
                            parser_completion_failure_q <= '0;
                        end else if (workgroup_id_exhausted_q) begin
                            queue_faulted_mask_q[captured_queue_context_id_q] <= 1'b1;
                            parser_completion_valid_q <= 1'b1;
                            parser_completion_queue_context_id_q <= captured_queue_context_id_q;
                            parser_completion_process_id_q <= captured_process_id_q;
                            parser_completion_address_space_id_q <= captured_address_space_id_q;
                            parser_completion_submission_id_valid_q <= 1'b1;
                            parser_completion_submission_id_q <= submission_id_after_byte;
                            parser_completion_packet_byte_position_q <= captured_packet_byte_position_q;
                            parser_completion_queue_incarnation_id_q <= captured_queue_incarnation_id_q;
                            parser_completion_workgroup_id_q <= '0;
                            parser_completion_status_q <= COMPLETION_QUEUE_FAULTED;
                            parser_completion_failure_q <= '0;
                        end else if (wave_count_q > RESIDENT_WAVE_SLOTS) begin
                            parser_completion_valid_q <= 1'b1;
                            parser_completion_queue_context_id_q <= captured_queue_context_id_q;
                            parser_completion_process_id_q <= captured_process_id_q;
                            parser_completion_address_space_id_q <= captured_address_space_id_q;
                            parser_completion_submission_id_valid_q <= 1'b1;
                            parser_completion_submission_id_q <= submission_id_after_byte;
                            parser_completion_packet_byte_position_q <= captured_packet_byte_position_q;
                            parser_completion_queue_incarnation_id_q <= captured_queue_incarnation_id_q;
                            parser_completion_workgroup_id_q <= next_workgroup_id_q;
                            parser_completion_status_q <= COMPLETION_ADMISSION_REJECTED;
                            parser_completion_failure_q <= FAILURE_WORKGROUP_WAVE_LIMIT;
                            if (&next_workgroup_id_q)
                                workgroup_id_exhausted_q <= 1'b1;
                            else
                                next_workgroup_id_q <= next_workgroup_id_q + 1'b1;
                        end else begin
                            submit_valid_q <= 1'b1;
                            submit_queue_context_id_q <= captured_queue_context_id_q;
                            submit_process_id_q <= captured_process_id_q;
                            submit_address_space_id_q <= captured_address_space_id_q;
                            submit_priority_q <= captured_priority_q;
                            submit_workgroup_id_q <= next_workgroup_id_q;
                            submit_submission_id_q <= submission_id_after_byte;
                            submit_packet_byte_position_q <= captured_packet_byte_position_q;
                            submit_queue_incarnation_id_q <= captured_queue_incarnation_id_q;
                            submit_start_pc_q <= entry_pc_q[VIRTUAL_ADDRESS_WIDTH-1:0];
                            submit_wave_count_q <= wave_count_q[WAVE_COUNT_WIDTH-1:0];
                            submit_scalar_units_q <= scalar_units_q;
                            submit_shared_bytes_q <= shared_bytes_q;
                            submit_other_state_units_q <= other_state_units_q;
                            if (&next_workgroup_id_q)
                                workgroup_id_exhausted_q <= 1'b1;
                            else
                                next_workgroup_id_q <= next_workgroup_id_q + 1'b1;
                        end
                    end else begin
                        byte_index_q <= byte_index_q + 1'b1;
                    end
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (VIRTUAL_ADDRESS_WIDTH < 1 || VIRTUAL_ADDRESS_WIDTH > 57)
            $fatal(1, "command parser virtual address width must be in [1, 57]");
    end
`endif
endmodule
