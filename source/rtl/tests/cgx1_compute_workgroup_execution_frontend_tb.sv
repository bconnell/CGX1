// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_compute_workgroup_execution_frontend_tb;
    localparam integer ROWS = 32;
    localparam integer SLOTS = 4;
    localparam integer GROUPS = 6;
    localparam integer ROW_WIDTH = 5;
    localparam integer SLOT_WIDTH = 2;
    localparam integer COUNT_WIDTH = 3;
    localparam integer VA_WIDTH = 57;
    localparam integer WAVE_ADDRESS_WIDTH = 32 * VA_WIDTH;
    localparam logic [4:0] FAIL_SHARED_MEMORY_FRAGMENTED = 5'd16;
    logic clk = 0, reset_n = 0;
    logic dispatch_valid, dispatch_ready;
    logic [7:0] dispatch_workgroup_id;
    logic [COUNT_WIDTH-1:0] dispatch_wave_count;
    logic [(SLOTS*9)-1:0] dispatch_vgpr_register_counts_flat;
    logic [VA_WIDTH-1:0] dispatch_start_pc = '0;
    logic [(SLOTS*32)-1:0] dispatch_initial_live_lane_mask_flat = '1;
    logic [15:0] dispatch_scalar_state_units_per_wave;
    logic [31:0] dispatch_other_workgroup_state_units;
    logic [31:0] dispatch_shared_local_bytes;
    logic dispatch_result_valid, dispatch_accepted;
    logic [4:0] dispatch_failure;
    logic [(SLOTS*VA_WIDTH)-1:0] decoded_sequential_pc_flat = '0;
    logic control_event_valid = 1'b0;
    logic [SLOT_WIDTH-1:0] control_event_wave_slot = '0;
    logic [2:0] control_event_kind = '0;
    logic [VA_WIDTH-1:0] control_event_sequential_pc = '0;
    logic [VA_WIDTH-1:0] control_event_target_pc = '0;
    logic [VA_WIDTH-1:0] control_event_fallthrough_pc = '0;
    logic [VA_WIDTH-1:0] control_event_join_pc = '0;
    logic [VA_WIDTH-1:0] control_event_return_pc = '0;
    logic [VA_WIDTH-1:0] control_event_loop_test_pc = '0;
    logic [VA_WIDTH-1:0] control_event_loop_body_pc = '0;
    logic [VA_WIDTH-1:0] control_event_loop_exit_pc = '0;
    logic [31:0] control_event_taken_mask = '0;
    logic [31:0] control_event_continue_mask = '0;
    logic control_event_ready, control_event_accepted;
    logic [(SLOTS*VA_WIDTH)-1:0] control_pc_flat;
    logic [(SLOTS*32)-1:0] control_live_lane_mask_flat, control_active_lane_mask_flat;
    logic [SLOTS-1:0] control_reconverged_mask;
    logic control_terminal_valid;
    logic [SLOT_WIDTH-1:0] control_terminal_wave_slot;
    logic [3:0] control_terminal_fault_code;
    logic barrier_arrive_valid;
    logic [7:0] barrier_arrive_workgroup_id;
    logic [SLOTS-1:0] barrier_arrive_local_wave_mask;
    logic barrier_arrive_ready, barrier_arrive_accepted, barrier_release_valid;
    logic [7:0] barrier_release_workgroup_id;
    logic [31:0] barrier_release_generation;
    logic [SLOTS-1:0] barrier_release_wave_mask;
    logic terminate_wave_valid;
    logic [SLOT_WIDTH-1:0] terminate_wave_slot;
    logic [1:0] terminate_wave_reason;
    logic terminate_wave_ready, terminate_wave_accepted;
    logic workgroup_abort_valid;
    logic [7:0] workgroup_abort_id;
    logic workgroup_abort_ready, workgroup_abort_accepted;
    logic workgroup_retire_valid;
    logic workgroup_retire_ready = 1'b1;
    logic [7:0] workgroup_retire_id;
    logic restore_valid;
    logic [SLOT_WIDTH-1:0] restore_wave_slot;
    logic [7:0] restore_register;
    logic [1023:0] restore_data;
    logic restore_ready;
    logic [SLOTS-1:0] matrix_request_valid, matrix_request_full_wave_active;
    logic [(SLOTS*8)-1:0] matrix_request_d_base, matrix_request_a_base, matrix_request_b_base;
    logic [SLOTS-1:0] matrix_request_ready, matrix_request_accepted;
    logic matrix_illegal_issue;
    logic [SLOT_WIDTH-1:0] matrix_illegal_wave_slot;
    logic [SLOTS-1:0] vector_request_valid;
    logic [(SLOTS*4)-1:0] vector_request_opcode;
    logic [(SLOTS*8)-1:0] vector_request_source0, vector_request_source1, vector_request_destination;
    logic [(SLOTS*32)-1:0] vector_request_lane_mask;
    logic [SLOTS-1:0] vector_request_accepted;
    logic vector_complete_valid;
    logic [SLOT_WIDTH-1:0] vector_complete_wave_slot;
    logic vector_illegal_opcode, vector_address_fault, vector_uninitialized_fault;
    logic [31:0] memory_epoch;
    logic [SLOTS-1:0] memory_issue_valid, memory_issue_ready, memory_issue_accepted;
    logic [SLOTS-1:0] memory_issue_global, memory_issue_write;
    logic [(SLOTS*8)-1:0] memory_issue_destination_flat;
    logic [(SLOTS*32)-1:0] memory_issue_lane_mask_flat;
    logic [(SLOTS*WAVE_ADDRESS_WIDTH)-1:0] memory_issue_byte_addresses_flat;
    logic [(SLOTS*1024)-1:0] memory_issue_store_data_flat;
    logic [SLOTS-1:0] memory_waiting_mask, memory_load_destination_pending_mask;
    logic memory_completion_ready, memory_completion_valid, memory_completion_write;
    logic [7:0] memory_completion_workgroup_id;
    logic [SLOT_WIDTH-1:0] memory_completion_wave_slot;
    logic [63:0] memory_completion_transaction_tag;
    logic memory_fault_ready, memory_fault_valid;
    logic [7:0] memory_fault_workgroup_id;
    logic [SLOT_WIDTH-1:0] memory_fault_wave_slot;
    logic [63:0] memory_fault_transaction_tag;
    logic [2:0] memory_fault_code;
    logic [5:0] memory_fault_lane;
    logic memory_global_request_valid, memory_global_request_ready;
    logic [7:0] memory_global_request_workgroup_id;
    logic [SLOT_WIDTH-1:0] memory_global_request_wave_slot;
    logic [31:0] memory_global_request_epoch;
    logic [63:0] memory_global_request_transaction_tag;
    logic memory_global_request_write;
    logic [31:0] memory_global_request_lane_mask;
    logic [WAVE_ADDRESS_WIDTH-1:0] memory_global_request_byte_addresses_flat;
    logic [1023:0] memory_global_request_store_data_flat;
    logic memory_global_response_valid, memory_global_response_ready;
    logic [7:0] memory_global_response_workgroup_id;
    logic [SLOT_WIDTH-1:0] memory_global_response_wave_slot;
    logic [31:0] memory_global_response_epoch;
    logic [63:0] memory_global_response_transaction_tag;
    logic memory_global_response_write;
    logic [31:0] memory_global_response_lane_mask;
    logic [1023:0] memory_global_response_lane_data_flat;
    logic [2:0] memory_global_response_fault_code;
    logic [5:0] memory_global_response_fault_lane;
    logic instruction_fetch_enable = 1'b0;
    logic instruction_memory_request_valid, instruction_memory_request_ready;
    logic [7:0] instruction_memory_request_workgroup_id;
    logic [SLOT_WIDTH-1:0] instruction_memory_request_wave_slot;
    logic [31:0] instruction_memory_request_epoch;
    logic [63:0] instruction_memory_request_transaction_tag;
    logic [VA_WIDTH-1:0] instruction_memory_request_pc;
    logic instruction_memory_response_valid, instruction_memory_response_ready;
    logic [7:0] instruction_memory_response_workgroup_id;
    logic [SLOT_WIDTH-1:0] instruction_memory_response_wave_slot;
    logic [31:0] instruction_memory_response_epoch;
    logic [63:0] instruction_memory_response_transaction_tag;
    logic [VA_WIDTH-1:0] instruction_memory_response_pc;
    logic [31:0] instruction_memory_response_word;
    logic [2:0] instruction_memory_response_fault_code;
    logic [SLOTS-1:0] instruction_fetch_unhandled_valid;
    logic [SLOTS-1:0] instruction_fetch_unhandled_ready = '0;
    logic [(SLOTS*4)-1:0] instruction_fetch_unhandled_class_flat;
    logic [(SLOTS*32)-1:0] instruction_fetch_unhandled_word_flat;
    logic [(SLOTS*4)-1:0] instruction_fetch_unhandled_opcode_flat;
    logic [(SLOTS*8)-1:0] instruction_fetch_unhandled_destination_flat;
    logic [(SLOTS*8)-1:0] instruction_fetch_unhandled_source0_flat;
    logic [(SLOTS*8)-1:0] instruction_fetch_unhandled_source1_flat;
    logic [(SLOTS*8)-1:0] instruction_fetch_unhandled_workgroup_id_flat;
    logic [(SLOTS*VA_WIDTH)-1:0] instruction_fetch_unhandled_pc_flat;
    logic [(SLOTS*32)-1:0] instruction_fetch_unhandled_epoch_flat;
    logic [(SLOTS*64)-1:0] instruction_fetch_unhandled_transaction_tag_flat;
    logic [SLOTS-1:0] instruction_fetch_fault_valid_mask;
    logic [SLOTS-1:0] instruction_fetch_fault_ready_mask = '0;
    logic [(SLOTS*8)-1:0] instruction_fetch_fault_workgroup_id_flat;
    logic [(SLOTS*32)-1:0] instruction_fetch_fault_epoch_flat;
    logic [(SLOTS*64)-1:0] instruction_fetch_fault_transaction_tag_flat;
    logic [(SLOTS*VA_WIDTH)-1:0] instruction_fetch_fault_pc_flat;
    logic [(SLOTS*3)-1:0] instruction_fetch_fault_code_flat;
    logic [SLOTS-1:0] allocation_reserved_bitmap, allocation_active_bitmap, allocation_sanitized_bitmap;
    logic [(SLOTS*ROW_WIDTH)-1:0] allocation_row_base_flat;
    logic [(SLOTS*9)-1:0] allocation_register_count_flat;
    logic [SLOTS-1:0] matrix_execution_busy_bitmap, vector_execution_busy_bitmap;
    logic [SLOTS-1:0] resident_wave_mask, live_wave_mask, barrier_waiting_mask;
    logic [SLOTS-1:0] issuable_wave_mask, release_pending_wave_mask;
    logic [GROUPS-1:0] workgroup_active_mask;
    logic [COUNT_WIDTH-1:0] resident_wave_count;
    logic [31:0] scalar_state_units_used, shared_local_bytes_used, other_workgroup_state_units_used;
    integer timeout, iteration, lane, physical_row, bank, register_number, base_row;
    integer map_before;
    logic [63:0] tag0;
    logic [31:0] epoch0;
    logic [63:0] fetch_tag0, fetch_tag1;
    logic [31:0] fetch_epoch0, fetch_epoch1;
    logic [VA_WIDTH-1:0] fetch_pc0, fetch_pc1;
    logic [SLOTS-1:0] active_before, reserved_before;
    logic [(SLOTS*ROW_WIDTH)-1:0] row_base_before;
    logic [(SLOTS*9)-1:0] register_count_before;
    logic [31:0] shared_bytes_before;

    always #5 clk = ~clk;

    cgx1_compute_workgroup_execution_frontend #(
        .PHYSICAL_ROWS(ROWS), .RESIDENT_WAVE_SLOTS(SLOTS),
        .MAX_WORKGROUP_CONTEXTS(GROUPS), .WORKGROUP_ID_WIDTH(8),
        .ROW_WIDTH(ROW_WIDTH), .WAVE_SLOT_WIDTH(SLOT_WIDTH),
        .WAVE_COUNT_WIDTH(COUNT_WIDTH), .ENABLE_INSTRUCTION_FETCH(1)
    ) dut(.*);

    task automatic dispatch(input logic [7:0] id, input logic [COUNT_WIDTH-1:0] waves,
                            input logic [8:0] count0, input logic [8:0] count1,
                            input logic [8:0] count2, input logic [8:0] count3,
                            input logic [4:0] expected_failure);
    begin
        @(negedge clk);
        dispatch_workgroup_id = id;
        dispatch_wave_count = waves;
        dispatch_vgpr_register_counts_flat = '0;
        dispatch_vgpr_register_counts_flat[0+:9] = count0;
        dispatch_vgpr_register_counts_flat[9+:9] = count1;
        dispatch_vgpr_register_counts_flat[18+:9] = count2;
        dispatch_vgpr_register_counts_flat[27+:9] = count3;
        dispatch_scalar_state_units_per_wave = 1;
        dispatch_shared_local_bytes = (expected_failure == 5'd12) ? 4097 : 64;
        dispatch_other_workgroup_state_units = 1;
        dispatch_valid = 1;
        #1;
        if (!dispatch_ready) $fatal(1, "workgroup dispatch frontend was not ready");
        @(posedge clk); #1; @(negedge clk); dispatch_valid = 0;
        timeout = 0;
        while (!dispatch_result_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 2048) $fatal(1, "workgroup admission transaction timed out");
        end
        if (dispatch_failure != expected_failure || dispatch_accepted != (expected_failure == 0))
            $fatal(1, "dispatch %0d result mismatch: accepted=%0b failure=%0d expected=%0d",
                id, dispatch_accepted, dispatch_failure, expected_failure);
        @(negedge clk);
    end
    endtask

    task automatic dispatch_with_resource_demand(
        input logic [7:0] id,
        input logic [COUNT_WIDTH-1:0] waves,
        input logic [8:0] count0,
        input logic [8:0] count1,
        input logic [8:0] count2,
        input logic [8:0] count3,
        input logic [15:0] scalar_units_per_wave,
        input logic [31:0] shared_bytes,
        input logic [31:0] other_units,
        input logic [4:0] expected_failure);
    begin
        @(negedge clk);
        dispatch_workgroup_id = id;
        dispatch_wave_count = waves;
        dispatch_vgpr_register_counts_flat = '0;
        dispatch_vgpr_register_counts_flat[0+:9] = count0;
        dispatch_vgpr_register_counts_flat[9+:9] = count1;
        dispatch_vgpr_register_counts_flat[18+:9] = count2;
        dispatch_vgpr_register_counts_flat[27+:9] = count3;
        dispatch_scalar_state_units_per_wave = scalar_units_per_wave;
        dispatch_shared_local_bytes = shared_bytes;
        dispatch_other_workgroup_state_units = other_units;
        dispatch_valid = 1;
        #1;
        if (!dispatch_ready) $fatal(1, "workgroup dispatch frontend was not ready");
        @(posedge clk); #1; @(negedge clk); dispatch_valid = 0;
        timeout = 0;
        while (!dispatch_result_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 2048) $fatal(1, "workgroup admission transaction timed out");
        end
        if (dispatch_failure != expected_failure || dispatch_accepted != (expected_failure == 0))
            $fatal(1, "resource-demand dispatch %0d mismatch: accepted=%0b failure=%0d expected=%0d",
                id, dispatch_accepted, dispatch_failure, expected_failure);
        @(negedge clk);
    end
    endtask

    task automatic abort_group(input logic [7:0] id);
    begin
        @(negedge clk); workgroup_abort_id = id; workgroup_abort_valid = 1; #1;
        if (!workgroup_abort_ready || !workgroup_abort_accepted)
            $fatal(1, "workgroup abort was not accepted");
        @(posedge clk); #1; @(negedge clk); workgroup_abort_valid = 0;
        timeout = 0;
        while (release_pending_wave_mask != '0 && timeout < 100) begin
            @(posedge clk); #1; timeout = timeout + 1;
        end
        if (timeout >= 100) $fatal(1, "workgroup abort did not release allocator state");
    end
    endtask

    task automatic arrive(input logic [7:0] id, input logic [SLOTS-1:0] local_mask,
                          input logic expected_release, input integer expected_generation);
    begin
        @(negedge clk); barrier_arrive_workgroup_id = id;
        barrier_arrive_local_wave_mask = local_mask; barrier_arrive_valid = 1;
        #1;
        if (!barrier_arrive_ready || !barrier_arrive_accepted)
            $fatal(1, "workgroup barrier arrival was not accepted");
        @(posedge clk); #1;
        if (barrier_release_valid !== expected_release)
            $fatal(1, "workgroup barrier release mismatch id=%0d mask=%b expected=%b actual=%b gen=%0d expected_gen=%0d",
                id, local_mask, expected_release, barrier_release_valid,
                barrier_release_generation, expected_generation);
        if (expected_release && barrier_release_generation != expected_generation)
            $fatal(1, "workgroup barrier generation mismatch");
        @(negedge clk); barrier_arrive_valid = 0;
    end
    endtask

    task automatic issue_vector(input logic [SLOT_WIDTH-1:0] slot,
                                input logic [7:0] source0, input logic [7:0] source1,
                                input logic [7:0] destination);
    begin
        vector_request_opcode[(slot*4)+:4] = 4'd0;
        vector_request_source0[(slot*8)+:8] = source0;
        vector_request_source1[(slot*8)+:8] = source1;
        vector_request_destination[(slot*8)+:8] = destination;
        vector_request_lane_mask[(slot*32)+:32] = 32'hffffffff;
        vector_request_valid[slot] = 1;
        timeout = 0;
        while (!vector_request_accepted[slot]) begin
            @(negedge clk); #1; timeout = timeout + 1;
            if (dut.vector_request_lane_mask_effective[(slot*32)+:32]
                !== (vector_request_lane_mask[(slot*32)+:32]
                    & control_active_lane_mask_flat[(slot*32)+:32]
                    & control_live_lane_mask_flat[(slot*32)+:32]))
                $fatal(1, "vector lane mask did not follow the wave's active and live lanes");
            if (timeout > 100) $fatal(1, "vector request did not issue for slot %0d", slot);
        end
        @(posedge clk); #1; @(negedge clk); vector_request_valid[slot] = 0;
    end
    endtask

    task automatic issue_memory(input integer slot, input logic global_space,
                                input logic write_access, input logic [7:0] destination,
                                input logic [31:0] lane_mask, input logic [VA_WIDTH-1:0] address0,
                                input logic [31:0] value0);
    begin
        @(negedge clk);
        memory_issue_global[slot] = global_space;
        memory_issue_write[slot] = write_access;
        memory_issue_destination_flat[(slot*8)+:8] = destination;
        memory_issue_lane_mask_flat[(slot*32)+:32] = lane_mask;
        memory_issue_byte_addresses_flat[(slot*WAVE_ADDRESS_WIDTH)+:WAVE_ADDRESS_WIDTH] = '0;
        memory_issue_store_data_flat[(slot*1024)+:1024] = '0;
        memory_issue_byte_addresses_flat[(slot*WAVE_ADDRESS_WIDTH)+:VA_WIDTH] = address0;
        memory_issue_store_data_flat[(slot*1024)+:32] = value0;
        memory_issue_valid[slot] = 1'b1; #1;
        if (memory_issue_ready[slot] !== 1'b1 || memory_issue_accepted[slot] !== 1'b1)
            $fatal(1, "integrated LSU did not accept slot %0d", slot);
        @(posedge clk); #1; @(negedge clk); memory_issue_valid[slot] = 1'b0;
    end
    endtask

    task automatic send_control_event(input integer slot, input logic [2:0] kind,
                                      input logic [VA_WIDTH-1:0] sequential_pc,
                                      input logic [VA_WIDTH-1:0] target_pc,
                                      input logic [VA_WIDTH-1:0] fallthrough_pc,
                                      input logic [VA_WIDTH-1:0] join_pc,
                                      input logic [VA_WIDTH-1:0] return_pc,
                                      input logic [VA_WIDTH-1:0] loop_test_pc,
                                      input logic [VA_WIDTH-1:0] loop_body_pc,
                                      input logic [VA_WIDTH-1:0] loop_exit_pc,
                                      input logic [31:0] taken_mask,
                                      input logic [31:0] continue_mask);
    begin
        @(negedge clk);
        control_event_wave_slot = slot[SLOT_WIDTH-1:0];
        control_event_kind = kind;
        control_event_sequential_pc = sequential_pc;
        control_event_target_pc = target_pc;
        control_event_fallthrough_pc = fallthrough_pc;
        control_event_join_pc = join_pc;
        control_event_return_pc = return_pc;
        control_event_loop_test_pc = loop_test_pc;
        control_event_loop_body_pc = loop_body_pc;
        control_event_loop_exit_pc = loop_exit_pc;
        control_event_taken_mask = taken_mask;
        control_event_continue_mask = continue_mask;
        control_event_valid = 1'b1;
        #1;
        if (!control_event_ready || !control_event_accepted)
            $fatal(1, "decoded control event %0d was not accepted for slot %0d", kind, slot);
        @(posedge clk); #1; @(negedge clk); control_event_valid = 1'b0;
    end
    endtask

    task automatic wait_memory_completion(input integer slot);
    begin
        timeout = 0;
        while (!memory_completion_valid || memory_completion_wave_slot != slot) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 200) $fatal(1, "integrated memory completion timed out for slot %0d state=%0d wait=%b local_req=%b/%b local_rsp=%b outstanding=%b", slot, dut.lsu.state_q[slot], memory_waiting_mask, dut.local_memory_request_valid, dut.local_memory_request_accepted, dut.local_memory_response_valid, dut.shared_memory_outstanding_wave_bitmap);
        end
        if (!memory_completion_ready) begin
            @(negedge clk); memory_completion_ready = 1'b1;
        end
        @(posedge clk); #1; @(negedge clk);
        memory_completion_ready = 1'b0;
    end
    endtask

    task automatic wait_vector_complete(input logic [SLOT_WIDTH-1:0] slot);
    begin
        timeout = 0;
        while (!vector_complete_valid && dut.execution_frontend.vector_pipe.state_q != 3'd0) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 1000) $fatal(1, "vector execution did not complete: busy=%b matrix=%b state=%0d readv=%b readrsp=%b writev=%b writerdy=%b",
                vector_execution_busy_bitmap, matrix_execution_busy_bitmap,
                dut.execution_frontend.vector_pipe.state_q,
                dut.execution_frontend.vread_valid, dut.execution_frontend.vread_response,
                dut.execution_frontend.vwrite_valid, dut.execution_frontend.vwrite_ready);
        end
        if (vector_complete_valid && (vector_complete_wave_slot != slot || vector_address_fault
            || vector_uninitialized_fault || vector_illegal_opcode))
            $fatal(1, "vector execution completed with an unexpected tag or fault");
        if (vector_complete_valid) begin @(posedge clk); #1; end
    end
    endtask

    task automatic set_register(input logic [SLOT_WIDTH-1:0] slot,
                                input integer architectural_register,
                                input logic [31:0] lane0_value);
    begin
        base_row = $unsigned(allocation_row_base_flat[(slot*ROW_WIDTH)+:ROW_WIDTH]);
        physical_row = base_row + (architectural_register / 8);
        bank = architectural_register % 8;
        for (lane = 0; lane < 32; lane = lane + 1)
            dut.execution_frontend.pooled.storage.data[physical_row][bank][(lane*32)+:32]
                = lane0_value + lane;
        dut.execution_frontend.pooled.storage.initialized[physical_row][bank] = 1'b1;
    end
    endtask

    task automatic issue_matrix(input logic [SLOT_WIDTH-1:0] slot);
    begin
        matrix_request_d_base[(slot*8)+:8] = 8'd32;
        matrix_request_a_base[(slot*8)+:8] = 8'd64;
        matrix_request_b_base[(slot*8)+:8] = 8'd68;
        matrix_request_valid[slot] = 1;
        timeout = 0;
        while (!matrix_request_accepted[slot]) begin
            @(negedge clk); #1; timeout = timeout + 1;
            if (timeout > 200) $fatal(1, "matrix request did not issue for slot %0d", slot);
        end
        @(posedge clk); #1; @(negedge clk); matrix_request_valid[slot] = 0;
    end
    endtask

    task automatic issue_matrix_slot0;
    begin
        issue_matrix(0);
    end
    endtask

    task automatic wait_no_exec_busy;
    begin
        timeout = 0;
        while ((matrix_execution_busy_bitmap != '0) || (vector_execution_busy_bitmap != '0)) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 300) $fatal(1, "mixed execution did not quiesce");
        end
    end
    endtask

    initial begin
        dispatch_valid = 0; dispatch_workgroup_id = 0; dispatch_wave_count = 0;
        dispatch_vgpr_register_counts_flat = 0; dispatch_scalar_state_units_per_wave = 1;
        dispatch_shared_local_bytes = 0; dispatch_other_workgroup_state_units = 0;
        barrier_arrive_valid = 0; barrier_arrive_workgroup_id = 0; barrier_arrive_local_wave_mask = 0;
        terminate_wave_valid = 0; terminate_wave_slot = 0; terminate_wave_reason = 0;
        workgroup_abort_valid = 0; workgroup_abort_id = 0;
        restore_valid = 0; restore_wave_slot = 0; restore_register = 0; restore_data = 0;
        matrix_request_valid = 0; matrix_request_full_wave_active = '1;
        matrix_request_d_base = 0; matrix_request_a_base = 0; matrix_request_b_base = 0;
        vector_request_valid = 0; vector_request_opcode = 0; vector_request_source0 = 0;
        vector_request_source1 = 0; vector_request_destination = 0; vector_request_lane_mask = 0;
        memory_epoch = 32'd1; memory_issue_valid = '0; memory_issue_global = '0;
        memory_issue_write = '0; memory_issue_destination_flat = '0;
        memory_issue_lane_mask_flat = '0; memory_issue_byte_addresses_flat = '0;
        memory_issue_store_data_flat = '0; memory_completion_ready = 1'b1;
        memory_fault_ready = 1'b1; memory_global_request_ready = 1'b0;
        memory_global_response_valid = 1'b0; memory_global_response_workgroup_id = '0;
        memory_global_response_wave_slot = '0; memory_global_response_epoch = '0;
        memory_global_response_transaction_tag = '0; memory_global_response_write = 1'b0;
        memory_global_response_lane_mask = '0; memory_global_response_lane_data_flat = '0;
        memory_global_response_fault_code = '0; memory_global_response_fault_lane = '0;
        instruction_fetch_enable = 1'b0;
        instruction_memory_request_ready = 1'b0;
        instruction_memory_response_valid = 1'b0;
        instruction_memory_response_workgroup_id = '0;
        instruction_memory_response_wave_slot = '0;
        instruction_memory_response_epoch = '0;
        instruction_memory_response_transaction_tag = '0;
        instruction_memory_response_pc = '0;
        instruction_memory_response_word = '0;
        instruction_memory_response_fault_code = '0;
        instruction_fetch_unhandled_ready = '0;
        instruction_fetch_fault_ready_mask = '0;
        repeat (3) @(posedge clk); @(negedge clk); reset_n = 1;

        // Exact-size rejection and maximum-fit complete admission use the actual allocator.
        dispatch(8'd1, 1, 9'd257, 0, 0, 0, 5'd5);
        if (allocation_active_bitmap != '0 || live_wave_mask != '0)
            $fatal(1, "invalid VGPR demand changed allocator or scheduler state");
        dispatch_with_resource_demand(8'd8, 2, 16, 16, 0, 0,
            16'd32768, 32'd64, 16'd1, 5'd10);
        dispatch_with_resource_demand(8'd9, 1, 16, 0, 0, 0,
            16'd1, 32'h80000000, 16'd1, 5'd12);
        dispatch_with_resource_demand(8'd70, 1, 16, 0, 0, 0,
            16'd1, 32'd64, 32'h00010000, 5'd14);
        dispatch_with_resource_demand(8'd71, 1, 16, 0, 0, 0,
            16'd1, 32'd64, 32'h80000000, 5'd14);
        if (allocation_active_bitmap != '0 || allocation_reserved_bitmap != '0
            || resident_wave_count != 0 || workgroup_active_mask != '0)
            $fatal(1, "overflowing resource demands changed allocator or scheduler state");
        dispatch(8'd3, 2, 256, 256, 0, 0, 5'd6);
        dispatch(8'd4, 1, 16, 0, 0, 0, 5'd12);
        dispatch(8'd7, 5, 16, 16, 16, 16, 5'd2);
        dispatch(8'd2, 4, 64, 64, 64, 64, 0);
        if (allocation_active_bitmap != 4'b1111 || resident_wave_count != 4
            || allocation_register_count_flat[0+:9] != 64
            || allocation_row_base_flat != {5'd24, 5'd16, 5'd8, 5'd0})
            $fatal(1, "maximum-fit workgroup did not reserve actual allocator rows active=%b count=%h bases=%h resident=%0d",
                allocation_active_bitmap, allocation_register_count_flat, allocation_row_base_flat, resident_wave_count);
        abort_group(8'd2);
        if (allocation_active_bitmap != '0 || shared_local_bytes_used != 0)
            $fatal(1, "maximum-fit workgroup abort leaked allocator/common state");

        // Control reconvergence is checked in the same local-wave identity
        // space as the residency barrier, even when a different group owns slot 0.
        dispatch(8'd40, 1, 16, 0, 0, 0, 0);
        dispatch(8'd41, 1, 16, 0, 0, 0, 0);
        send_control_event(0, 3'd1, 0, 57'h2000, 57'h2010, 57'h2020,
            0, 0, 0, 0, 32'h1, 0);
        arrive(8'd41, 4'b0001, 1'b1, 0);
        abort_group(8'd40); abort_group(8'd41);

        dispatch(8'd42, 1, 16, 0, 0, 0, 0);
        dispatch(8'd43, 1, 16, 0, 0, 0, 0);
        send_control_event(1, 3'd1, 0, 57'h3000, 57'h3010, 57'h3020,
            0, 0, 0, 0, 32'h1, 0);
        @(negedge clk); barrier_arrive_workgroup_id = 8'd43;
        barrier_arrive_local_wave_mask = 4'b0001; barrier_arrive_valid = 1'b1; #1;
        if (barrier_arrive_ready || barrier_arrive_accepted)
            $fatal(1, "divergent nonzero-slot wave used another workgroup's reconvergence bit");
        @(negedge clk); barrier_arrive_valid = 1'b0;
        abort_group(8'd42); abort_group(8'd43);

        // Multiple independent complete workgroups share a CU without sharing slots.
        dispatch(8'd5, 1, 16, 0, 0, 0, 0);
        dispatch(8'd6, 1, 16, 0, 0, 0, 0);
        if (resident_wave_count != 2 || live_wave_mask != 4'b0011
            || issuable_wave_mask != 4'b0011 || shared_local_bytes_used != 128)
            $fatal(1, "independent workgroups did not coexist on actual resident slots");
        dispatch(8'd5, 1, 16, 0, 0, 0, 5'd3);
        abort_group(8'd5); abort_group(8'd6);

        // Leave two eight-row holes. The 8-register wave consumes one first-fit
        // row, but the 72-register wave needs nine contiguous rows; the remaining
        // fifteen free rows cannot satisfy that complete admission.
        dispatch(8'd10, 1, 64, 0, 0, 0, 0);
        dispatch(8'd11, 1, 64, 0, 0, 0, 0);
        dispatch(8'd12, 1, 64, 0, 0, 0, 0);
        dispatch(8'd13, 1, 64, 0, 0, 0, 0);
        abort_group(8'd11); abort_group(8'd13);
        active_before = allocation_active_bitmap;
        reserved_before = allocation_reserved_bitmap;
        row_base_before = allocation_row_base_flat;
        register_count_before = allocation_register_count_flat;
        shared_bytes_before = shared_local_bytes_used;
        dispatch_with_resource_demand(8'd20, 2, 8, 72, 0, 0,
            16'd0, 32'd64, 16'd0, 5'd9);
        if (allocation_active_bitmap != active_before || allocation_reserved_bitmap != reserved_before
            || allocation_row_base_flat != row_base_before
            || allocation_register_count_flat != register_count_before
            || live_wave_mask != 4'b0101 || shared_local_bytes_used != shared_bytes_before)
            $fatal(1, "fragmented partial admission mismatch active=%b/%b reserved=%b/%b live=%b shared=%0d/%0d",
                allocation_active_bitmap, active_before, allocation_reserved_bitmap,
                reserved_before, live_wave_mask, shared_local_bytes_used, shared_bytes_before);
        abort_group(8'd10); abort_group(8'd12);

        dispatch(8'd30, 2, 9, 17, 0, 0, 0);
        if (allocation_register_count_flat[0+:9] != 9
            || allocation_register_count_flat[9+:9] != 17
            || allocation_row_base_flat[0+:ROW_WIDTH] != 0
            || allocation_row_base_flat[ROW_WIDTH+:ROW_WIDTH] != 2)
            $fatal(1, "nonuniform architectural allocation did not use the actual rounded rows");
        abort_group(8'd30);

        // Run real matrix and vector requests for sibling waves sharing this pool.
        dispatch(8'd31, 2, 80, 80, 0, 0, 0);
        set_register(0, 32, 0); set_register(0, 33, 0); set_register(0, 34, 0); set_register(0, 35, 0);
        set_register(0, 36, 0); set_register(0, 37, 0); set_register(0, 38, 0); set_register(0, 39, 0);
        for (register_number = 64; register_number < 72; register_number = register_number + 1)
            set_register(0, register_number, 1);
        set_register(1, 0, 10); set_register(1, 1, 3);
        issue_matrix_slot0();
        timeout = 0;
        while (!matrix_execution_busy_bitmap[0]) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 32) $fatal(1, "accepted matrix wave never became busy");
        end
        issue_vector(1, 0, 1, 2);
        if (!matrix_execution_busy_bitmap[0] || !vector_execution_busy_bitmap[1])
            $fatal(1, "sibling vector execution did not overlap live matrix execution");
        wait_vector_complete(1);
        base_row = $unsigned(allocation_row_base_flat[(1*ROW_WIDTH)+:ROW_WIDTH]);
        if (dut.execution_frontend.pooled.storage.data[base_row][2][0+:32] != 13)
            $fatal(1, "actual sibling vector pipeline did not update its pooled allocation");
        wait_no_exec_busy();

        arrive(8'd31, 4'b0001, 1'b0, 0);
        if (!barrier_waiting_mask[0] || !issuable_wave_mask[1]
            || !allocation_active_bitmap[0])
            $fatal(1, "barrier waiter lost its resident allocation or blocked its sibling");
        vector_request_valid[0] = 1; #1;
        if (vector_request_accepted[0])
            $fatal(1, "barrier waiter issued an ordinary vector request");
        vector_request_valid[0] = 0;
        issue_vector(1, 0, 1, 3); wait_vector_complete(1);
        arrive(8'd31, 4'b0010, 1'b1, 0);
        for (iteration = 1; iteration <= 5; iteration = iteration + 1) begin
            arrive(8'd31, 4'b0010, 1'b0, iteration);
            arrive(8'd31, 4'b0001, 1'b1, iteration);
        end

        // A faulted busy wave leaves the barrier set immediately, releases a
        // waiting survivor, and holds its real allocator entry until idle.
        issue_vector(0, 0, 1, 4);
        timeout = 0;
        while (!vector_execution_busy_bitmap[0]) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 32) $fatal(1, "fault-path vector wave did not become busy");
        end
        arrive(8'd31, 4'b0010, 1'b0, 6);
        @(negedge clk); terminate_wave_slot = 0; terminate_wave_reason = 1;
        terminate_wave_valid = 1; #1;
        if (!terminate_wave_ready || issuable_wave_mask[0])
            $fatal(1, "same-cycle fault did not remove issue eligibility");
        @(posedge clk); #1; @(negedge clk); terminate_wave_valid = 0;
        if (allocation_active_bitmap[0] !== 1'b1 || live_wave_mask[0]
            || !release_pending_wave_mask[0] || !barrier_release_valid
            || barrier_release_wave_mask != 4'b0010 || !issuable_wave_mask[1])
            $fatal(1, "fault during sibling barrier wait lost state or released too early");
        wait_vector_complete(0);
        timeout = 0;
        while (allocation_active_bitmap[0]) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 32) $fatal(1, "faulted wave allocation was not released at quiescence");
        end
        abort_group(8'd31);
        if (allocation_active_bitmap != '0 || resident_wave_count != 0
            || shared_local_bytes_used != 0)
            $fatal(1, "kill while barrier blocked leaked pooled or common group state");
        dispatch(8'd32, 2, 16, 16, 0, 0, 0);
        arrive(8'd32, 4'b0001, 1'b0, 0);
        abort_group(8'd32);
        if (allocation_active_bitmap != '0 || shared_local_bytes_used != 0)
            $fatal(1, "kill of a barrier-blocked group leaked resources");

        // A matrix-dependent vector request keeps its live wave in the
        // participant set when a different wave faults before reaching barrier.
        dispatch(8'd33, 2, 80, 80, 0, 0, 0);
        set_register(1, 0, 0);
        for (register_number = 32; register_number < 40; register_number = register_number + 1)
            set_register(1, register_number, 0);
        for (register_number = 64; register_number < 72; register_number = register_number + 1)
            set_register(1, register_number, 1);
        issue_matrix(1);
        timeout = 0;
        while (!matrix_execution_busy_bitmap[1]) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 32) $fatal(1, "matrix fault-path wave did not become busy");
        end
        vector_request_opcode[(1*4)+:4] = 4'd0;
        vector_request_source0[(1*8)+:8] = 8'd32;
        vector_request_source1[(1*8)+:8] = 8'd0;
        vector_request_destination[(1*8)+:8] = 8'd2;
        vector_request_lane_mask[(1*32)+:32] = 32'hffffffff;
        vector_request_valid[1] = 1;
        #1;
        if (vector_request_accepted[1])
            $fatal(1, "vector request bypassed its live matrix dependency");
        arrive(8'd33, 4'b0001, 1'b0, 0);
        @(negedge clk); terminate_wave_slot = 0; terminate_wave_reason = 1;
        terminate_wave_valid = 1; #1;
        if (!terminate_wave_ready || issuable_wave_mask[0])
            $fatal(1, "matrix-sibling fault did not immediately block the departing wave");
        @(posedge clk); #1; @(negedge clk); terminate_wave_valid = 0;
        if (!matrix_execution_busy_bitmap[1] || !allocation_active_bitmap[1]
            || !live_wave_mask[1] || barrier_release_valid
            || !release_pending_wave_mask[0] || !issuable_wave_mask[1]
            || vector_request_accepted[1])
            $fatal(1, "fault removed a stalled surviving participant or released the matrix allocation early");
        timeout = 0;
        while (!vector_request_accepted[1]) begin
            @(negedge clk); #1; timeout = timeout + 1;
            if (timeout > 400) $fatal(1, "matrix dependency did not release its surviving vector wave");
        end
        @(posedge clk); #1; @(negedge clk); vector_request_valid[1] = 0;
        wait_vector_complete(1);
        if (!live_wave_mask[1] || barrier_release_valid)
            $fatal(1, "stalled surviving wave left the barrier set before arriving");
        arrive(8'd33, 4'b0010, 1'b1, 0);
        abort_group(8'd33);
        if (allocation_active_bitmap != '0 || allocation_reserved_bitmap != '0
            || shared_local_bytes_used != 0)
            $fatal(1, "matrix-fault dependency case leaked allocator or group state");

        // Fault the wave that owns an in-flight matrix operation. Its active
        // allocator entry must survive until matrix execution is quiescent.
        dispatch(8'd34, 2, 80, 80, 0, 0, 0);
        for (register_number = 32; register_number < 40; register_number = register_number + 1)
            set_register(1, register_number, 0);
        for (register_number = 64; register_number < 76; register_number = register_number + 1)
            set_register(1, register_number, 1);
        issue_matrix(1);
        timeout = 0;
        while (!matrix_execution_busy_bitmap[1]) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 32) $fatal(1, "matrix execution never became busy for same-wave fault");
        end
        arrive(8'd34, 4'b0001, 1'b0, 0);
        @(negedge clk); terminate_wave_slot = 1; terminate_wave_reason = 1;
        terminate_wave_valid = 1; #1;
        if (!terminate_wave_ready || issuable_wave_mask[1])
            $fatal(1, "matrix-busy fault did not immediately stop new issue");
        @(posedge clk); #1; @(negedge clk); terminate_wave_valid = 0;
        if (!matrix_execution_busy_bitmap[1] || !allocation_active_bitmap[1]
            || !release_pending_wave_mask[1] || !barrier_release_valid
            || barrier_release_wave_mask != 4'b0001 || !issuable_wave_mask[0])
            $fatal(1, "matrix-busy fault released resources early or blocked the surviving waiter");
        timeout = 0;
        while (allocation_active_bitmap[1]) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 400) $fatal(1, "matrix-fault allocation did not release at quiescence");
        end
        abort_group(8'd34);
        if (allocation_active_bitmap != '0 || resident_wave_count != 0
            || shared_local_bytes_used != 0)
            $fatal(1, "matrix-busy fault case leaked allocator or workgroup state");

        // Reset with barrier membership and allocations present clears both authorities.
        dispatch(8'd40, 2, 16, 16, 0, 0, 0);
        arrive(8'd40, 4'b0001, 1'b0, 0);
        set_register(1, 0, 10); set_register(1, 1, 3);
        issue_vector(1, 0, 1, 2);
        if (!vector_execution_busy_bitmap[1] || !barrier_waiting_mask[0])
            $fatal(1, "active-reset case did not contain both live execution and barrier state");
        @(negedge clk); reset_n = 0; #1;
        if (allocation_active_bitmap != '0 || resident_wave_mask != '0
            || allocation_reserved_bitmap != '0 || vector_execution_busy_bitmap != '0
            || workgroup_active_mask != '0 || shared_local_bytes_used != 0)
            $fatal(1, "reset failed to clear active execution, allocator, and barrier ownership together");
        repeat (2) @(posedge clk); @(negedge clk); reset_n = 1;

        // Reset halfway through reserve/sanitize before barrier commit. This
        // workgroup uses all physical rows, so the first allocation must remain
        // private while its large range is sanitized.
        @(negedge clk);
        dispatch_workgroup_id = 8'd41;
        dispatch_wave_count = 2;
        dispatch_vgpr_register_counts_flat = '0;
        dispatch_vgpr_register_counts_flat[0+:9] = 9'd248;
        dispatch_vgpr_register_counts_flat[9+:9] = 9'd8;
        dispatch_scalar_state_units_per_wave = 1;
        dispatch_shared_local_bytes = 64;
        dispatch_other_workgroup_state_units = 1;
        dispatch_valid = 1;
        #1;
        if (!dispatch_ready) $fatal(1, "partial-reset admission was not ready");
        @(posedge clk); #1; @(negedge clk); dispatch_valid = 0;
        timeout = 0;
        while (allocation_reserved_bitmap == '0) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 32) $fatal(1, "partial-reset admission never reserved its first wave");
        end
        if (dispatch_ready || dispatch_result_valid || workgroup_active_mask != '0
            || resident_wave_mask != '0 || live_wave_mask != '0)
            $fatal(1, "partial reservation became scheduler-visible before complete commit");
        @(negedge clk); reset_n = 0; #1;
        if (allocation_active_bitmap != '0 || allocation_reserved_bitmap != '0
            || resident_wave_mask != '0 || workgroup_active_mask != '0)
            $fatal(1, "reset during partial admission left allocator or barrier ownership");
        repeat (2) @(posedge clk); @(negedge clk); reset_n = 1;

        // Shared memory must be a real contiguous allocation owned by the
        // complete workgroup, including maximum-fit admission and retirement.
        dispatch_with_resource_demand(8'd59, 1, 8, 0, 0, 0, 0, 4096, 0,
            0);
        if (shared_local_bytes_used != 4096)
            $fatal(1, "maximum-fit workgroup did not retain its complete shared-memory allocation");
        abort_group(8'd59);
        if (shared_local_bytes_used != 0)
            $fatal(1, "workgroup retirement did not release its shared-memory region");

        // Leave two 1024-byte holes in a full 4096-byte pool. Aggregate
        // capacity permits 1536 bytes, but no contiguous region does.
        dispatch_with_resource_demand(8'd60, 1, 8, 0, 0, 0, 0, 1024, 0,
            0);
        dispatch_with_resource_demand(8'd61, 1, 8, 0, 0, 0, 0, 1024, 0,
            0);
        dispatch_with_resource_demand(8'd62, 1, 8, 0, 0, 0, 0, 1024, 0,
            0);
        dispatch_with_resource_demand(8'd63, 1, 8, 0, 0, 0, 0, 1024, 0,
            0);
        abort_group(8'd60);
        abort_group(8'd62);
        if (shared_local_bytes_used != 2048)
            $fatal(1, "workgroup release did not return its memory regions to the allocator");
        dispatch_with_resource_demand(8'd64, 1, 8, 0, 0, 0, 0, 1536, 0,
            FAIL_SHARED_MEMORY_FRAGMENTED);
        if (shared_local_bytes_used != 2048 || resident_wave_count != 2
            || allocation_active_bitmap != 4'b1010)
            $fatal(1, "fragmented memory rejection changed resident CU resources");
        dispatch_with_resource_demand(8'd65, 1, 8, 0, 0, 0, 0, 1024, 0,
            0);
        if (shared_local_bytes_used != 3072 || resident_wave_count != 3)
            $fatal(1, "workgroup did not reuse a free shared-memory region after fragmentation");
        abort_group(8'd61);
        abort_group(8'd63);
        abort_group(8'd65);
        if (shared_local_bytes_used != 0 || resident_wave_count != 0)
            $fatal(1, "shared-memory fragmentation sequence leaked workgroup resources");

        // Long randomized arrival order sequence. Every admitted wave is resident,
        // and each generation completes even though the arrival order varies.
        dispatch(8'd50, 3, 16, 16, 16, 0, 0);
        for (iteration = 0; iteration < 1700; iteration = iteration + 1) begin
            case ($urandom_range(0, 5))
                0: begin arrive(8'd50, 4'b0001, 1'b0, iteration); arrive(8'd50, 4'b0010, 1'b0, iteration); arrive(8'd50, 4'b0100, 1'b1, iteration); end
                1: begin arrive(8'd50, 4'b0001, 1'b0, iteration); arrive(8'd50, 4'b0100, 1'b0, iteration); arrive(8'd50, 4'b0010, 1'b1, iteration); end
                2: begin arrive(8'd50, 4'b0010, 1'b0, iteration); arrive(8'd50, 4'b0001, 1'b0, iteration); arrive(8'd50, 4'b0100, 1'b1, iteration); end
                3: begin arrive(8'd50, 4'b0010, 1'b0, iteration); arrive(8'd50, 4'b0100, 1'b0, iteration); arrive(8'd50, 4'b0001, 1'b1, iteration); end
                4: begin arrive(8'd50, 4'b0100, 1'b0, iteration); arrive(8'd50, 4'b0001, 1'b0, iteration); arrive(8'd50, 4'b0010, 1'b1, iteration); end
                default: begin arrive(8'd50, 4'b0100, 1'b0, iteration); arrive(8'd50, 4'b0010, 1'b0, iteration); arrive(8'd50, 4'b0001, 1'b1, iteration); end
            endcase
            if (resident_wave_count != 3 || allocation_active_bitmap[2:0] != 3'b111
                || issuable_wave_mask != 3'b111 || live_wave_mask != 3'b111)
                $fatal(1, "randomized barrier generation %0d lost complete residency", iteration);
        end
        abort_group(8'd50);

        // A shared region must not retire before the pooled allocator accepts
        // the final wave release. Keep a same-wave restore request active to
        // exercise the allocator's release backpressure path.
        dispatch_with_resource_demand(8'd58, 1, 8, 0, 0, 0, 0, 64, 0, 0);
        if (allocation_active_bitmap != 4'b0001 || shared_local_bytes_used != 64)
            $fatal(1, "release-backpressure setup did not own one wave and one region");
        @(negedge clk);
        workgroup_abort_id = 8'd58;
        workgroup_abort_valid = 1'b1;
        restore_valid = 1'b1;
        restore_wave_slot = 0;
        restore_register = 0;
        restore_data = '0;
        #1;
        if (!workgroup_abort_ready || !workgroup_abort_accepted)
            $fatal(1, "release-backpressure abort was not accepted");
        @(posedge clk); #1; @(negedge clk); workgroup_abort_valid = 1'b0;
        repeat (2) @(posedge clk); #1;
        if (allocation_active_bitmap != 4'b0001 || shared_local_bytes_used != 64
            || workgroup_active_mask == '0)
            $fatal(1, "shared region retired before final pooled VGPR release was accepted");
        @(negedge clk); restore_valid = 1'b0; workgroup_retire_ready = 1'b0;
        timeout = 0;
        while (release_pending_wave_mask != '0 && timeout < 100) begin
            @(posedge clk); #1; timeout = timeout + 1;
        end
        if (timeout >= 100 || allocation_active_bitmap != '0
            || shared_local_bytes_used != 0 || workgroup_active_mask != '0)
            $fatal(1, "release-backpressure recovery did not retire the whole workgroup");
        if (!workgroup_retire_valid || workgroup_retire_id !== 8'd58)
            $fatal(1, "final resource release did not report the retired workgroup");
        repeat (2) begin
            @(posedge clk); #1;
            if (!workgroup_retire_valid || workgroup_retire_id !== 8'd58)
                $fatal(1, "workgroup retirement event was not held under backpressure");
        end
        @(negedge clk); dispatch_workgroup_id = 8'd58; #1;
        if (dispatch_ready)
            $fatal(1, "workgroup ID was reused while its retirement event was unconsumed");
        workgroup_retire_ready = 1'b1;
        @(posedge clk); #1;
        if (workgroup_retire_valid)
            $fatal(1, "accepted retirement event remained asserted");

        // Local LSU requests use the admitted workgroup region, retain their
        // captured payload, block only their owner, and coexist with barriers.
        dispatch_with_resource_demand(8'd70, 2, 16, 16, 0, 0, 0, 64, 0, 0);
        set_register(1, 0, 10); set_register(1, 1, 3);
        set_register(0, 1, 1);
        memory_completion_ready = 1'b0;
        issue_memory(0, 1'b0, 1'b1, 8'd0, 32'd1, 32'd0, 32'hc0decafe);
        if (memory_waiting_mask !== 4'b0001 || issuable_wave_mask !== 4'b0011)
            $fatal(1, "local store wait did not preserve sibling issue eligibility");
        memory_issue_byte_addresses_flat[0+:32] = 32'd128;
        memory_issue_store_data_flat[0+:32] = 32'hdeadbeef;
        issue_vector(1, 0, 1, 2);
        wait_vector_complete(1);
        arrive(8'd70, 4'b0010, 1'b0, 0);
        wait_memory_completion(0);
        memory_completion_ready = 1'b0;
        issue_memory(0, 1'b0, 1'b0, 8'd5, 32'd1, 32'd0, 32'd0);
        vector_request_opcode[0+:4] = 4'd0;
        vector_request_source0[0+:8] = 8'd5;
        vector_request_source1[0+:8] = 8'd1;
        vector_request_destination[0+:8] = 8'd6;
        vector_request_lane_mask[0+:32] = 32'hffffffff;
        vector_request_valid[0] = 1'b1;
        #1;
        if (memory_waiting_mask[0] !== 1'b1 || vector_request_accepted[0]
            || barrier_release_valid)
            $fatal(1, "load dependency or barrier membership escaped while response was pending");
        wait_memory_completion(0);
        timeout = 0;
        while (!vector_request_accepted[0]) begin
            @(negedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "load-dependent vector instruction did not resume");
        end
        @(posedge clk); #1; @(negedge clk); vector_request_valid[0] = 1'b0;
        wait_vector_complete(0);
        base_row = $unsigned(allocation_row_base_flat[(0*ROW_WIDTH)+:ROW_WIDTH]);
        if (dut.execution_frontend.pooled.storage.data[base_row][6][0+:32]
            != 32'hc0decaff)
            $fatal(1, "local load did not write its captured destination before dependent issue");
        arrive(8'd70, 4'b0001, 1'b1, 0);
        abort_group(8'd70);

        // Reallocate local memory after a complete workgroup release, then
        // prove the new owner can store and reload through its own region.
        dispatch_with_resource_demand(8'd73, 1, 16, 0, 0, 0, 0, 64, 0, 0);
        set_register(0, 1, 10); set_register(0, 2, 3);
        vector_request_opcode[0+:4] = 4'd0;
        vector_request_source0[0+:8] = 8'd1;
        vector_request_source1[0+:8] = 8'd2;
        vector_request_destination[0+:8] = 8'd3;
        vector_request_lane_mask[0+:32] = 32'hffffffff;
        memory_completion_ready = 1'b0;
        @(negedge clk);
        vector_request_valid[0] = 1'b1;
        memory_issue_global[0] = 1'b0; memory_issue_write[0] = 1'b1;
        memory_issue_destination_flat[0+:8] = '0;
        memory_issue_lane_mask_flat[0+:32] = 32'd1;
        memory_issue_byte_addresses_flat[0+:WAVE_ADDRESS_WIDTH] = '0;
        memory_issue_store_data_flat[0+:1024] = '0;
        memory_issue_store_data_flat[0+:32] = 32'h73a55a73;
        memory_issue_valid[0] = 1'b1; #1;
        if (!vector_request_valid[0] || memory_issue_ready[0])
            $fatal(1, "simultaneous vector/memory issue did not give the older vector request priority");
        timeout = 0;
        while (!vector_request_accepted[0]) begin
            @(negedge clk); #1; timeout = timeout + 1;
            if (timeout > 100)
                $fatal(1, "simultaneous vector/memory issue deadlocked both requesters");
        end
        @(posedge clk); #1; @(negedge clk); vector_request_valid[0] = 1'b0;
        if (memory_issue_ready[0])
            $fatal(1, "memory request overtook an earlier same-wave vector operation");
        timeout = 0;
        while (!memory_issue_ready[0]) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "memory request did not resume after vector completion");
        end
        if (!memory_issue_accepted[0])
            $fatal(1, "deferred same-wave memory request did not become acceptable");
        @(posedge clk); #1; @(negedge clk); memory_issue_valid[0] = 1'b0;
        wait_memory_completion(0);
        memory_completion_ready = 1'b0;
        issue_memory(0, 1'b0, 1'b0, 8'd4, 32'd1, 32'd0, 32'd0);
        wait_memory_completion(0);
        base_row = $unsigned(allocation_row_base_flat[(0*ROW_WIDTH)+:ROW_WIDTH]);
        if (dut.execution_frontend.pooled.storage.data[base_row][4][0+:32]
            != 32'h73a55a73)
            $fatal(1, "reused local-memory region did not preserve the new workgroup's access");
        abort_group(8'd73);

        // One wave may wait on global memory while its sibling reaches a
        // barrier; the barrier retains the waiting wave until it can arrive.
        dispatch_with_resource_demand(8'd74, 2, 16, 16, 0, 0, 0, 64, 0, 0);
        memory_completion_ready = 1'b0;
        issue_memory(0, 1'b1, 1'b0, 8'd6, 32'd1, 32'h741000, 32'd0);
        tag0 = memory_global_request_transaction_tag;
        @(negedge clk); memory_global_request_ready = 1'b1;
        @(posedge clk); #1; @(negedge clk); memory_global_request_ready = 1'b0;
        arrive(8'd74, 4'b0010, 1'b0, 0);
        if (!barrier_waiting_mask[1] || !memory_waiting_mask[0]
            || live_wave_mask != 4'b0011 || barrier_release_valid)
            $fatal(1, "barrier membership changed while a surviving sibling waited on memory");
        set_register(0, 1, 10); set_register(0, 2, 3);
        issue_vector(0, 1, 2, 7);
        wait_vector_complete(0);
        if (!memory_waiting_mask[0] || !barrier_waiting_mask[1])
            $fatal(1, "independent same-wave work did not progress alongside memory wait");
        memory_global_response_workgroup_id = 8'd74;
        memory_global_response_wave_slot = 0;
        memory_global_response_epoch = memory_epoch;
        memory_global_response_transaction_tag = tag0;
        memory_global_response_write = 1'b0;
        memory_global_response_lane_mask = 32'd1;
        memory_global_response_lane_data_flat = '0;
        memory_global_response_lane_data_flat[0+:32] = 32'h74107410;
        memory_global_response_fault_code = '0;
        memory_global_response_fault_lane = 6'h3f;
        memory_global_response_valid = 1'b1; #1;
        if (!memory_global_response_ready || !dut.lsu.writeback_valid)
            $fatal(1, "delayed barrier wave response did not reach pooled writeback");
        @(posedge clk); #1; @(negedge clk); memory_global_response_valid = 1'b0;
        wait_memory_completion(0);
        arrive(8'd74, 4'b0001, 1'b1, 0);
        if (barrier_release_wave_mask != 4'b0011)
            $fatal(1, "memory-delayed barrier did not release the whole surviving workgroup");
        abort_group(8'd74);

        // A global request is stable under downstream backpressure. Aborting
        // after acceptance holds the wave allocation until the matching response.
        dispatch_with_resource_demand(8'd71, 1, 16, 0, 0, 0, 0, 64, 0, 0);
        issue_memory(0, 1'b1, 1'b0, 8'd7, 32'd1, 57'h100000012345000, 32'd0);
        if (!memory_global_request_valid || memory_global_request_workgroup_id != 8'd71
            || memory_global_request_wave_slot != 0
            || memory_global_request_byte_addresses_flat[0+:VA_WIDTH] != 57'h100000012345000)
            $fatal(1, "global LSU request lost captured identity or address");
        tag0 = memory_global_request_transaction_tag;
        repeat (2) begin
            @(posedge clk); #1;
            if (!memory_global_request_valid
                || memory_global_request_transaction_tag != tag0
                || memory_global_request_byte_addresses_flat[0+:VA_WIDTH] != 57'h100000012345000)
                $fatal(1, "global request changed while ready was low");
        end
        @(negedge clk); workgroup_abort_id = 8'd71; workgroup_abort_valid = 1'b1; #1;
        if (!workgroup_abort_ready || !workgroup_abort_accepted
            || !memory_global_request_valid
            || memory_global_request_transaction_tag != tag0)
            $fatal(1, "abort under global backpressure withdrew an already-presented request");
        @(posedge clk); #1; @(negedge clk); workgroup_abort_valid = 1'b0;
        if (!memory_global_request_valid
            || memory_global_request_transaction_tag != tag0
            || memory_global_request_byte_addresses_flat[0+:VA_WIDTH] != 57'h100000012345000)
            $fatal(1, "killed stalled global request was not held stable through handshake");
        memory_global_request_ready = 1'b1;
        @(posedge clk); #1; @(negedge clk); memory_global_request_ready = 1'b0;
        if (!release_pending_wave_mask[0] || !allocation_active_bitmap[0]
            || !memory_waiting_mask[0])
            $fatal(1, "killed accepted global request did not hold VGPR release until response");
        memory_global_response_workgroup_id = 8'd71;
        memory_global_response_wave_slot = 0;
        memory_global_response_epoch = 32'd1;
        memory_global_response_transaction_tag = tag0;
        memory_global_response_write = 1'b0;
        memory_global_response_lane_mask = 32'd1;
        memory_global_response_lane_data_flat = '0;
        memory_global_response_lane_data_flat[0+:32] = 32'hface1234;
        memory_global_response_fault_code = 0;
        memory_global_response_fault_lane = 6'h3f;
        memory_global_response_valid = 1'b1; #1;
        if (!memory_global_response_ready || dut.lsu.writeback_valid)
            $fatal(1, "killed global response was not discarded without VGPR writeback");
        @(posedge clk); #1; @(negedge clk); memory_global_response_valid = 1'b0;
        timeout = 0;
        while (release_pending_wave_mask[0]) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "aborted global operation did not drain for release");
        end
        if (allocation_active_bitmap != '0 || shared_local_bytes_used != 0)
            $fatal(1, "global response drain did not release the workgroup allocation");

        // A memory fault is delivered with identity and terminates its wave;
        // whole-workgroup resources retire only through the ordinary quiescent path.
        dispatch_with_resource_demand(8'd72, 1, 16, 0, 0, 0, 0, 64, 0, 0);
        memory_fault_ready = 1'b0;
        issue_memory(0, 1'b0, 1'b0, 8'd8, 32'd1, 32'd64, 32'd0);
        timeout = 0;
        while (!memory_fault_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "invalid local address did not produce a memory fault");
        end
        vector_request_opcode[0+:4] = 4'd0;
        vector_request_source0[0+:8] = 8'd1;
        vector_request_source1[0+:8] = 8'd2;
        vector_request_destination[0+:8] = 8'd9;
        vector_request_lane_mask[0+:32] = 32'hffffffff;
        vector_request_valid[0] = 1'b1; #1;
        if (vector_request_accepted[0] || issuable_wave_mask[0])
            $fatal(1, "fault-pending memory wave issued vector work under fault backpressure");
        @(negedge clk); vector_request_valid[0] = 1'b0;
        if (memory_fault_workgroup_id != 8'd72 || memory_fault_wave_slot != 0
            || memory_fault_code != 3'd3 || memory_fault_lane != 0)
            $fatal(1, "local bounds fault lost its architectural identity or cause");
        memory_fault_ready = 1'b1;
        timeout = 0;
        while (workgroup_active_mask != '0) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "faulted memory wave did not retire its workgroup");
        end
        if (allocation_active_bitmap != '0 || shared_local_bytes_used != 0)
            $fatal(1, "memory fault leaked VGPR or local-region ownership");

        // Dispatch initializes authoritative control state for each resident wave.
        dispatch_start_pc = 57'h1000;
        dispatch_initial_live_lane_mask_flat = '0;
        dispatch_initial_live_lane_mask_flat[0+:32] = 32'hf;
        dispatch_initial_live_lane_mask_flat[32+:32] = 32'h3;
        dispatch_with_resource_demand(8'd73, 2, 16, 16, 0, 0, 0, 64, 0, 0);
        if (control_pc_flat[0+:VA_WIDTH] != 57'h1000
            || control_pc_flat[VA_WIDTH+:VA_WIDTH] != 57'h1000
            || control_live_lane_mask_flat[0+:32] != 32'hf
            || control_live_lane_mask_flat[32+:32] != 32'h3
            || control_active_lane_mask_flat[0+:32] != 32'hf
            || control_active_lane_mask_flat[32+:32] != 32'h3)
            $fatal(1, "dispatch did not initialize per-wave PC and live-lane masks");
        set_register(0, 1, 32'd10);
        set_register(0, 2, 32'd20);
        set_register(0, 8, 32'd100);

        // A divergent branch masks vector/memory lanes and cannot enter a
        // workgroup barrier before reconvergence.
        send_control_event(0, 3'd1, 0, 57'h1100, 57'h1200, 57'h1300,
            0, 0, 0, 0, 32'h3, 0);
        if (control_active_lane_mask_flat[0+:32] != 32'h3 || control_reconverged_mask[0])
            $fatal(1, "branch event did not expose its active lane path");
        decoded_sequential_pc_flat[0+:VA_WIDTH] = 57'h1104;
        issue_vector(0, 8'd1, 8'd2, 8'd8);
        if (control_pc_flat[0+:VA_WIDTH] != 57'h1104)
            $fatal(1, "accepted vector instruction did not advance its wave PC");
        wait_vector_complete(0);
        base_row = $unsigned(allocation_row_base_flat[0+:ROW_WIDTH]);
        if (dut.execution_frontend.pooled.storage.data[base_row+1][0][0+:32] != 32'd30
            || dut.execution_frontend.pooled.storage.data[base_row+1][0][32+:32] != 32'd32
            || dut.execution_frontend.pooled.storage.data[base_row+1][0][64+:32] != 32'd102
            || dut.execution_frontend.pooled.storage.data[base_row+1][0][96+:32] != 32'd103)
            $fatal(1, "divergent vector write changed inactive lanes or missed active lanes");
        barrier_arrive_workgroup_id = 8'd73;
        barrier_arrive_local_wave_mask = 4'b0001;
        barrier_arrive_valid = 1'b1; #1;
        if (barrier_arrive_ready || barrier_arrive_accepted)
            $fatal(1, "divergent wave reached a workgroup barrier before reconvergence");
        @(negedge clk); barrier_arrive_valid = 1'b0;

        // A global load carries only active lanes; delayed service leaves this
        // wave waiting while its sibling can finish independent vector work.
        decoded_sequential_pc_flat[0+:VA_WIDTH] = 57'h1108;
        issue_memory(0, 1'b1, 1'b0, 8'd9, 32'hf, 57'h100000010000000, 32'd0);
        if (!memory_global_request_valid || memory_global_request_lane_mask != 32'h3
            || !memory_waiting_mask[0] || control_pc_flat[0+:VA_WIDTH] != 57'h1108)
            $fatal(1, "divergent global memory request did not retain the active lane mask");
        tag0 = memory_global_request_transaction_tag;
        epoch0 = memory_global_request_epoch;
        control_event_wave_slot = 0; control_event_kind = 3'd0;
        control_event_sequential_pc = 57'h110c; control_event_valid = 1'b1; #1;
        if (control_event_ready || control_event_accepted
            || control_pc_flat[0+:VA_WIDTH] != 57'h1108)
            $fatal(1, "memory-waiting wave changed control state under downstream backpressure");
        @(negedge clk); control_event_valid = 1'b0;
        memory_global_request_ready = 1'b1;
        @(posedge clk); #1; @(negedge clk); memory_global_request_ready = 1'b0;
        if (!memory_waiting_mask[0])
            $fatal(1, "memory-waiting wave accepted another control event");

        decoded_sequential_pc_flat[VA_WIDTH+:VA_WIDTH] = 57'h1004;
        issue_vector(1, 8'd1, 8'd2, 8'd10);
        timeout = 0;
        while (vector_execution_busy_bitmap[1]) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "unrelated sibling vector operation did not complete");
        end
        arrive(8'd73, 4'b0010, 1'b0, 0);
        if (!barrier_waiting_mask[1] || !memory_waiting_mask[0])
            $fatal(1, "barrier did not retain a sibling while another wave waited on memory");

        memory_global_response_workgroup_id = 8'd73;
        memory_global_response_wave_slot = 0;
        memory_global_response_epoch = epoch0;
        memory_global_response_transaction_tag = tag0;
        memory_global_response_write = 1'b0;
        memory_global_response_lane_mask = 32'h3;
        memory_global_response_lane_data_flat = '0;
        memory_global_response_lane_data_flat[0+:32] = 32'h12345678;
        memory_global_response_lane_data_flat[32+:32] = 32'h87654321;
        memory_global_response_fault_code = 0;
        memory_global_response_fault_lane = 6'h3f;
        memory_global_response_valid = 1'b1; #1;
        if (!memory_global_response_ready)
            $fatal(1, "delayed global load response was not accepted");
        @(posedge clk); #1; @(negedge clk); memory_global_response_valid = 1'b0;
        wait_memory_completion(0);
        base_row = $unsigned(allocation_row_base_flat[(0*ROW_WIDTH)+:ROW_WIDTH]);
        if (dut.execution_frontend.pooled.storage.data[base_row][9][0+:32] != 32'h12345678
            || dut.execution_frontend.pooled.storage.data[base_row][9][32+:32] != 32'h87654321)
            $fatal(1, "delayed global response did not write back the captured destination lanes");
        timeout = 0;
        while (memory_waiting_mask[0]) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "global response did not release the waiting wave");
        end

        send_control_event(0, 3'd0, 57'h1300, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        if (control_active_lane_mask_flat[0+:32] != 32'hc)
            $fatal(1, "first decoded path did not defer at its explicit join");
        send_control_event(0, 3'd0, 57'h1300, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        if (control_active_lane_mask_flat[0+:32] != 32'hf || !control_reconverged_mask[0])
            $fatal(1, "decoded paths did not reconverge");
        arrive(8'd73, 4'b0001, 1'b1, 0);
        abort_group(8'd73);

        // Malformed control retires through the same terminal, barrier, and
        // quiescent allocator path as other wave faults.
        dispatch_start_pc = 57'h2000;
        dispatch_initial_live_lane_mask_flat[0+:32] = 32'hf;
        dispatch_with_resource_demand(8'd74, 1, 16, 0, 0, 0, 0, 64, 0, 0);
        send_control_event(0, 3'd1, 0, 57'h2001, 57'h2010, 57'h2020,
            0, 0, 0, 0, 32'h1, 0);
        if (!control_terminal_valid || control_terminal_wave_slot != 0
            || control_terminal_fault_code != 4'd1)
            $fatal(1, "invalid control PC did not enter the wave terminal path");
        timeout = 0;
        while (workgroup_active_mask != '0) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "control fault did not drain workgroup resources");
        end
        if (allocation_active_bitmap != '0 || shared_local_bytes_used != 0)
            $fatal(1, "control fault leaked VGPR or workgroup-local state");

        // Abort drops a divergent resident wave and slot reuse starts from a
        // fresh PC/mask with no saved path state.
        dispatch_start_pc = 57'h3000;
        dispatch_initial_live_lane_mask_flat[0+:32] = 32'hf;
        dispatch_with_resource_demand(8'd75, 1, 16, 0, 0, 0, 0, 64, 0, 0);
        send_control_event(0, 3'd1, 0, 57'h3100, 57'h3200, 57'h3300,
            0, 0, 0, 0, 32'h3, 0);
        abort_group(8'd75);
        dispatch_start_pc = 57'h4000;
        dispatch_with_resource_demand(8'd76, 1, 16, 0, 0, 0, 0, 64, 0, 0);
        if (control_pc_flat[0+:VA_WIDTH] != 57'h4000
            || control_live_lane_mask_flat[0+:32] != 32'hf
            || control_active_lane_mask_flat[0+:32] != 32'hf)
            $fatal(1, "reused resident slot retained prior control-flow state");
        abort_group(8'd76);

        // End-to-end fetch owns the dispatch PC, captures request identity,
        // accepts out-of-order-ready sibling work through the existing decoder,
        // and prevents release until a killed outstanding request drains.
        dispatch_start_pc = 57'h5000;
        memory_epoch = 32'hc001;
        instruction_fetch_enable = 1'b1;
        instruction_memory_request_ready = 1'b0;
        dispatch_with_resource_demand(8'd77, 2, 16, 16, 0, 0, 0, 64, 0, 0);
        set_register(1, 1, 32'd10);
        set_register(1, 2, 32'd20);
        timeout = 0;
        while (!instruction_memory_request_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "first resident wave did not request its dispatch PC");
        end
        if (instruction_memory_request_workgroup_id != 8'd77
            || instruction_memory_request_wave_slot != 0
            || instruction_memory_request_epoch != memory_epoch
            || instruction_memory_request_pc != 57'h5000)
            $fatal(1, "first instruction fetch did not retain its wave/workgroup/epoch/PC identity");
        fetch_tag0 = instruction_memory_request_transaction_tag;
        fetch_epoch0 = instruction_memory_request_epoch;
        fetch_pc0 = instruction_memory_request_pc;
        repeat (2) begin
            @(posedge clk); #1;
            if (!instruction_memory_request_valid
                || instruction_memory_request_workgroup_id != 8'd77
                || instruction_memory_request_wave_slot != 0
                || instruction_memory_request_transaction_tag != fetch_tag0
                || instruction_memory_request_pc != fetch_pc0)
                $fatal(1, "presented instruction request changed during downstream backpressure");
        end
        control_event_valid = 1'b1;
        control_event_wave_slot = 0;
        control_event_kind = 3'd0;
        control_event_sequential_pc = 57'h5004;
        #1;
        if (control_event_accepted || instruction_memory_request_valid !== 1'b1)
            $fatal(1, "fetch-waiting wave accepted dependent control work or lost its request");
        @(negedge clk); control_event_valid = 1'b0; instruction_memory_request_ready = 1'b1;
        @(posedge clk); #1;
        @(negedge clk); instruction_memory_request_ready = 1'b0;
        timeout = 0;
        while (!instruction_memory_request_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "unrelated resident wave did not request while its sibling waited");
        end
        if (instruction_memory_request_workgroup_id != 8'd77
            || instruction_memory_request_wave_slot != 1
            || instruction_memory_request_epoch != memory_epoch
            || instruction_memory_request_pc != 57'h5000
            || !dut.instruction_fetch_issue_block_mask[0])
            $fatal(1, "sibling fetch identity or independent wait state was incorrect");
        fetch_tag1 = instruction_memory_request_transaction_tag;
        fetch_epoch1 = instruction_memory_request_epoch;
        fetch_pc1 = instruction_memory_request_pc;
        @(negedge clk); instruction_memory_request_ready = 1'b1;
        @(posedge clk); #1;
        @(negedge clk); instruction_memory_request_ready = 1'b0;
        instruction_memory_response_workgroup_id = 8'd77;
        instruction_memory_response_wave_slot = 1;
        instruction_memory_response_epoch = fetch_epoch1;
        instruction_memory_response_transaction_tag = fetch_tag1;
        instruction_memory_response_pc = fetch_pc1;
        instruction_memory_response_word = 32'h1003_0102;
        instruction_memory_response_fault_code = 0;
        instruction_memory_response_valid = 1'b1; #1;
        if (!instruction_memory_response_ready)
            $fatal(1, "matching sibling instruction response was backpressured");
        @(posedge clk); #1;
        @(negedge clk); instruction_memory_response_valid = 1'b0;
        timeout = 0;
        while (!vector_request_accepted[1]) begin
            @(negedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "fetched vector word did not enter resident execution");
        end
        @(posedge clk); #1;
        if (control_pc_flat[VA_WIDTH+:VA_WIDTH] != 57'h5004
            || !dut.instruction_fetch_busy_mask[0]
            || !dut.instruction_fetch_issue_block_mask[0])
            $fatal(1, "accepted fetched instruction failed to advance only its PC or retain sibling wait");
        instruction_fetch_enable = 1'b0;
        wait_vector_complete(1);
        if (control_pc_flat[0+:VA_WIDTH] != 57'h5000)
            $fatal(1, "waiting sibling PC advanced before its instruction response");
        base_row = $unsigned(allocation_row_base_flat[(1*ROW_WIDTH)+:ROW_WIDTH]);
        if (dut.execution_frontend.pooled.storage.data[base_row+1][3][0+:32] != 32'd30
            || dut.execution_frontend.pooled.storage.data[base_row+1][3][32+:32] != 32'd30)
            $fatal(1, "fetched vector word did not complete pooled-VGPR writeback");

        @(negedge clk); workgroup_abort_id = 8'd77; workgroup_abort_valid = 1'b1; #1;
        if (!workgroup_abort_ready || !workgroup_abort_accepted)
            $fatal(1, "workgroup abort was not accepted with an instruction fetch outstanding");
        @(posedge clk); #1;
        @(negedge clk); workgroup_abort_valid = 1'b0;
        if (!release_pending_wave_mask[0] || !dut.instruction_fetch_busy_mask[0])
            $fatal(1, "workgroup release ignored outstanding instruction fetch activity");
        instruction_memory_response_workgroup_id = 8'd77;
        instruction_memory_response_wave_slot = 0;
        instruction_memory_response_epoch = fetch_epoch0;
        instruction_memory_response_transaction_tag = fetch_tag0;
        instruction_memory_response_pc = fetch_pc0;
        instruction_memory_response_word = 32'h1004_0102;
        instruction_memory_response_fault_code = 0;
        instruction_memory_response_valid = 1'b1; #1;
        if (!instruction_memory_response_ready)
            $fatal(1, "aborted instruction fetch response was not drained");
        @(posedge clk); #1;
        @(negedge clk); instruction_memory_response_valid = 1'b0;
        timeout = 0;
        while (workgroup_active_mask != '0) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "drained instruction fetch did not release the aborted workgroup");
        end
        if (allocation_active_bitmap != '0 || shared_local_bytes_used != 0)
            $fatal(1, "instruction fetch drain leaked CU resources");

        // Fetch-service faults report the captured identity and use the same
        // terminal barrier path, including normal complete-workgroup release.
        instruction_fetch_enable = 1'b1;
        instruction_memory_request_ready = 1'b1;
        dispatch_start_pc = 57'h6000;
        dispatch_with_resource_demand(8'd78, 1, 16, 0, 0, 0, 0, 64, 0, 0);
        timeout = 0;
        while (!instruction_memory_request_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "fetch-fault wave did not issue an instruction request");
        end
        if (instruction_memory_request_wave_slot != 0
            || instruction_memory_request_pc != 57'h6000)
            $fatal(1, "fetch-fault request identity was incorrect");
        fetch_tag0 = instruction_memory_request_transaction_tag;
        fetch_epoch0 = instruction_memory_request_epoch;
        fetch_pc0 = instruction_memory_request_pc;
        @(posedge clk); #1;
        instruction_memory_response_workgroup_id = 8'd78;
        instruction_memory_response_wave_slot = 0;
        instruction_memory_response_epoch = fetch_epoch0;
        instruction_memory_response_transaction_tag = fetch_tag0;
        instruction_memory_response_pc = fetch_pc0;
        instruction_memory_response_word = '0;
        instruction_memory_response_fault_code = 3'd2;
        instruction_memory_response_valid = 1'b1; #1;
        @(posedge clk); #1;
        if (!instruction_fetch_fault_valid_mask[0]
            || instruction_fetch_fault_workgroup_id_flat[0+:8] != 8'd78
            || instruction_fetch_fault_epoch_flat[0+:32] != fetch_epoch0
            || instruction_fetch_fault_transaction_tag_flat[0+:64] != fetch_tag0
            || instruction_fetch_fault_pc_flat[0+:VA_WIDTH] != fetch_pc0
            || instruction_fetch_fault_code_flat[0+:3] != 3'd2)
            $fatal(1, "instruction fetch fault lost captured transaction identity");
        @(negedge clk); instruction_memory_response_valid = 1'b0;
        instruction_fetch_fault_ready_mask[0] = 1'b1;
        timeout = 0;
        while (workgroup_active_mask != '0) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "instruction fetch fault did not retire its workgroup");
        end
        @(negedge clk); instruction_fetch_fault_ready_mask = '0;
        instruction_fetch_enable = 1'b0;
        if (allocation_active_bitmap != '0 || shared_local_bytes_used != 0)
            $fatal(1, "instruction fetch fault leaked CU resources");

        // An accepted raw-class word hands sequential-PC authority back to
        // the existing external decoder/handler metadata input.
        instruction_fetch_enable = 1'b1;
        instruction_memory_request_ready = 1'b1;
        dispatch_start_pc = 57'h7000;
        decoded_sequential_pc_flat[0+:VA_WIDTH] = 57'h7008;
        dispatch_with_resource_demand(8'd79, 1, 16, 0, 0, 0, 0, 64, 0, 0);
        timeout = 0;
        while (!instruction_memory_request_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "raw-class wave did not issue an instruction request");
        end
        if (instruction_memory_request_workgroup_id != 8'd79
            || instruction_memory_request_wave_slot != 0
            || instruction_memory_request_pc != 57'h7000)
            $fatal(1, "raw-class fetch request identity was incorrect");
        fetch_tag0 = instruction_memory_request_transaction_tag;
        fetch_epoch0 = instruction_memory_request_epoch;
        fetch_pc0 = instruction_memory_request_pc;
        @(posedge clk); #1;
        @(negedge clk);
        instruction_memory_response_workgroup_id = 8'd79;
        instruction_memory_response_wave_slot = 0;
        instruction_memory_response_epoch = fetch_epoch0;
        instruction_memory_response_transaction_tag = fetch_tag0;
        instruction_memory_response_pc = fetch_pc0;
        instruction_memory_response_word = 32'h2A96_7854;
        instruction_memory_response_fault_code = 0;
        instruction_memory_response_valid = 1'b1; #1;
        if (!instruction_memory_response_ready)
            $fatal(1, "matching raw-class response was backpressured");
        @(posedge clk); #1;
        @(negedge clk); instruction_memory_response_valid = 1'b0;
        if (!instruction_fetch_unhandled_valid[0]
            || instruction_fetch_unhandled_class_flat[0+:4] != 4'h2
            || instruction_fetch_unhandled_word_flat[0+:32] != 32'h2A96_7854
            || instruction_fetch_unhandled_opcode_flat[0+:4] !== 4'hA
            || instruction_fetch_unhandled_destination_flat[0+:8] !== 8'h96
            || instruction_fetch_unhandled_source0_flat[0+:8] !== 8'h78
            || instruction_fetch_unhandled_source1_flat[0+:8] !== 8'h54
            || instruction_fetch_unhandled_workgroup_id_flat[0+:8] != 8'd79
            || instruction_fetch_unhandled_pc_flat[0+:VA_WIDTH] != 57'h7000
            || instruction_fetch_unhandled_epoch_flat[0+:32] != fetch_epoch0
            || instruction_fetch_unhandled_transaction_tag_flat[0+:64] != fetch_tag0)
            $fatal(1, "raw-class handler handoff lost instruction identity");
        repeat (2) begin
            @(posedge clk); #1;
            if (!instruction_fetch_unhandled_valid[0]
                || control_pc_flat[0+:VA_WIDTH] != 57'h7000)
                $fatal(1, "raw-class instruction retired or advanced before handler acceptance");
        end
        @(negedge clk); instruction_fetch_unhandled_ready[0] = 1'b1;
        @(posedge clk); #1;
        @(negedge clk); instruction_fetch_unhandled_ready[0] = 1'b0;
        if (control_pc_flat[0+:VA_WIDTH] != 57'h7008
            || instruction_fetch_unhandled_valid[0])
            $fatal(1, "accepted raw-class instruction did not advance to handler-supplied sequential PC");
        timeout = 0;
        while (!instruction_memory_request_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "raw-class acceptance did not fetch its next PC");
        end
        if (instruction_memory_request_pc != 57'h7008)
            $fatal(1, "raw-class acceptance retried the same PC instead of the supplied next PC");
        fetch_tag0 = instruction_memory_request_transaction_tag;
        fetch_epoch0 = instruction_memory_request_epoch;
        fetch_pc0 = instruction_memory_request_pc;
        @(negedge clk); workgroup_abort_id = 8'd79; workgroup_abort_valid = 1'b1; #1;
        if (!workgroup_abort_ready || !workgroup_abort_accepted)
            $fatal(1, "raw-class workgroup abort was not accepted");
        @(posedge clk); #1;
        @(negedge clk); workgroup_abort_valid = 1'b0;
        instruction_memory_request_ready = 1'b1;
        @(posedge clk); #1;
        @(negedge clk); instruction_memory_request_ready = 1'b0;
        instruction_memory_response_workgroup_id = 8'd79;
        instruction_memory_response_wave_slot = 0;
        instruction_memory_response_epoch = fetch_epoch0;
        instruction_memory_response_transaction_tag = fetch_tag0;
        instruction_memory_response_pc = fetch_pc0;
        instruction_memory_response_word = 32'h2000_0000;
        instruction_memory_response_fault_code = 0;
        instruction_memory_response_valid = 1'b1; #1;
        @(posedge clk); #1;
        @(negedge clk); instruction_memory_response_valid = 1'b0;
        timeout = 0;
        while (workgroup_active_mask != '0) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "raw-class stale response did not release aborted workgroup");
        end
        instruction_fetch_enable = 1'b0;
        if (allocation_active_bitmap != '0 || shared_local_bytes_used != 0)
            $fatal(1, "raw-class acceptance/release leaked workgroup resources");

        // Control class opcode 1 provisionally branches from PC+4 by a signed
        // byte displacement before opcode 0 terminates through normal release.
        instruction_fetch_enable = 1'b1;
        instruction_memory_request_ready = 1'b1;
        dispatch_start_pc = 57'h8000;
        dispatch_with_resource_demand(8'd80, 1, 16, 0, 0, 0, 0, 64, 0, 0);
        timeout = 0;
        while (!instruction_memory_request_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "provisional termination wave did not issue an instruction request");
        end
        if (instruction_memory_request_workgroup_id != 8'd80
            || instruction_memory_request_wave_slot != 0
            || instruction_memory_request_pc != 57'h8000)
            $fatal(1, "provisional termination fetch request identity was incorrect");
        fetch_tag0 = instruction_memory_request_transaction_tag;
        fetch_epoch0 = instruction_memory_request_epoch;
        fetch_pc0 = instruction_memory_request_pc;
        @(posedge clk); #1;
        @(negedge clk);
        instruction_memory_response_workgroup_id = 8'd80;
        instruction_memory_response_wave_slot = 0;
        instruction_memory_response_epoch = fetch_epoch0;
        instruction_memory_response_transaction_tag = fetch_tag0;
        instruction_memory_response_pc = fetch_pc0;
        instruction_memory_response_word = 32'h3100_0008;
        instruction_memory_response_fault_code = 0;
        instruction_memory_response_valid = 1'b1; #1;
        if (!instruction_memory_response_ready)
            $fatal(1, "matching provisional branch response was backpressured");
        @(posedge clk); #1;
        @(negedge clk); instruction_memory_response_valid = 1'b0;
        if (instruction_fetch_unhandled_valid[0])
            $fatal(1, "provisional branch instruction escaped to the external raw handler");
        @(posedge clk); #1;
        if (control_pc_flat[0+:VA_WIDTH] != 57'h800c)
            $fatal(1, "provisional branch did not select PC+4+8");
        timeout = 0;
        while (!instruction_memory_request_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "provisional branch did not fetch its target PC");
        end
        if (instruction_memory_request_workgroup_id != 8'd80
            || instruction_memory_request_pc != 57'h800c)
            $fatal(1, "provisional branch did not preserve the target request identity");
        fetch_tag0 = instruction_memory_request_transaction_tag;
        fetch_epoch0 = instruction_memory_request_epoch;
        fetch_pc0 = instruction_memory_request_pc;
        @(posedge clk); #1;
        @(negedge clk);
        instruction_memory_response_workgroup_id = 8'd80;
        instruction_memory_response_wave_slot = 0;
        instruction_memory_response_epoch = fetch_epoch0;
        instruction_memory_response_transaction_tag = fetch_tag0;
        instruction_memory_response_pc = fetch_pc0;
        instruction_memory_response_word = 32'h3000_0000;
        instruction_memory_response_fault_code = 0;
        instruction_memory_response_valid = 1'b1; #1;
        if (!instruction_memory_response_ready)
            $fatal(1, "matching provisional termination response was backpressured");
        @(posedge clk); #1;
        @(negedge clk); instruction_memory_response_valid = 1'b0;
        if (instruction_fetch_unhandled_valid[0])
            $fatal(1, "provisional termination instruction escaped to the external raw handler");
        timeout = 0;
        while (workgroup_active_mask != '0) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "branch-then-termination did not retire its workgroup");
        end
        if (allocation_active_bitmap != '0 || shared_local_bytes_used != 0)
            $fatal(1, "branch-then-termination leaked workgroup resources");

        // An out-of-range branch target must become the existing invalid-PC
        // wave fault and retire through ordinary workgroup resource release.
        dispatch_start_pc = 57'h0;
        dispatch_with_resource_demand(8'd81, 1, 16, 0, 0, 0, 0, 64, 0, 0);
        timeout = 0;
        while (!instruction_memory_request_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "invalid-branch wave did not issue an instruction request");
        end
        if (instruction_memory_request_workgroup_id != 8'd81
            || instruction_memory_request_wave_slot != 0
            || instruction_memory_request_pc != 57'h0)
            $fatal(1, "invalid-branch fetch request identity was incorrect");
        fetch_tag0 = instruction_memory_request_transaction_tag;
        fetch_epoch0 = instruction_memory_request_epoch;
        fetch_pc0 = instruction_memory_request_pc;
        @(posedge clk); #1;
        @(negedge clk);
        instruction_memory_response_workgroup_id = 8'd81;
        instruction_memory_response_wave_slot = 0;
        instruction_memory_response_epoch = fetch_epoch0;
        instruction_memory_response_transaction_tag = fetch_tag0;
        instruction_memory_response_pc = fetch_pc0;
        instruction_memory_response_word = 32'h31ff_fff8;
        instruction_memory_response_fault_code = 0;
        instruction_memory_response_valid = 1'b1; #1;
        if (!instruction_memory_response_ready)
            $fatal(1, "matching out-of-range branch response was backpressured");
        @(posedge clk); #1;
        @(negedge clk); instruction_memory_response_valid = 1'b0;
        @(posedge clk); #1;
        if (instruction_fetch_unhandled_valid[0])
            $fatal(1, "out-of-range branch escaped to the external raw handler");
        timeout = 0;
        while (workgroup_active_mask != '0) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 100) $fatal(1, "invalid branch did not retire its workgroup");
        end
        if (allocation_active_bitmap != '0 || shared_local_bytes_used != 0)
            $fatal(1, "invalid branch fault leaked workgroup resources");
        instruction_fetch_enable = 1'b0;

        $display("[pass] authoritative residency, LSU and instruction fetch waits, fetched branch/termination/fault, stale response drain, fault/kill lifecycle, and region reuse passed.");
        $finish;
    end
endmodule
