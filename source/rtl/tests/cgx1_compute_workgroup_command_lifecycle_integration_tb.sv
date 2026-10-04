// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
`timescale 1ns/1ps
module cgx1_compute_workgroup_command_lifecycle_integration_tb;
    localparam integer QUEUES = 4;
    localparam integer RING_BYTES = 256;
    localparam integer COUNT_WIDTH = $clog2(RING_BYTES + 1);
    localparam integer SLOTS = 2;
    localparam integer WG_WIDTH = 16;
    localparam integer PC_WIDTH = 57;
    localparam integer WAVE_WIDTH = $clog2(SLOTS + 1);
    localparam integer SLOT_WIDTH = $clog2(SLOTS);
    localparam integer PACKET_BYTES = 128;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    always #5 clk = ~clk;

    logic register_valid = 1'b0;
    logic register_ready;
    logic [5:0] register_context_id = '0;
    logic [63:0] register_process_id = '0;
    logic [63:0] register_address_space_id = '0;
    logic [2:0] register_priority = '0;
    logic register_result_valid;
    logic [5:0] register_result_context_id;
    logic [1:0] register_result_status;
    logic [63:0] register_result_incarnation_id;

    logic byte_valid = 1'b0;
    logic byte_ready;
    logic [5:0] byte_context_id = '0;
    logic [7:0] byte_data = '0;
    logic queue_reset_valid = 1'b0;
    logic queue_reset_ready;
    logic [5:0] queue_reset_context_id = '0;
    logic [63:0] queue_reset_pending_mask;
    logic queue_reset_complete_valid;
    logic queue_reset_complete_ready = 1'b0;
    logic [5:0] queue_reset_complete_context_id;
    logic [63:0] queue_reset_complete_incarnation_id;
    logic [63:0] queue_reset_discard_start_position;
    logic [63:0] queue_reset_discard_end_position;
    logic [63:0] registered_context_mask;
    logic [63:0] faulted_context_mask;
    logic [(QUEUES*COUNT_WIDTH)-1:0] unread_bytes_flat;
    logic [(QUEUES*64)-1:0] producer_position_flat;
    logic [(QUEUES*64)-1:0] consumer_position_flat;

    logic submit_valid;
    logic submit_ready;
    logic [5:0] submit_queue_context_id;
    logic [63:0] submit_process_id;
    logic [63:0] submit_address_space_id;
    logic [2:0] submit_priority;
    logic [WG_WIDTH-1:0] submit_workgroup_id;
    logic [63:0] submit_submission_id;
    logic [63:0] submit_packet_byte_position;
    logic [63:0] submit_queue_incarnation_id;
    logic [PC_WIDTH-1:0] submit_start_pc;
    logic [WAVE_WIDTH-1:0] submit_wave_count;
    logic [(SLOTS*32)-1:0] submit_initial_live_lane_mask_flat;
    logic [(SLOTS*9)-1:0] submit_vgpr_register_counts_flat;
    logic [15:0] submit_scalar_state_units_per_wave;
    logic [31:0] submit_shared_local_bytes;
    logic [31:0] submit_other_workgroup_state_units;
    logic parser_completion_valid;
    logic [5:0] parser_completion_queue_context_id;
    logic [63:0] parser_completion_process_id;
    logic [63:0] parser_completion_address_space_id;
    logic parser_completion_submission_id_valid;
    logic [63:0] parser_completion_submission_id;
    logic [63:0] parser_completion_packet_byte_position;
    logic [63:0] parser_completion_queue_incarnation_id;
    logic [WG_WIDTH-1:0] parser_completion_workgroup_id;
    logic [2:0] parser_completion_status;
    logic [4:0] parser_completion_failure;

    logic tile_eligible = 1'b1;
    logic dispatch_valid;
    logic dispatch_ready;
    logic [5:0] dispatch_queue_context_id;
    logic [63:0] dispatch_process_id;
    logic [63:0] dispatch_address_space_id;
    logic [2:0] dispatch_priority;
    logic [WG_WIDTH-1:0] dispatch_workgroup_id;
    logic [WAVE_WIDTH-1:0] dispatch_wave_count;
    logic [PC_WIDTH-1:0] dispatch_start_pc;
    logic [(SLOTS*32)-1:0] dispatch_initial_live_lane_mask_flat;
    logic [(SLOTS*9)-1:0] dispatch_vgpr_register_counts_flat;
    logic [15:0] dispatch_scalar_state_units_per_wave;
    logic [31:0] dispatch_shared_local_bytes;
    logic [31:0] dispatch_other_workgroup_state_units;
    logic [63:0] dispatch_submission_id;
    logic [63:0] dispatch_packet_byte_position;
    logic [63:0] dispatch_queue_incarnation_id;
    logic dispatch_result_valid;
    logic dispatch_accepted;
    logic [4:0] dispatch_failure;
    logic admission_completion_valid;
    logic admission_completion_ready;
    logic [5:0] admission_queue_context_id;
    logic [63:0] admission_process_id;
    logic [63:0] admission_address_space_id;
    logic [WG_WIDTH-1:0] admission_workgroup_id;
    logic [63:0] admission_submission_id;
    logic [63:0] admission_packet_byte_position;
    logic [63:0] admission_queue_incarnation_id;
    logic [2:0] admission_status;
    logic [4:0] admission_failure;
    logic [3:0] pending_count;

    logic [63:0] lifecycle_drained_mask;
    logic lifecycle_submit_capacity_ready;
    logic submit_accepted_valid;
    logic workgroup_retire_valid;
    logic workgroup_retire_ready;
    logic [WG_WIDTH-1:0] workgroup_retire_id;
    logic workgroup_abort_valid;
    logic workgroup_abort_ready;
    logic [WG_WIDTH-1:0] workgroup_abort_id;
    logic command_completion_valid;
    logic command_completion_ready = 1'b0;
    logic [5:0] command_completion_queue_context_id;
    logic [63:0] command_completion_process_id;
    logic [63:0] command_completion_address_space_id;
    logic [WG_WIDTH-1:0] command_completion_workgroup_id;
    logic [63:0] command_completion_submission_id;
    logic [63:0] command_completion_packet_byte_position;
    logic [63:0] command_completion_queue_incarnation_id;
    logic [2:0] command_completion_status;
    logic [4:0] command_completion_failure;
    logic [4:0] tracked_count;

    logic terminate_valid = 1'b0;
    logic [0:0] terminate_wave_slot = '0;
    logic terminate_ready;
    logic terminate_accepted;
    logic [SLOTS-1:0] allocation_active_bitmap;
    logic [1:0] workgroup_active_mask;
    logic [WAVE_WIDTH-1:0] resident_wave_count;
    logic [31:0] shared_local_bytes_used;

    logic [SLOTS-1:0] memory_issue_valid = '0;
    logic [SLOTS-1:0] memory_issue_ready;
    logic [SLOTS-1:0] memory_issue_accepted;
    logic [SLOTS-1:0] memory_issue_global = '0;
    logic [SLOTS-1:0] memory_issue_write = '0;
    logic [(SLOTS*8)-1:0] memory_issue_destination_flat = '0;
    logic [(SLOTS*32)-1:0] memory_issue_lane_mask_flat = '0;
    logic [(SLOTS*32*PC_WIDTH)-1:0] memory_issue_byte_addresses_flat = '0;
    logic [(SLOTS*1024)-1:0] memory_issue_store_data_flat = '0;
    logic [SLOTS-1:0] memory_waiting_mask;
    logic [SLOTS-1:0] memory_load_destination_pending_mask;
    logic memory_global_request_valid;
    logic memory_global_request_ready = 1'b0;
    logic [WG_WIDTH-1:0] memory_global_request_workgroup_id;
    logic [SLOT_WIDTH-1:0] memory_global_request_wave_slot;
    logic [31:0] memory_global_request_epoch;
    logic [63:0] memory_global_request_transaction_tag;
    logic memory_global_request_write;
    logic [31:0] memory_global_request_lane_mask;
    logic [(32*PC_WIDTH)-1:0] memory_global_request_byte_addresses_flat;
    logic [1023:0] memory_global_request_store_data_flat;
    logic memory_global_response_valid = 1'b0;
    logic memory_global_response_ready;
    logic [WG_WIDTH-1:0] memory_global_response_workgroup_id = '0;
    logic [SLOT_WIDTH-1:0] memory_global_response_wave_slot = '0;
    logic [31:0] memory_global_response_epoch = '0;
    logic [63:0] memory_global_response_transaction_tag = '0;
    logic memory_global_response_write = 1'b0;
    logic [31:0] memory_global_response_lane_mask = '0;
    logic [1023:0] memory_global_response_lane_data_flat = '0;
    logic [2:0] memory_global_response_fault_code = '0;
    logic [5:0] memory_global_response_fault_lane = '0;
    logic [WG_WIDTH-1:0] held_memory_workgroup_id;
    logic [SLOT_WIDTH-1:0] held_memory_wave_slot;
    logic [31:0] held_memory_epoch;
    logic [63:0] held_memory_transaction_tag;
    logic [31:0] held_memory_lane_mask;

    assign submit_accepted_valid = submit_valid && submit_ready;

    cgx1_compute_workgroup_command_queue_frontend #(
        .QUEUE_CONTEXT_COUNT(QUEUES),
        .RING_BYTES_PER_CONTEXT(RING_BYTES),
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .WORKGROUP_ID_WIDTH(WG_WIDTH),
        .VIRTUAL_ADDRESS_WIDTH(PC_WIDTH),
        .MAX_PACKET_BYTES(PACKET_BYTES)
    ) queue_frontend (
        .clk(clk), .reset_n(reset_n),
        .queue_register_valid(register_valid), .queue_register_ready(register_ready),
        .queue_register_context_id(register_context_id),
        .queue_register_process_id(register_process_id),
        .queue_register_address_space_id(register_address_space_id),
        .queue_register_priority(register_priority),
        .queue_register_result_valid(register_result_valid),
        .queue_register_result_ready(1'b1),
        .queue_register_result_context_id(register_result_context_id),
        .queue_register_result_status(register_result_status),
        .queue_register_result_incarnation_id(register_result_incarnation_id),
        .ingress_byte_valid(byte_valid), .ingress_byte_ready(byte_ready),
        .ingress_byte_context_id(byte_context_id), .ingress_byte_data(byte_data),
        .ingress_recovery_valid(1'b0), .ingress_recovery_context_id('0),
        .ingress_recovery_ready(),
        .queue_reset_valid(queue_reset_valid), .queue_reset_ready(queue_reset_ready),
        .queue_reset_context_id(queue_reset_context_id),
        .queue_reset_pending_mask(queue_reset_pending_mask),
        .queue_lifecycle_drained_mask(lifecycle_drained_mask),
        .queue_reset_complete_valid(queue_reset_complete_valid),
        .queue_reset_complete_ready(queue_reset_complete_ready),
        .queue_reset_complete_context_id(queue_reset_complete_context_id),
        .queue_reset_complete_incarnation_id(queue_reset_complete_incarnation_id),
        .queue_reset_discard_start_position(queue_reset_discard_start_position),
        .queue_reset_discard_end_position(queue_reset_discard_end_position),
        .registered_context_mask(registered_context_mask),
        .faulted_context_mask(faulted_context_mask),
        .unread_bytes_flat(unread_bytes_flat),
        .producer_position_flat(producer_position_flat),
        .consumer_position_flat(consumer_position_flat),
        .submit_valid(submit_valid), .submit_ready(submit_ready),
        .submit_queue_context_id(submit_queue_context_id),
        .submit_process_id(submit_process_id),
        .submit_address_space_id(submit_address_space_id),
        .submit_priority(submit_priority), .submit_workgroup_id(submit_workgroup_id),
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
        .parser_completion_ready(1'b1),
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
        .RESIDENT_WAVE_SLOTS(SLOTS), .MAX_PENDING_ENTRIES(8),
        .WORKGROUP_ID_WIDTH(WG_WIDTH), .VIRTUAL_ADDRESS_WIDTH(PC_WIDTH)
    ) dispatcher (
        .clk(clk), .reset_n(reset_n), .tile_eligible(tile_eligible),
        // Parser framing faults are ingress-local; queue reset drives the
        // explicit downstream cancellation mask below.
        .faulted_queue_mask(64'b0),
        .cancelled_queue_mask(queue_reset_pending_mask),
        .lifecycle_ready(lifecycle_submit_capacity_ready),
        .submit_valid(submit_valid), .submit_ready(submit_ready),
        .submit_queue_context_id(submit_queue_context_id),
        .submit_process_id(submit_process_id),
        .submit_address_space_id(submit_address_space_id),
        .submit_priority(submit_priority), .submit_graphics(1'b0),
        .submit_workgroup_id(submit_workgroup_id), .submit_wave_count(submit_wave_count),
        .submit_start_pc(submit_start_pc),
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
        .dispatch_priority(dispatch_priority), .dispatch_workgroup_id(dispatch_workgroup_id),
        .dispatch_wave_count(dispatch_wave_count), .dispatch_start_pc(dispatch_start_pc),
        .dispatch_initial_live_lane_mask_flat(dispatch_initial_live_lane_mask_flat),
        .dispatch_vgpr_register_counts_flat(dispatch_vgpr_register_counts_flat),
        .dispatch_scalar_state_units_per_wave(dispatch_scalar_state_units_per_wave),
        .dispatch_shared_local_bytes(dispatch_shared_local_bytes),
        .dispatch_other_workgroup_state_units(dispatch_other_workgroup_state_units),
        .dispatch_submission_id(dispatch_submission_id),
        .dispatch_packet_byte_position(dispatch_packet_byte_position),
        .dispatch_queue_incarnation_id(dispatch_queue_incarnation_id),
        .dispatch_result_valid(dispatch_result_valid),
        .dispatch_accepted(dispatch_accepted), .dispatch_failure(dispatch_failure),
        .completion_valid(admission_completion_valid),
        .completion_ready(admission_completion_ready),
        .completion_queue_context_id(admission_queue_context_id),
        .completion_process_id(admission_process_id),
        .completion_address_space_id(admission_address_space_id),
        .completion_workgroup_id(admission_workgroup_id),
        .completion_submission_id(admission_submission_id),
        .completion_packet_byte_position(admission_packet_byte_position),
        .completion_queue_incarnation_id(admission_queue_incarnation_id),
        .completion_status(admission_status), .completion_failure(admission_failure),
        .pending_count(pending_count)
    );

    cgx1_compute_workgroup_command_lifecycle #(
        .QUEUE_CONTEXT_COUNT(64), .COMMAND_SLOTS(16),
        .WORKGROUP_ID_WIDTH(WG_WIDTH)
    ) lifecycle (
        .clk(clk), .reset_n(reset_n),
        .submit_accepted_valid(submit_accepted_valid),
        .submit_capacity_ready(lifecycle_submit_capacity_ready),
        .submit_queue_context_id(submit_queue_context_id),
        .submit_process_id(submit_process_id),
        .submit_address_space_id(submit_address_space_id),
        .submit_workgroup_id(submit_workgroup_id),
        .submit_submission_id(submit_submission_id),
        .submit_packet_byte_position(submit_packet_byte_position),
        .submit_queue_incarnation_id(submit_queue_incarnation_id),
        .admission_valid(admission_completion_valid),
        .admission_ready(admission_completion_ready),
        .admission_queue_context_id(admission_queue_context_id),
        .admission_process_id(admission_process_id),
        .admission_address_space_id(admission_address_space_id),
        .admission_workgroup_id(admission_workgroup_id),
        .admission_submission_id(admission_submission_id),
        .admission_packet_byte_position(admission_packet_byte_position),
        .admission_queue_incarnation_id(admission_queue_incarnation_id),
        .admission_status(admission_status), .admission_failure(admission_failure),
        .cancelled_queue_mask(queue_reset_pending_mask),
        .workgroup_retire_valid(workgroup_retire_valid),
        .workgroup_retire_ready(workgroup_retire_ready),
        .workgroup_retire_id(workgroup_retire_id),
        .workgroup_abort_valid(workgroup_abort_valid),
        .workgroup_abort_ready(workgroup_abort_ready),
        .workgroup_abort_id(workgroup_abort_id),
        .completion_valid(command_completion_valid),
        .completion_ready(command_completion_ready),
        .completion_queue_context_id(command_completion_queue_context_id),
        .completion_process_id(command_completion_process_id),
        .completion_address_space_id(command_completion_address_space_id),
        .completion_workgroup_id(command_completion_workgroup_id),
        .completion_submission_id(command_completion_submission_id),
        .completion_packet_byte_position(command_completion_packet_byte_position),
        .completion_queue_incarnation_id(command_completion_queue_incarnation_id),
        .completion_status(command_completion_status),
        .completion_failure(command_completion_failure),
        .queue_drained_mask(lifecycle_drained_mask), .tracked_count(tracked_count)
    );

    cgx1_compute_workgroup_execution_frontend #(
        .PHYSICAL_ROWS(32), .RESIDENT_WAVE_SLOTS(SLOTS),
        .MAX_WORKGROUP_CONTEXTS(2), .SCALAR_PREDICATE_STATE_UNITS(8),
        .SHARED_LOCAL_MEMORY_BYTES(1024), .OTHER_WORKGROUP_STATE_UNITS(8),
        .WORKGROUP_ID_WIDTH(WG_WIDTH), .VIRTUAL_ADDRESS_WIDTH(PC_WIDTH)
    ) compute_frontend (
        .clk(clk), .reset_n(reset_n),
        .dispatch_valid(dispatch_valid), .dispatch_ready(dispatch_ready),
        .dispatch_workgroup_id(dispatch_workgroup_id), .dispatch_wave_count(dispatch_wave_count),
        .dispatch_start_pc(dispatch_start_pc),
        .dispatch_initial_live_lane_mask_flat(dispatch_initial_live_lane_mask_flat),
        .dispatch_vgpr_register_counts_flat(dispatch_vgpr_register_counts_flat),
        .dispatch_scalar_state_units_per_wave(dispatch_scalar_state_units_per_wave),
        .dispatch_shared_local_bytes(dispatch_shared_local_bytes),
        .dispatch_other_workgroup_state_units(dispatch_other_workgroup_state_units),
        .dispatch_result_valid(dispatch_result_valid), .dispatch_accepted(dispatch_accepted),
        .dispatch_failure(dispatch_failure),
        .barrier_arrive_valid(1'b0), .barrier_arrive_workgroup_id('0),
        .barrier_arrive_local_wave_mask('0),
        .terminate_wave_valid(terminate_valid), .terminate_wave_slot(terminate_wave_slot),
        .terminate_wave_reason(2'b00), .terminate_wave_ready(terminate_ready),
        .terminate_wave_accepted(terminate_accepted),
        .workgroup_abort_valid(workgroup_abort_valid),
        .workgroup_abort_id(workgroup_abort_id),
        .workgroup_abort_ready(workgroup_abort_ready), .workgroup_abort_accepted(),
        .workgroup_retire_valid(workgroup_retire_valid),
        .workgroup_retire_ready(workgroup_retire_ready),
        .workgroup_retire_id(workgroup_retire_id),
        .decoded_sequential_pc_flat('0), .control_event_valid(1'b0),
        .control_event_wave_slot('0), .control_event_kind('0),
        .control_event_sequential_pc('0), .control_event_target_pc('0),
        .control_event_fallthrough_pc('0), .control_event_join_pc('0),
        .control_event_return_pc('0), .control_event_loop_test_pc('0),
        .control_event_loop_body_pc('0), .control_event_loop_exit_pc('0),
        .control_event_taken_mask('0), .control_event_continue_mask('0),
        .restore_valid(1'b0), .restore_wave_slot('0), .restore_register('0),
        .restore_data('0), .matrix_request_valid('0),
        .matrix_request_full_wave_active('0), .matrix_request_d_base('0),
        .matrix_request_a_base('0), .matrix_request_b_base('0),
        .vector_request_valid('0), .vector_request_opcode('0),
        .vector_request_source0('0), .vector_request_source1('0),
        .vector_request_destination('0), .vector_request_lane_mask('0),
        .memory_epoch(32'b0), .memory_issue_valid(memory_issue_valid),
        .memory_issue_ready(memory_issue_ready), .memory_issue_accepted(memory_issue_accepted),
        .memory_issue_global(memory_issue_global), .memory_issue_write(memory_issue_write),
        .memory_issue_destination_flat(memory_issue_destination_flat),
        .memory_issue_lane_mask_flat(memory_issue_lane_mask_flat),
        .memory_issue_byte_addresses_flat(memory_issue_byte_addresses_flat),
        .memory_issue_store_data_flat(memory_issue_store_data_flat),
        .memory_waiting_mask(memory_waiting_mask),
        .memory_load_destination_pending_mask(memory_load_destination_pending_mask),
        .memory_completion_ready(1'b1), .memory_fault_ready(1'b1),
        .memory_global_request_valid(memory_global_request_valid),
        .memory_global_request_ready(memory_global_request_ready),
        .memory_global_request_workgroup_id(memory_global_request_workgroup_id),
        .memory_global_request_wave_slot(memory_global_request_wave_slot),
        .memory_global_request_epoch(memory_global_request_epoch),
        .memory_global_request_transaction_tag(memory_global_request_transaction_tag),
        .memory_global_request_write(memory_global_request_write),
        .memory_global_request_lane_mask(memory_global_request_lane_mask),
        .memory_global_request_byte_addresses_flat(memory_global_request_byte_addresses_flat),
        .memory_global_request_store_data_flat(memory_global_request_store_data_flat),
        .memory_global_response_valid(memory_global_response_valid),
        .memory_global_response_ready(memory_global_response_ready),
        .memory_global_response_workgroup_id(memory_global_response_workgroup_id),
        .memory_global_response_wave_slot(memory_global_response_wave_slot),
        .memory_global_response_epoch(memory_global_response_epoch),
        .memory_global_response_transaction_tag(memory_global_response_transaction_tag),
        .memory_global_response_write(memory_global_response_write),
        .memory_global_response_lane_mask(memory_global_response_lane_mask),
        .memory_global_response_lane_data_flat(memory_global_response_lane_data_flat),
        .memory_global_response_fault_code(memory_global_response_fault_code),
        .memory_global_response_fault_lane(memory_global_response_fault_lane),
        .allocation_active_bitmap(allocation_active_bitmap),
        .workgroup_active_mask(workgroup_active_mask),
        .resident_wave_count(resident_wave_count),
        .shared_local_bytes_used(shared_local_bytes_used)
    );

    task automatic build_packet(
        input logic [63:0] token,
        input integer waves,
        output logic [PACKET_BYTES*8-1:0] packet,
        output integer byte_count);
        integer byte_index;
        integer wave_index;
        integer record_start;
        begin
            packet = '0;
            byte_count = 44 + waves * 8;
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
            packet[28*8 +: 8] = waves;
            packet[30*8 +: 8] = 8'd1;
            packet[32*8 +: 8] = 8'd64;
            for (wave_index = 0; wave_index < waves; wave_index = wave_index + 1) begin
                record_start = 44 + wave_index * 8;
                for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                    packet[(record_start+byte_index)*8 +: 8] = 8'hff;
                packet[(record_start+4)*8 +: 8] = 8'd16;
            end
        end
    endtask

    task automatic register_queue(input logic [5:0] context_id,
                                 input logic [63:0] expected_incarnation);
        integer guard;
        begin
            @(negedge clk);
            register_context_id = context_id;
            register_process_id = 64'h1000000000000000 | context_id;
            register_address_space_id = 64'h2000000000000000 | context_id;
            register_priority = 3'd4;
            register_valid = 1'b1;
            guard = 0;
            while (!register_ready && guard < 40) begin
                @(negedge clk); #1; guard = guard + 1;
            end
            if (!register_ready) $fatal(1, "queue registration remained blocked");
            @(posedge clk); #1;
            if (!register_result_valid || register_result_status !== 2'd0
                || register_result_context_id !== context_id
                || register_result_incarnation_id !== expected_incarnation)
                $fatal(1, "queue registration result mismatch context=%0d inc=%0d status=%0d",
                    register_result_context_id, register_result_incarnation_id,
                    register_result_status);
            @(negedge clk); register_valid = 1'b0;
        end
    endtask

    task automatic write_packet_bytes(
        input logic [5:0] context_id,
        input logic [PACKET_BYTES*8-1:0] packet,
        input integer start_byte,
        input integer byte_count);
        integer byte_index;
        integer guard;
        begin
            for (byte_index = start_byte; byte_index < start_byte + byte_count;
                 byte_index = byte_index + 1) begin
                @(negedge clk);
                byte_context_id = context_id;
                byte_data = packet[byte_index*8 +: 8];
                byte_valid = 1'b1;
                #1;
                guard = 0;
                while (!byte_ready && guard < 100) begin
                    @(negedge clk); #1; guard = guard + 1;
                end
                if (!byte_ready)
                    $fatal(1, "queue byte ingress stayed blocked context=%0d byte=%0d",
                        context_id, byte_index);
                @(posedge clk); #1;
                byte_valid = 1'b0;
            end
        end
    endtask

    task automatic request_queue_reset(input logic [5:0] context_id);
        begin
            @(negedge clk); queue_reset_context_id = context_id;
            queue_reset_valid = 1'b1; #1;
            if (!queue_reset_ready)
                $fatal(1, "registered queue context did not accept reset context=%0d", context_id);
            @(posedge clk); #1;
            @(negedge clk); queue_reset_valid = 1'b0;
            if (!queue_reset_pending_mask[context_id])
                $fatal(1, "accepted queue reset did not publish its cancel mask");
        end
    endtask

    task automatic wait_command_completion(
        input logic [5:0] context_id,
        input logic [WG_WIDTH-1:0] workgroup_id,
        input logic [63:0] token,
        input logic [63:0] position,
        input logic [63:0] incarnation,
        input logic [2:0] status);
        integer guard;
        begin
            guard = 0;
            while (!command_completion_valid && guard < 300) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            if (!command_completion_valid
                || command_completion_queue_context_id !== context_id
                || command_completion_process_id !== (64'h1000000000000000 | context_id)
                || command_completion_address_space_id !== (64'h2000000000000000 | context_id)
                || command_completion_workgroup_id !== workgroup_id
                || command_completion_submission_id !== token
                || command_completion_packet_byte_position !== position
                || command_completion_queue_incarnation_id !== incarnation
                || command_completion_status !== status
                || command_completion_failure !== '0)
                $fatal(1, "final command completion mismatch valid=%b ctx=%0d wg=%h token=%h pos=%0d inc=%0d status=%0d failure=%0d expected ctx=%0d wg=%h token=%h pos=%0d inc=%0d status=%0d",
                    command_completion_valid, command_completion_queue_context_id,
                    command_completion_workgroup_id, command_completion_submission_id,
                    command_completion_packet_byte_position,
                    command_completion_queue_incarnation_id, command_completion_status,
                    command_completion_failure, context_id, workgroup_id, token, position,
                    incarnation, status);
            repeat (2) begin
                @(posedge clk); #1;
                if (!command_completion_valid
                    || command_completion_queue_context_id !== context_id
                    || command_completion_workgroup_id !== workgroup_id
                    || command_completion_submission_id !== token
                    || command_completion_packet_byte_position !== position
                    || command_completion_queue_incarnation_id !== incarnation
                    || command_completion_status !== status)
                    $fatal(1, "final command completion changed under backpressure");
            end
            if (lifecycle_drained_mask[context_id])
                $fatal(1, "queue drained while its final command completion was unacknowledged");
        end
    endtask

    task automatic acknowledge_command_completion;
        begin
            @(negedge clk); command_completion_ready = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); command_completion_ready = 1'b0;
        end
    endtask

    task automatic wait_queue_reset_completion(
        input logic [5:0] context_id,
        input logic [63:0] incarnation,
        input logic [63:0] discard_start,
        input logic [63:0] discard_end);
        integer guard;
        begin
            guard = 0;
            while (!queue_reset_complete_valid && guard < 300) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            if (!queue_reset_complete_valid
                || queue_reset_complete_context_id !== context_id
                || queue_reset_complete_incarnation_id !== incarnation
                || queue_reset_discard_start_position !== discard_start
                || queue_reset_discard_end_position !== discard_end
                || !registered_context_mask[context_id]
                || !queue_reset_pending_mask[context_id])
                $fatal(1, "queue reset response mismatch valid=%b ctx=%0d inc=%0d range=%0d..%0d registered=%b pending=%b",
                    queue_reset_complete_valid, queue_reset_complete_context_id,
                    queue_reset_complete_incarnation_id,
                    queue_reset_discard_start_position, queue_reset_discard_end_position,
                    registered_context_mask[context_id], queue_reset_pending_mask[context_id]);
            repeat (2) begin
                @(posedge clk); #1;
                if (!queue_reset_complete_valid
                    || queue_reset_complete_context_id !== context_id
                    || queue_reset_complete_incarnation_id !== incarnation
                    || queue_reset_discard_start_position !== discard_start
                    || queue_reset_discard_end_position !== discard_end)
                    $fatal(1, "queue reset response changed under backpressure");
            end
        end
    endtask

    task automatic acknowledge_queue_reset;
        begin
            @(negedge clk); queue_reset_complete_ready = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); queue_reset_complete_ready = 1'b0;
        end
    endtask

    task automatic wait_resident_count(input integer expected_count);
        integer guard;
        begin
            guard = 0;
            while (resident_wave_count !== expected_count[WAVE_WIDTH-1:0]
                && guard < 300) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            if (resident_wave_count !== expected_count[WAVE_WIDTH-1:0])
                $fatal(1, "frontend resident wave count mismatch expected=%0d actual=%0d pending=%0d inflight=%b",
                    expected_count, resident_wave_count, pending_count, dispatcher.inflight_q);
        end
    endtask

    task automatic terminate_wave(input logic [0:0] wave_slot);
        begin
            @(negedge clk); terminate_wave_slot = wave_slot; terminate_valid = 1'b1; #1;
            if (!terminate_ready || !terminate_accepted)
                $fatal(1, "frontend did not accept wave termination slot=%0d", wave_slot);
            @(posedge clk); #1;
            @(negedge clk); terminate_valid = 1'b0;
        end
    endtask

    task automatic wait_dispatch_handshake;
        integer guard;
        begin
            guard = 0;
            while (!(dispatch_valid && dispatch_ready) && guard < 300) begin
                @(negedge clk); #1; guard = guard + 1;
            end
            if (!(dispatch_valid && dispatch_ready))
                $fatal(1, "scheduler did not present an admission to the real frontend");
            @(posedge clk); #1;
            if (compute_frontend.txn_state_q == 0 || !dispatcher.inflight_q)
                $fatal(1, "dispatch handshake did not enter multi-cycle authoritative admission");
        end
    endtask

    task automatic issue_global_load_and_capture_request(
        input logic [SLOT_WIDTH-1:0] slot_id,
        input logic [7:0] destination,
        input logic [PC_WIDTH-1:0] byte_address);
        integer guard;
        begin
            @(negedge clk);
            memory_issue_valid[slot_id] = 1'b1;
            memory_issue_global[slot_id] = 1'b1;
            memory_issue_write[slot_id] = 1'b0;
            memory_issue_destination_flat[(slot_id*8)+:8] = destination;
            memory_issue_lane_mask_flat[(slot_id*32)+:32] = 32'd1;
            memory_issue_byte_addresses_flat[(slot_id*32*PC_WIDTH)+:PC_WIDTH]
                = byte_address;
            #1;
            if (!memory_issue_ready[slot_id] || !memory_issue_accepted[slot_id])
                $fatal(1, "resident command did not accept the integrated global load");
            @(posedge clk); #1;
            @(negedge clk);
            memory_issue_valid[slot_id] = 1'b0;
            memory_issue_global[slot_id] = 1'b0;

            guard = 0;
            while (!memory_global_request_valid && guard < 100) begin
                @(negedge clk); #1; guard = guard + 1;
            end
            if (!memory_global_request_valid || memory_global_request_ready
                || memory_global_request_write
                || memory_global_request_lane_mask !== 32'd1
                || memory_global_request_byte_addresses_flat[0+:PC_WIDTH] !== byte_address)
                $fatal(1, "integrated global LSU request was missing or changed after issue acceptance");
            held_memory_workgroup_id = memory_global_request_workgroup_id;
            held_memory_wave_slot = memory_global_request_wave_slot;
            held_memory_epoch = memory_global_request_epoch;
            held_memory_transaction_tag = memory_global_request_transaction_tag;
            held_memory_lane_mask = memory_global_request_lane_mask;

            @(negedge clk); memory_global_request_ready = 1'b1; #1;
            if (!memory_global_request_valid)
                $fatal(1, "integrated global request withdrew before downstream acceptance");
            @(posedge clk); #1;
            @(negedge clk); memory_global_request_ready = 1'b0;
            if (!memory_waiting_mask[slot_id]
                || !memory_load_destination_pending_mask[slot_id])
                $fatal(1, "accepted global load did not retain its per-wave wait and destination state");
        end
    endtask

    task automatic return_response_after_wave_abort;
        begin
            @(negedge clk);
            memory_global_response_workgroup_id = held_memory_workgroup_id;
            memory_global_response_wave_slot = held_memory_wave_slot;
            memory_global_response_epoch = held_memory_epoch;
            memory_global_response_transaction_tag = held_memory_transaction_tag;
            memory_global_response_write = 1'b0;
            memory_global_response_lane_mask = held_memory_lane_mask;
            memory_global_response_lane_data_flat = '0;
            memory_global_response_lane_data_flat[0+:32] = 32'hbad0bad0;
            memory_global_response_fault_code = '0;
            memory_global_response_fault_lane = '0;
            memory_global_response_valid = 1'b1; #1;
            if (!memory_global_response_ready)
                $fatal(1, "killed-wave response was not accepted for stale-response retirement");
            @(posedge clk); #1;
            @(negedge clk); memory_global_response_valid = 1'b0;
        end
    endtask

    initial begin : run_test
        logic [PACKET_BYTES*8-1:0] packet;
        integer byte_count;
        integer guard;

        repeat (3) @(posedge clk);
        @(negedge clk); reset_n = 1'b1;
        register_queue(6'd0, 64'd1);

        // Admission is intermediate: only final-wave resource release completes the command.
        build_packet(64'd101, 1, packet, byte_count);
        write_packet_bytes(6'd0, packet, 0, byte_count);
        wait_resident_count(1);
        if (command_completion_valid || tracked_count != 1
            || workgroup_active_mask == '0 || shared_local_bytes_used != 64)
            $fatal(1, "admission was reported as final completion or lost resident resources");
        terminate_wave(1'b0);
        wait_command_completion(6'd0, 16'h8000, 64'd101, 64'd0, 64'd1, 3'd0);
        acknowledge_command_completion();
        if (!lifecycle_drained_mask[0] || resident_wave_count != 0
            || allocation_active_bitmap != '0 || shared_local_bytes_used != 0)
            $fatal(1, "successful completion did not drain command and CU resources");

        // Queue reset discards unread bytes, reports their old incarnation/range,
        // and does not permit context reuse until the reset response is consumed.
        build_packet(64'd102, 1, packet, byte_count);
        write_packet_bytes(6'd0, packet, 0, 8);
        request_queue_reset(6'd0);
        if (byte_ready || !queue_reset_pending_mask[0])
            $fatal(1, "queue reset did not block further ring ingress");
        wait_queue_reset_completion(6'd0, 64'd1, 64'd52, 64'd60);
        acknowledge_queue_reset();
        if (registered_context_mask[0] || queue_reset_pending_mask[0])
            $fatal(1, "queue reset did not unregister after response acknowledgement");
        register_queue(6'd0, 64'd2);

        // Begin parsing a complete packet, then reset the queue while the
        // parser owns the frame. The descriptor reaches CUDS and is cancelled
        // without tile service; final cancellation waits for its result handshake.
        tile_eligible = 1'b0;
        build_packet(64'd201, 1, packet, byte_count);
        write_packet_bytes(6'd0, packet, 0, byte_count);
        @(posedge clk); #1;
        if (queue_frontend.feeder_state_q != 2'd1)
            $fatal(1, "reset-during-parse fixture did not start an owned frame transaction");
        request_queue_reset(6'd0);
        wait_command_completion(6'd0, 16'h8001, 64'd201, 64'd0, 64'd2, 3'd4);
        if (resident_wave_count != 0 || queue_reset_complete_valid)
            $fatal(1, "pending cancellation admitted work or completed reset before command drain");
        acknowledge_command_completion();
        wait_queue_reset_completion(6'd0, 64'd2, 64'd52, 64'd52);
        acknowledge_queue_reset();
        if (registered_context_mask[0])
            $fatal(1, "parser-cancelled queue context remained registered");

        // Reset after the scheduler has handed a descriptor to the frontend.
        // Admission is allowed to resolve, then the resident group is aborted
        // and final cancellation waits for authoritative resource retirement.
        register_queue(6'd0, 64'd3);
        tile_eligible = 1'b1;
        build_packet(64'd301, 1, packet, byte_count);
        write_packet_bytes(6'd0, packet, 0, byte_count);
        wait_dispatch_handshake();
        request_queue_reset(6'd0);
        wait_command_completion(6'd0, 16'h8002, 64'd301, 64'd0, 64'd3, 3'd4);
        if (resident_wave_count != 0 || allocation_active_bitmap != '0
            || shared_local_bytes_used != 0 || workgroup_active_mask != '0)
            $fatal(1, "resident queue cancellation completed before complete resource release");
        if (queue_reset_complete_valid)
            $fatal(1, "queue reset completed while its command cancellation was unacknowledged");
        acknowledge_command_completion();
        wait_queue_reset_completion(6'd0, 64'd3, 64'd52, 64'd52);
        acknowledge_queue_reset();

        // Two independent resident workgroups in one context both abort and
        // retire before queue reuse; completion backpressure retains each identity.
        register_queue(6'd1, 64'd4);
        build_packet(64'd401, 1, packet, byte_count);
        write_packet_bytes(6'd1, packet, 0, byte_count);
        build_packet(64'd402, 1, packet, byte_count);
        write_packet_bytes(6'd1, packet, 0, byte_count);
        wait_resident_count(2);
        if (tracked_count != 2 || shared_local_bytes_used != 128)
            $fatal(1, "multiple workgroups were not independently resident before reset");
        request_queue_reset(6'd1);
        wait_command_completion(6'd1, 16'h8003, 64'd401, 64'd0, 64'd4, 3'd4);
        acknowledge_command_completion();
        wait_command_completion(6'd1, 16'h8004, 64'd402, 64'd52, 64'd4, 3'd4);
        if (resident_wave_count != 0 || allocation_active_bitmap != '0
            || shared_local_bytes_used != 0)
            $fatal(1, "multi-workgroup reset left CU-local state allocated");
        acknowledge_command_completion();
        wait_queue_reset_completion(6'd1, 64'd4, 64'd104, 64'd104);
        acknowledge_queue_reset();

        // A queue reset cannot complete while a global load accepted by the
        // real LSU is outstanding. The killed wave remains allocated until
        // its tagged response drains, and that response must not write back.
        register_queue(6'd2, 64'd5);
        build_packet(64'd501, 1, packet, byte_count);
        write_packet_bytes(6'd2, packet, 0, byte_count);
        wait_resident_count(1);
        if (!allocation_active_bitmap[0] || tracked_count != 1)
            $fatal(1, "global-memory cancellation setup did not retain one admitted wave");
        issue_global_load_and_capture_request(1'b0, 8'd5, 57'h12340);
        request_queue_reset(6'd2);
        repeat (5) begin
            @(posedge clk); #1;
            if (command_completion_valid || queue_reset_complete_valid
                || !allocation_active_bitmap[0] || resident_wave_count != 1
                || shared_local_bytes_used != 64 || workgroup_retire_valid)
                $fatal(1, "command or workgroup retired before its outstanding global response drained");
        end
        return_response_after_wave_abort();
        wait_command_completion(6'd2, 16'h8005, 64'd501, 64'd0, 64'd5, 3'd4);
        if (resident_wave_count != 0 || allocation_active_bitmap != '0
            || shared_local_bytes_used != 0 || workgroup_retire_valid)
            $fatal(1, "global response drain did not precede cancelled command resource release");
        acknowledge_command_completion();
        wait_queue_reset_completion(6'd2, 64'd5, 64'd52, 64'd52);
        acknowledge_queue_reset();

        // A device reset clears buffered ring/parser data, resident CU state,
        // and command-lifecycle ownership together, then permits fresh use.
        register_queue(6'd2, 64'd6);
        build_packet(64'd601, 1, packet, byte_count);
        write_packet_bytes(6'd2, packet, 0, byte_count);
        build_packet(64'd602, 1, packet, byte_count);
        write_packet_bytes(6'd2, packet, 0, byte_count);
        wait_resident_count(2);
        build_packet(64'd603, 1, packet, byte_count);
        write_packet_bytes(6'd2, packet, 0, 8);
        @(posedge clk); #1;
        if (tracked_count != 2 || shared_local_bytes_used != 128
            || (unread_bytes_flat[(2*COUNT_WIDTH)+:COUNT_WIDTH] == 0
                && queue_frontend.feeder_state_q == 0))
            $fatal(1, "whole-device reset setup did not contain lifecycle, parser, ring, and resident state");
        @(negedge clk); reset_n = 1'b0;
        repeat (3) @(posedge clk);
        #1;
        if (registered_context_mask != '0 || queue_reset_pending_mask != '0
            || unread_bytes_flat != '0 || producer_position_flat != '0
            || consumer_position_flat != '0 || pending_count != 0 || tracked_count != 0
            || lifecycle_drained_mask !== 64'hffffffffffffffff
            || resident_wave_count != 0 || allocation_active_bitmap != '0
            || shared_local_bytes_used != 0 || command_completion_valid
            || queue_reset_complete_valid || workgroup_retire_valid
            || dispatch_valid || dispatcher.inflight_q || queue_frontend.feeder_state_q != 0)
            $fatal(1, "whole-device reset left ring, parser, dispatch, lifecycle, or resident state behind");
        @(negedge clk); reset_n = 1'b1;
        register_queue(6'd2, 64'd1);
        request_queue_reset(6'd2);
        wait_queue_reset_completion(6'd2, 64'd1, 64'd0, 64'd0);
        acknowledge_queue_reset();

        guard = 0;
        while (tracked_count != 0 && guard < 20) begin
            @(posedge clk); #1; guard = guard + 1;
        end
        if (tracked_count != 0 || lifecycle_drained_mask !== 64'hffffffffffffffff
            || registered_context_mask != '0 || queue_reset_pending_mask != '0
            || pending_count != 0 || resident_wave_count != 0)
            $fatal(1, "queue-to-retirement integration leaked command or resource state");

        $display("[pass] queue/parser/CUDS/lifecycle/compute integration covered retirement, parser and pending reset, in-flight admission abort, multi-workgroup drain, global-memory quiescence, device reset, response backpressure, and incarnation reuse.");
        $finish;
    end

    initial begin
        #5_000_000;
        $fatal(1, "queue-to-retirement integration test timed out");
    end
endmodule
