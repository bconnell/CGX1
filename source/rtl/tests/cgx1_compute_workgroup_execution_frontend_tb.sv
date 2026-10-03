// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_compute_workgroup_execution_frontend_tb;
    localparam integer ROWS = 32;
    localparam integer SLOTS = 4;
    localparam integer GROUPS = 6;
    localparam integer ROW_WIDTH = 5;
    localparam integer SLOT_WIDTH = 2;
    localparam integer COUNT_WIDTH = 3;
    localparam logic [4:0] FAIL_SHARED_MEMORY_FRAGMENTED = 5'd16;
    logic clk = 0, reset_n = 0;
    logic dispatch_valid, dispatch_ready;
    logic [7:0] dispatch_workgroup_id;
    logic [COUNT_WIDTH-1:0] dispatch_wave_count;
    logic [(SLOTS*9)-1:0] dispatch_vgpr_register_counts_flat;
    logic [15:0] dispatch_scalar_state_units_per_wave, dispatch_other_workgroup_state_units;
    logic [31:0] dispatch_shared_local_bytes;
    logic dispatch_result_valid, dispatch_accepted;
    logic [4:0] dispatch_failure;
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
    logic [SLOTS-1:0] active_before, reserved_before;
    logic [(SLOTS*ROW_WIDTH)-1:0] row_base_before;
    logic [(SLOTS*9)-1:0] register_count_before;
    logic [31:0] shared_bytes_before;

    always #5 clk = ~clk;

    cgx1_compute_workgroup_execution_frontend #(
        .PHYSICAL_ROWS(ROWS), .RESIDENT_WAVE_SLOTS(SLOTS),
        .MAX_WORKGROUP_CONTEXTS(GROUPS), .WORKGROUP_ID_WIDTH(8),
        .ROW_WIDTH(ROW_WIDTH), .WAVE_SLOT_WIDTH(SLOT_WIDTH),
        .WAVE_COUNT_WIDTH(COUNT_WIDTH)
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
        input logic [15:0] other_units,
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
            if (timeout > 100) $fatal(1, "vector request did not issue for slot %0d", slot);
        end
        @(posedge clk); #1; @(negedge clk); vector_request_valid[slot] = 0;
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
        repeat (3) @(posedge clk); @(negedge clk); reset_n = 1;

        // Exact-size rejection and maximum-fit complete admission use the actual allocator.
        dispatch(8'd1, 1, 9'd257, 0, 0, 0, 5'd5);
        if (allocation_active_bitmap != '0 || live_wave_mask != '0)
            $fatal(1, "invalid VGPR demand changed allocator or scheduler state");
        dispatch_with_resource_demand(8'd8, 2, 16, 16, 0, 0,
            16'd32768, 32'd64, 16'd1, 5'd10);
        dispatch_with_resource_demand(8'd9, 1, 16, 0, 0, 0,
            16'd1, 32'h80000000, 16'd1, 5'd12);
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
        @(negedge clk); restore_valid = 1'b0;
        timeout = 0;
        while (release_pending_wave_mask != '0 && timeout < 100) begin
            @(posedge clk); #1; timeout = timeout + 1;
        end
        if (timeout >= 100 || allocation_active_bitmap != '0
            || shared_local_bytes_used != 0 || workgroup_active_mask != '0)
            $fatal(1, "release-backpressure recovery did not retire the whole workgroup");

        $display("[pass] authoritative pooled workgroup admission, rollback, actual mixed execution, barrier generations, release backpressure, quiescent fault/kill, reset, and 5,100 randomized arrivals passed.");
        $finish;
    end
endmodule
