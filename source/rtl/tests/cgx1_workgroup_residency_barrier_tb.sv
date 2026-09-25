// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_workgroup_residency_barrier_tb;
    localparam integer SLOTS = 8;
    localparam integer SLOT_WIDTH = 3;
    localparam integer COUNT_WIDTH = 4;
    localparam integer ROW_WIDTH = 4;
    localparam integer ID_WIDTH = 8;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic dispatch_valid;
    logic [ID_WIDTH-1:0] dispatch_workgroup_id;
    logic [COUNT_WIDTH-1:0] dispatch_wave_count;
    logic [8:0] dispatch_vgpr_registers_per_wave;
    logic [15:0] dispatch_scalar_state_units_per_wave;
    logic [31:0] dispatch_shared_local_bytes;
    logic [15:0] dispatch_other_workgroup_state_units;
    logic dispatch_ready;
    logic dispatch_accepted;
    logic [4:0] dispatch_failure;
    logic [SLOTS-1:0] dispatch_allocated_wave_slots;
    logic [(SLOTS*SLOT_WIDTH)-1:0] dispatch_wave_slot_map_flat;
    logic [(SLOTS*ROW_WIDTH)-1:0] dispatch_vgpr_row_base_flat;

    logic barrier_arrive_valid;
    logic [ID_WIDTH-1:0] barrier_arrive_workgroup_id;
    logic [SLOTS-1:0] barrier_arrive_wave_mask;
    logic barrier_arrive_ready;
    logic barrier_arrive_accepted;
    logic barrier_release_valid;
    logic [ID_WIDTH-1:0] barrier_release_workgroup_id;
    logic [31:0] barrier_release_generation;
    logic [SLOTS-1:0] barrier_release_wave_mask;

    logic terminate_wave_valid;
    logic [SLOT_WIDTH-1:0] terminate_wave_slot;
    logic [1:0] terminate_wave_reason;
    logic terminate_wave_ready;
    logic terminate_wave_accepted;
    logic workgroup_abort_valid;
    logic [ID_WIDTH-1:0] workgroup_abort_id;
    logic workgroup_abort_ready;
    logic workgroup_abort_accepted;

    logic [ID_WIDTH-1:0] query_workgroup_id;
    logic query_workgroup_found;
    logic [COUNT_WIDTH-1:0] query_workgroup_wave_count;
    logic [SLOTS-1:0] query_workgroup_live_waves;
    logic [SLOTS-1:0] query_workgroup_arrived_waves;
    logic [31:0] query_barrier_generation;

    logic [SLOTS-1:0] resident_wave_mask;
    logic [SLOTS-1:0] barrier_waiting_mask;
    logic [SLOTS-1:0] issuable_wave_mask;
    logic [3:0] workgroup_active_mask;
    logic [COUNT_WIDTH-1:0] resident_wave_count;
    logic [4:0] pooled_vgpr_rows_used;
    logic [31:0] scalar_state_units_used;
    logic [31:0] shared_local_bytes_used;
    logic [31:0] other_workgroup_state_units_used;

    logic [SLOTS-1:0] issue_request_valid;
    logic [SLOTS-1:0] issue_dependency_ready;
    logic issue_selected_valid;
    logic [SLOT_WIDTH-1:0] issue_selected_wave_slot;
    logic issue_selected_accepted = 1'b1;
    integer seed = 32'h6C17B221;
    integer rand_value;
    integer expected_generation;
    integer index;
    logic [SLOTS-1:0] local_mask;
    logic [SLOTS-1:0] available_mask;
    logic [SLOTS*SLOT_WIDTH-1:0] allocated_map;

    always #5 clk = ~clk;
    assign issue_request_valid = resident_wave_mask;
    assign issue_dependency_ready = issuable_wave_mask;

    cgx1_workgroup_residency_barrier #(
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .PHYSICAL_VGPR_ROWS(16),
        .MAX_WORKGROUP_CONTEXTS(4),
        .SCALAR_PREDICATE_STATE_UNITS(128),
        .SHARED_LOCAL_MEMORY_BYTES(4096),
        .OTHER_WORKGROUP_STATE_UNITS(128),
        .WORKGROUP_ID_WIDTH(ID_WIDTH),
        .WAVE_SLOT_WIDTH(SLOT_WIDTH),
        .LOCAL_WAVE_WIDTH(SLOT_WIDTH),
        .ROW_WIDTH(ROW_WIDTH),
        .ROW_COUNT_WIDTH(5),
        .WORKGROUP_CONTEXT_WIDTH(2),
        .WAVE_COUNT_WIDTH(COUNT_WIDTH)
    ) dut (.*);

    cgx1_vector_resident_wave_scheduler #(
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .WAVE_SLOT_WIDTH(SLOT_WIDTH)
    ) issue_arbiter (
        .clk(clk),
        .reset_n(reset_n),
        .request_valid(issue_request_valid),
        .dependency_ready(issue_dependency_ready),
        .selected_valid(issue_selected_valid),
        .selected_wave_slot(issue_selected_wave_slot),
        .selected_accepted(issue_selected_accepted)
    );

    function automatic integer CountOnes(input logic [SLOTS-1:0] value);
        integer bit_index;
        begin
            CountOnes = 0;
            for (bit_index = 0; bit_index < SLOTS; bit_index = bit_index + 1)
                if (value[bit_index]) CountOnes = CountOnes + 1;
        end
    endfunction

    function automatic integer SlotAt(
        input logic [(SLOTS*SLOT_WIDTH)-1:0] slot_map,
        input integer local_wave);
        begin
            SlotAt = slot_map[(local_wave*SLOT_WIDTH) +: SLOT_WIDTH];
        end
    endfunction

    task automatic ResetController;
        begin
            @(negedge clk);
            dispatch_valid = 1'b0;
            barrier_arrive_valid = 1'b0;
            terminate_wave_valid = 1'b0;
            workgroup_abort_valid = 1'b0;
            reset_n = 1'b0;
            repeat (2) @(posedge clk);
            @(negedge clk);
            reset_n = 1'b1;
            #1;
            if (resident_wave_mask != '0 || workgroup_active_mask != '0
                || resident_wave_count != 0 || pooled_vgpr_rows_used != 0
                || scalar_state_units_used != 0 || shared_local_bytes_used != 0
                || other_workgroup_state_units_used != 0) begin
                $fatal(1, "reset did not clear resident workgroup resources");
            end
        end
    endtask

    task automatic SendDispatch(
        input logic [ID_WIDTH-1:0] workgroup_id,
        input logic [COUNT_WIDTH-1:0] wave_count,
        input logic [8:0] vgprs_per_wave,
        input logic [15:0] scalar_units_per_wave,
        input logic [31:0] shared_bytes,
        input logic [15:0] other_units,
        input logic [4:0] expected_failure,
        output logic [SLOTS*SLOT_WIDTH-1:0] slot_map);
        logic [SLOTS-1:0] expected_allocated_slots;
        begin
            @(negedge clk);
            dispatch_valid = 1'b1;
            dispatch_workgroup_id = workgroup_id;
            dispatch_wave_count = wave_count;
            dispatch_vgpr_registers_per_wave = vgprs_per_wave;
            dispatch_scalar_state_units_per_wave = scalar_units_per_wave;
            dispatch_shared_local_bytes = shared_bytes;
            dispatch_other_workgroup_state_units = other_units;
            #1;
            if (!dispatch_ready || (dispatch_failure !== expected_failure)
                || (dispatch_accepted !== (expected_failure == 0))) begin
                $fatal(1, "dispatch %0d response mismatch: failure=%0d accepted=%b expected=%0d",
                    workgroup_id, dispatch_failure, dispatch_accepted, expected_failure);
            end
            slot_map = dispatch_wave_slot_map_flat;
            expected_allocated_slots = dispatch_allocated_wave_slots;
            if (expected_failure == 0
                && CountOnes(dispatch_allocated_wave_slots) != wave_count) begin
                $fatal(1, "dispatch %0d did not reserve the complete wave set", workgroup_id);
            end
            @(posedge clk);
            #1;
            @(negedge clk);
            dispatch_valid = 1'b0;
            #1;
            if (expected_failure == 0) begin
                if ((resident_wave_mask & expected_allocated_slots) != expected_allocated_slots)
                    $fatal(1, "dispatch %0d admitted without making every planned wave resident", workgroup_id);
                query_workgroup_id = workgroup_id;
                #1;
                if (!query_workgroup_found || CountOnes(query_workgroup_live_waves) != wave_count
                    || CountOnes(resident_wave_mask) < wave_count) begin
                    $fatal(1, "admitted workgroup %0d was not fully resident", workgroup_id);
                end
            end
        end
    endtask

    task automatic SendArrival(
        input logic [ID_WIDTH-1:0] workgroup_id,
        input logic [SLOTS-1:0] wave_mask,
        input logic expected_release,
        input integer generation);
        begin
            @(negedge clk);
            barrier_arrive_valid = 1'b1;
            barrier_arrive_workgroup_id = workgroup_id;
            barrier_arrive_wave_mask = wave_mask;
            #1;
            if (!barrier_arrive_ready || !barrier_arrive_accepted) begin
                $fatal(1, "barrier arrival rejected for workgroup %0d mask %h",
                    workgroup_id, wave_mask);
            end
            @(posedge clk);
            #1;
            if (barrier_release_valid !== expected_release) begin
                $fatal(1, "barrier release mismatch for workgroup %0d generation %0d",
                    workgroup_id, generation);
            end
            if (expected_release
                && (barrier_release_workgroup_id != workgroup_id
                    || barrier_release_generation != generation)) begin
                $fatal(1, "barrier released the wrong workgroup or generation");
            end
            @(negedge clk);
            barrier_arrive_valid = 1'b0;
            barrier_arrive_wave_mask = '0;
        end
    endtask

    task automatic SendTermination(
        input integer wave_slot,
        input logic expected_release,
        input integer generation,
        input logic [1:0] reason);
        begin
            @(negedge clk);
            terminate_wave_valid = 1'b1;
            terminate_wave_slot = wave_slot[SLOT_WIDTH-1:0];
            terminate_wave_reason = reason;
            #1;
            if (!terminate_wave_ready || !terminate_wave_accepted)
                $fatal(1, "resident wave termination was rejected at slot %0d", wave_slot);
            @(posedge clk);
            #1;
            if (barrier_release_valid !== expected_release)
                $fatal(1, "wave termination barrier-release result mismatch");
            if (expected_release && barrier_release_generation != generation)
                $fatal(1, "wave termination released the wrong barrier generation");
            @(negedge clk);
            terminate_wave_valid = 1'b0;
        end
    endtask

    task automatic SendAbort(input logic [ID_WIDTH-1:0] workgroup_id);
        integer resident_before;
        integer group_wave_count;
        begin
            query_workgroup_id = workgroup_id;
            #1;
            if (!query_workgroup_found)
                $fatal(1, "workgroup abort target %0d was not resident", workgroup_id);
            resident_before = resident_wave_count;
            group_wave_count = CountOnes(query_workgroup_live_waves);
            @(negedge clk);
            workgroup_abort_valid = 1'b1;
            workgroup_abort_id = workgroup_id;
            #1;
            if (!workgroup_abort_ready || !workgroup_abort_accepted)
                $fatal(1, "workgroup abort rejected for workgroup %0d", workgroup_id);
            @(posedge clk);
            #1;
            query_workgroup_id = workgroup_id;
            #1;
            if (query_workgroup_found
                || resident_wave_count != resident_before - group_wave_count)
                $fatal(1, "workgroup abort leaked its resident CU state");
            @(negedge clk);
            workgroup_abort_valid = 1'b0;
        end
    endtask

    initial begin
        dispatch_valid = 1'b0;
        dispatch_workgroup_id = '0;
        dispatch_wave_count = '0;
        dispatch_vgpr_registers_per_wave = '0;
        dispatch_scalar_state_units_per_wave = '0;
        dispatch_shared_local_bytes = '0;
        dispatch_other_workgroup_state_units = '0;
        barrier_arrive_valid = 1'b0;
        barrier_arrive_workgroup_id = '0;
        barrier_arrive_wave_mask = '0;
        terminate_wave_valid = 1'b0;
        terminate_wave_slot = '0;
        terminate_wave_reason = '0;
        workgroup_abort_valid = 1'b0;
        workgroup_abort_id = '0;
        query_workgroup_id = '0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        #1;

        SendDispatch(8'd1, 1, 16, 2, 256, 4, 0, allocated_map);
        SendArrival(8'd1, 8'b00000001, 1'b1, 0);
        query_workgroup_id = 8'd1;
        #1;
        if (query_barrier_generation != 1) $fatal(1, "single-wave barrier generation did not advance");

        ResetController();
        SendDispatch(8'd2, 3, 16, 2, 256, 4, 0, allocated_map);
        SendArrival(8'd2, 8'b00000111, 1'b1, 0);

        ResetController();
        SendDispatch(8'd3, 4, 16, 2, 256, 4, 0, allocated_map);
        SendArrival(8'd3, 8'b00001000, 1'b0, 0);
        SendArrival(8'd3, 8'b00000011, 1'b0, 0);
        SendArrival(8'd3, 8'b00000100, 1'b1, 0);

        ResetController();
        SendDispatch(8'd4, 4, 16, 2, 256, 4, 0, allocated_map);
        SendArrival(8'd4, 8'b00000100, 1'b0, 0);
        SendArrival(8'd4, 8'b00001000, 1'b0, 0);
        SendArrival(8'd4, 8'b00000001, 1'b0, 0);
        SendArrival(8'd4, 8'b00000010, 1'b1, 0);

        ResetController();
        SendDispatch(8'd5, 2, 16, 2, 256, 4, 0, allocated_map);
        SendArrival(8'd5, 8'b00000001, 1'b0, 0);
        #1;
        if (issuable_wave_mask != 8'b00000010 || !issue_selected_valid
            || issue_selected_wave_slot != 1) begin
            $fatal(1, "wave at a barrier blocked its schedulable workgroup sibling");
        end
        SendArrival(8'd5, 8'b00000010, 1'b1, 0);

        ResetController();
        SendDispatch(8'd6, 2, 16, 2, 256, 4, 0, allocated_map);
        SendDispatch(8'd7, 2, 16, 2, 256, 4, 0, allocated_map);
        SendArrival(8'd6, 8'b00000001, 1'b0, 0);
        #1;
        if (!issue_selected_valid || issue_selected_wave_slot == SlotAt(allocated_map, 0))
            $fatal(1, "waiting workgroup caused cross-workgroup issue head-of-line blocking");

        ResetController();
        SendDispatch(8'd8, 3, 16, 2, 256, 4, 0, allocated_map);
        expected_generation = 0;
        for (index = 0; index < 20; index = index + 1) begin
            SendArrival(8'd8, 8'b00000100, 1'b0, expected_generation);
            SendArrival(8'd8, 8'b00000001, 1'b0, expected_generation);
            SendArrival(8'd8, 8'b00000010, 1'b1, expected_generation);
            expected_generation = expected_generation + 1;
            query_workgroup_id = 8'd8;
            #1;
            if (query_barrier_generation != expected_generation)
                $fatal(1, "barrier generation did not advance on reuse iteration %0d", index);
        end

        ResetController();
        SendDispatch(8'd9, 8, 16, 16, 4096, 128, 0, allocated_map);
        if (resident_wave_mask != 8'hff || resident_wave_count != 8
            || pooled_vgpr_rows_used != 16 || scalar_state_units_used != 128
            || shared_local_bytes_used != 4096 || other_workgroup_state_units_used != 128)
            $fatal(1, "maximum-fit workgroup did not reserve every CU resource exactly");

        ResetController();
        SendDispatch(8'd13, 4, 16, 32, 0, 0, 0, allocated_map);
        SendDispatch(8'd14, 1, 16, 1, 0, 0, 11, allocated_map);

        ResetController();
        SendDispatch(8'd15, 1, 16, 1, 0, 0, 0, allocated_map);
        SendDispatch(8'd16, 1, 16, 1, 0, 0, 0, allocated_map);
        SendDispatch(8'd17, 1, 16, 1, 0, 0, 0, allocated_map);
        SendDispatch(8'd18, 1, 16, 1, 0, 0, 0, allocated_map);
        SendDispatch(8'd19, 1, 16, 1, 0, 0, 4, allocated_map);

        ResetController();
        SendDispatch(8'd10, 2, 256, 1, 0, 0, 6, allocated_map);
        SendDispatch(8'd11, 1, 16, 1, 4097, 0, 12, allocated_map);
        SendDispatch(8'd12, 9, 1, 0, 0, 0, 2, allocated_map);

        ResetController();
        SendDispatch(8'd20, 1, 32, 1, 0, 0, 0, allocated_map);
        SendDispatch(8'd21, 1, 32, 1, 0, 0, 0, allocated_map);
        SendDispatch(8'd22, 1, 32, 1, 0, 0, 0, allocated_map);
        SendDispatch(8'd23, 1, 32, 1, 0, 0, 0, allocated_map);
        SendAbort(8'd21);
        SendAbort(8'd23);
        SendDispatch(8'd24, 1, 33, 1, 0, 0, 9, allocated_map);

        ResetController();
        SendDispatch(8'd30, 3, 16, 4, 1024, 8, 0, allocated_map);
        SendArrival(8'd30, 8'b00000110, 1'b0, 0);
        SendTermination(SlotAt(allocated_map, 0), 1'b1, 0, 2'b01);
        query_workgroup_id = 8'd30;
        #1;
        if (!query_workgroup_found || query_barrier_generation != 1
            || query_workgroup_arrived_waves != '0 || resident_wave_count != 2)
            $fatal(1, "wave termination did not remove its barrier participant or release siblings");
        SendTermination(SlotAt(allocated_map, 1), 1'b0, 1, 2'b00);
        SendTermination(SlotAt(allocated_map, 2), 1'b0, 1, 2'b00);
        if (workgroup_active_mask != '0 || resident_wave_count != 0
            || shared_local_bytes_used != 0 || pooled_vgpr_rows_used != 0)
            $fatal(1, "normal workgroup completion leaked CU resources");

        SendDispatch(8'd35, 3, 16, 2, 256, 4, 0, allocated_map);
        SendArrival(8'd35, 8'b00000101, 1'b0, 0);
        SendTermination(SlotAt(allocated_map, 2), 1'b0, 0, 2'b01);
        query_workgroup_id = 8'd35;
        #1;
        if (query_workgroup_arrived_waves != 8'b00000001
            || issuable_wave_mask != 8'b00000010)
            $fatal(1, "wave fault left a stale barrier arrival or blocked a live sibling");
        SendArrival(8'd35, 8'b00000010, 1'b1, 0);
        SendAbort(8'd35);

        SendDispatch(8'd31, 3, 32, 2, 512, 6, 0, allocated_map);
        SendArrival(8'd31, 8'b00000011, 1'b0, 0);
        SendAbort(8'd31);
        if (resident_wave_count != 0 || scalar_state_units_used != 0
            || shared_local_bytes_used != 0 || other_workgroup_state_units_used != 0)
            $fatal(1, "fault/kill abort leaked resources while waves were barrier-blocked");

        SendDispatch(8'd32, 2, 16, 2, 256, 4, 0, allocated_map);
        SendArrival(8'd32, 8'b00000001, 1'b0, 0);
        ResetController();
        SendDispatch(8'd33, 8, 16, 16, 4096, 128, 0, allocated_map);

        ResetController();
        SendDispatch(8'd50, 4, 16, 2, 512, 8, 0, allocated_map);
        for (index = 0; index < 5000; index = index + 1) begin
            query_workgroup_id = 8'd50;
            #1;
            if (!query_workgroup_found || CountOnes(query_workgroup_live_waves) != 4)
                $fatal(1, "randomized test lost an admitted workgroup wave");
            available_mask = query_workgroup_live_waves & ~query_workgroup_arrived_waves;
            rand_value = $urandom(seed);
            local_mask = available_mask & rand_value[SLOTS-1:0];
            if (local_mask == '0) begin
                for (integer bit_index = 0; bit_index < SLOTS; bit_index = bit_index + 1) begin
                    if ((local_mask == '0) && available_mask[bit_index])
                        local_mask[bit_index] = 1'b1;
                end
            end
            SendArrival(8'd50, local_mask,
                ((query_workgroup_arrived_waves | local_mask) == query_workgroup_live_waves),
                query_barrier_generation);
            #1;
            if ((resident_wave_mask != (issuable_wave_mask | barrier_waiting_mask))
                || ((issuable_wave_mask & barrier_waiting_mask) != '0)
                || (issuable_wave_mask == '0) || !issue_selected_valid
                || CountOnes(resident_wave_mask) != CountOnes(query_workgroup_live_waves)
                || pooled_vgpr_rows_used > 16 || shared_local_bytes_used > 4096) begin
                $fatal(1, "randomized barrier/scheduler invariant failed at cycle %0d", index);
            end
        end

        $display("[pass] complete-workgroup residency, CU resource admission, barrier generations, release, kill/fault/reset, and randomized RTL forward-progress checks passed.");
        $finish;
    end
endmodule
