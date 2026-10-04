`timescale 1ns/1ps
module cgx1_compute_workgroup_dispatch_integration_tb;
    localparam integer SLOTS = 2;
    localparam integer WG_WIDTH = 8;
    localparam integer PC_WIDTH = 57;
    localparam integer WAVE_WIDTH = 2;

    logic clk = 0;
    logic reset_n = 0;
    always #5 clk = ~clk;

    logic tile_eligible = 1;
    logic [63:0] faulted_queue_mask = 0;
    logic submit_valid = 0, submit_ready;
    logic [5:0] submit_queue_context_id = 3;
    logic [63:0] submit_process_id = 64'h1003;
    logic [63:0] submit_address_space_id = 64'h2003;
    logic [2:0] submit_priority = 4;
    logic submit_graphics = 0;
    logic [WG_WIDTH-1:0] submit_workgroup_id = 0;
    logic [WAVE_WIDTH-1:0] submit_wave_count = 1;
    logic [PC_WIDTH-1:0] submit_start_pc = 57'h1000;
    logic [(SLOTS*32)-1:0] submit_initial_live_lane_mask_flat = '1;
    logic [(SLOTS*9)-1:0] submit_vgpr_register_counts_flat = '0;
    logic [15:0] submit_scalar_state_units_per_wave = 1;
    logic [31:0] submit_shared_local_bytes = 0;
    logic [31:0] submit_other_workgroup_state_units = 0;
    logic [63:0] submit_submission_id = 0;
    logic [63:0] submit_packet_byte_position = 0;
    logic [63:0] submit_queue_incarnation_id = 64'habc0000000000003;

    logic dispatch_valid, dispatch_ready;
    logic [5:0] dispatch_queue_context_id;
    logic [63:0] dispatch_process_id, dispatch_address_space_id;
    logic [2:0] dispatch_priority;
    logic [WG_WIDTH-1:0] dispatch_workgroup_id;
    logic [WAVE_WIDTH-1:0] dispatch_wave_count;
    logic [PC_WIDTH-1:0] dispatch_start_pc;
    logic [(SLOTS*32)-1:0] dispatch_initial_live_lane_mask_flat;
    logic [(SLOTS*9)-1:0] dispatch_vgpr_register_counts_flat;
    logic [15:0] dispatch_scalar_state_units_per_wave;
    logic [31:0] dispatch_shared_local_bytes;
    logic [31:0] dispatch_other_workgroup_state_units;
    logic dispatch_result_valid, dispatch_accepted;
    logic [4:0] dispatch_failure;
    logic completion_valid;
    logic [5:0] completion_queue_context_id;
    logic [63:0] completion_process_id, completion_address_space_id;
    logic [WG_WIDTH-1:0] completion_workgroup_id;
    logic [2:0] completion_status;
    logic [4:0] completion_failure;
    logic [63:0] dispatch_submission_id, dispatch_packet_byte_position;
    logic [63:0] dispatch_queue_incarnation_id;
    logic [63:0] completion_submission_id, completion_packet_byte_position;
    logic [63:0] completion_queue_incarnation_id;
    logic [2:0] pending_count;

    logic terminate_wave_valid = 0;
    logic [0:0] terminate_wave_slot = 0;
    logic terminate_wave_ready, terminate_wave_accepted;
    logic [SLOTS-1:0] allocation_active_bitmap;
    logic [1:0] workgroup_active_mask;
    logic [WAVE_WIDTH-1:0] resident_wave_count;
    logic [31:0] shared_local_bytes_used;
    logic workgroup_retire_valid;
    logic workgroup_retire_ready = 1'b0;
    logic [WG_WIDTH-1:0] workgroup_retire_id;

    cgx1_compute_workgroup_dispatch_scheduler #(
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .MAX_PENDING_ENTRIES(4),
        .WORKGROUP_ID_WIDTH(WG_WIDTH),
        .VIRTUAL_ADDRESS_WIDTH(PC_WIDTH),
        .AGING_INTERVAL_CYCLES(4)
    ) scheduler (
        .clk(clk), .reset_n(reset_n), .tile_eligible(tile_eligible),
        .faulted_queue_mask(faulted_queue_mask),
        .cancelled_queue_mask(64'b0), .lifecycle_ready(1'b1),
        .submit_valid(submit_valid), .submit_ready(submit_ready),
        .submit_queue_context_id(submit_queue_context_id),
        .submit_process_id(submit_process_id),
        .submit_address_space_id(submit_address_space_id),
        .submit_priority(submit_priority), .submit_graphics(submit_graphics),
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
        .dispatch_result_valid(dispatch_result_valid), .dispatch_accepted(dispatch_accepted),
        .dispatch_failure(dispatch_failure), .completion_valid(completion_valid),
        .completion_ready(1'b1), .completion_queue_context_id(completion_queue_context_id),
        .completion_process_id(completion_process_id),
        .completion_address_space_id(completion_address_space_id),
        .completion_workgroup_id(completion_workgroup_id),
        .completion_submission_id(completion_submission_id),
        .completion_packet_byte_position(completion_packet_byte_position),
        .completion_queue_incarnation_id(completion_queue_incarnation_id),
        .completion_status(completion_status), .completion_failure(completion_failure),
        .pending_count(pending_count)
    );

    cgx1_compute_workgroup_execution_frontend #(
        .PHYSICAL_ROWS(16), .RESIDENT_WAVE_SLOTS(SLOTS),
        .MAX_WORKGROUP_CONTEXTS(2), .SCALAR_PREDICATE_STATE_UNITS(8),
        .SHARED_LOCAL_MEMORY_BYTES(1024), .OTHER_WORKGROUP_STATE_UNITS(8),
        .WORKGROUP_ID_WIDTH(WG_WIDTH), .VIRTUAL_ADDRESS_WIDTH(PC_WIDTH)
    ) frontend (
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
        .terminate_wave_valid(terminate_wave_valid),
        .terminate_wave_slot(terminate_wave_slot), .terminate_wave_reason(2'b00),
        .terminate_wave_ready(terminate_wave_ready),
        .terminate_wave_accepted(terminate_wave_accepted),
        .workgroup_abort_valid(1'b0), .workgroup_abort_id('0),
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
        .memory_epoch(32'b0), .memory_issue_valid('0), .memory_issue_global('0),
        .memory_issue_write('0), .memory_issue_destination_flat('0),
        .memory_issue_lane_mask_flat('0), .memory_issue_byte_addresses_flat('0),
        .memory_issue_store_data_flat('0), .memory_completion_ready(1'b1),
        .memory_fault_ready(1'b1), .memory_global_request_ready(1'b1),
        .memory_global_response_valid(1'b0), .memory_global_response_workgroup_id('0),
        .memory_global_response_wave_slot('0), .memory_global_response_epoch('0),
        .memory_global_response_transaction_tag('0), .memory_global_response_write(1'b0),
        .memory_global_response_lane_mask('0), .memory_global_response_lane_data_flat('0),
        .memory_global_response_fault_code('0), .memory_global_response_fault_lane('0),
        .allocation_active_bitmap(allocation_active_bitmap),
        .workgroup_active_mask(workgroup_active_mask),
        .resident_wave_count(resident_wave_count),
        .shared_local_bytes_used(shared_local_bytes_used)
    );

    task automatic submit_workgroup(
        input logic [WG_WIDTH-1:0] id,
        input logic [WAVE_WIDTH-1:0] waves,
        input logic [31:0] shared_bytes);
        begin
            @(negedge clk);
            submit_workgroup_id = id;
            submit_submission_id = 64'h7000000000000000 | id;
            submit_packet_byte_position = 64'h8000000000000000 | id;
            submit_wave_count = waves;
            submit_start_pc = 57'h1000;
            submit_shared_local_bytes = shared_bytes;
            submit_vgpr_register_counts_flat = '0;
            submit_vgpr_register_counts_flat[0+:9] = 9'd16;
            submit_vgpr_register_counts_flat[9+:9] = waves > 1 ? 9'd16 : 9'd0;
            submit_valid = 1;
            if (!submit_ready) $fatal(1, "dispatcher ingress was not ready");
            @(posedge clk); #1;
            @(negedge clk); submit_valid = 0;
        end
    endtask

    task automatic wait_completion(
        input logic [WG_WIDTH-1:0] id,
        input logic [1:0] expected_status,
        input logic [4:0] expected_failure);
        integer guard;
        begin
            guard = 0;
            while (!completion_valid && guard < 100) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            if (!completion_valid || completion_workgroup_id !== id
                || completion_status !== expected_status
                || completion_failure !== expected_failure
                || completion_queue_context_id !== 3
                || completion_process_id !== 64'h1003
                || completion_address_space_id !== 64'h2003)
                $fatal(1, "dispatch completion mismatch for WG %0d: valid=%0b status=%0d failure=%0d",
                    id, completion_valid, completion_status, completion_failure);
            if (completion_submission_id !== (64'h7000000000000000 | id)
                || completion_packet_byte_position !== (64'h8000000000000000 | id)
                || completion_queue_incarnation_id !== 64'habc0000000000003)
                $fatal(1, "dispatch completion lost command packet correlation for WG %0d", id);
        end
    endtask

    initial begin : run_test
        integer step;
        reset_n = 0;
        repeat (3) @(posedge clk);
        @(negedge clk); reset_n = 1;

        submit_workgroup(8'd1, 1, 32'd64);
        wait_completion(8'd1, 2'd0, 5'd0);
        if (resident_wave_count != 1 || shared_local_bytes_used != 64
            || workgroup_active_mask == 0 || allocation_active_bitmap == 0)
            $fatal(1, "dispatch did not reach authoritative complete-workgroup residency");
        @(posedge clk); #1;

        // Existing workgroup ID is a permanent admission failure from the real owner.
        submit_workgroup(8'd1, 1, 32'd64);
        wait_completion(8'd1, 2'd1, 5'd3);
        if (resident_wave_count != 1 || shared_local_bytes_used != 64)
            $fatal(1, "duplicate dispatch disturbed the resident workgroup");
        @(posedge clk); #1;

        // A complete two-wave demand waits while only one slot is free, then retries after release.
        submit_workgroup(8'd2, 2, 32'd128);
        repeat (4) begin
            @(posedge clk); #1;
            if (pending_count != 1 || completion_valid)
                $fatal(1, "resource-busy dispatch was not retained for retry");
        end

        @(negedge clk); terminate_wave_valid = 1; terminate_wave_slot = 0;
        #1;
        if (!terminate_wave_accepted)
            $fatal(1, "resident workgroup wave did not terminate: slot=%0d ready=%b live=%b resident=%b alloc=%b workgroup_ids=%h",
                terminate_wave_slot, terminate_wave_ready, frontend.live_wave_mask,
                frontend.resident_wave_mask, allocation_active_bitmap,
                frontend.barrier_slot_workgroup_id_flat);
        @(posedge clk); #1;
        @(negedge clk); terminate_wave_valid = 0;
        step = 0;
        while ((shared_local_bytes_used != 0 || !workgroup_retire_valid) && step < 40) begin
            @(posedge clk); #1; step = step + 1;
        end
        if (shared_local_bytes_used != 0 || !workgroup_retire_valid
            || workgroup_retire_id !== 8'd1 || allocation_active_bitmap != '0)
            $fatal(1, "quiescent release did not free resources and report workgroup retirement");

        repeat (2) begin
            @(posedge clk); #1;
            if (!workgroup_retire_valid || workgroup_retire_id !== 8'd1)
                $fatal(1, "integrated retirement event was not stable under backpressure");
        end
        @(negedge clk); workgroup_retire_ready = 1'b1;
        @(posedge clk); #1;
        if (workgroup_retire_valid)
            $fatal(1, "integrated retirement event remained valid after acknowledgement");

        wait_completion(8'd2, 2'd0, 5'd0);
        if (resident_wave_count != 2 || shared_local_bytes_used != 128
            || !workgroup_active_mask[0] && !workgroup_active_mask[1])
            $fatal(1, "retried dispatch did not admit all waves and its owned region");

        $display("CGX1 CU dispatch scheduler/frontend integration checks passed.");
        $finish;
    end
endmodule
