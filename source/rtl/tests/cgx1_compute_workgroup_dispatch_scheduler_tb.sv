`timescale 1ns/1ps
module cgx1_compute_workgroup_dispatch_scheduler_tb;
    localparam integer SLOTS = 4;
    localparam integer WG_WIDTH = 8;
    localparam integer PC_WIDTH = 16;
    localparam integer WAVE_WIDTH = 3;
    localparam integer PENDING_WIDTH = 4;

    logic clk = 0;
    logic reset_n = 0;
    always #5 clk = ~clk;

    logic tile_eligible = 1;
    logic [63:0] faulted_queue_mask = 0;
    logic submit_valid = 0, submit_ready;
    logic [5:0] submit_queue_context_id = 0;
    logic [63:0] submit_process_id = 0, submit_address_space_id = 0;
    logic [2:0] submit_priority = 0;
    logic submit_graphics = 0;
    logic [WG_WIDTH-1:0] submit_workgroup_id = 0;
    logic [WAVE_WIDTH-1:0] submit_wave_count = 1;
    logic [PC_WIDTH-1:0] submit_start_pc = 0;
    logic [(SLOTS*32)-1:0] submit_initial_live_lane_mask_flat = '1;
    logic [(SLOTS*9)-1:0] submit_vgpr_register_counts_flat = '0;
    logic [15:0] submit_scalar_state_units_per_wave = 1;
    logic [31:0] submit_shared_local_bytes = 0;
    logic [15:0] submit_other_workgroup_state_units = 0;

    logic dispatch_valid, dispatch_ready = 1;
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
    logic [15:0] dispatch_other_workgroup_state_units;

    logic dispatch_result_valid = 0;
    logic dispatch_accepted = 0;
    logic [4:0] dispatch_failure = 0;
    logic completion_valid, completion_ready = 1;
    logic [5:0] completion_queue_context_id;
    logic [63:0] completion_process_id, completion_address_space_id;
    logic [WG_WIDTH-1:0] completion_workgroup_id;
    logic [1:0] completion_status;
    logic [4:0] completion_failure;
    logic [PENDING_WIDTH-1:0] pending_count;

    cgx1_compute_workgroup_dispatch_scheduler #(
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .MAX_PENDING_ENTRIES(8),
        .WORKGROUP_ID_WIDTH(WG_WIDTH),
        .VIRTUAL_ADDRESS_WIDTH(PC_WIDTH),
        .AGING_INTERVAL_CYCLES(1)
    ) dut (.*);

    task automatic enqueue(
        input logic [5:0] context_id,
        input logic [2:0] priority_value,
        input logic [WG_WIDTH-1:0] workgroup_id,
        input logic graphics,
        input logic [63:0] process_id,
        input logic [63:0] address_space_id);
        integer guard;
        begin
            @(negedge clk);
            submit_queue_context_id = context_id;
            submit_priority = priority_value;
            submit_workgroup_id = workgroup_id;
            submit_graphics = graphics;
            submit_process_id = process_id;
            submit_address_space_id = address_space_id;
            submit_valid = 1;
            guard = 0;
            while (!submit_ready && guard < 20) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (!submit_ready) $fatal(1, "scheduler ingress stayed full");
            @(posedge clk); #1;
            @(negedge clk); submit_valid = 0;
        end
    endtask

    task automatic wait_for_any_dispatch;
        integer guard;
        begin
            dispatch_ready = 1;
            #1;
            guard = 0;
            while (!dispatch_valid && guard < 100) begin
                @(negedge clk); #1;
                guard = guard + 1;
            end
            if (!dispatch_valid) $fatal(1,
                "queued workgroup was not dispatched: pending=%0d tile=%0b ready=%0b selected=%0b attempt=%0b inflight=%0b entry0=%0b selected0=%0d/%0d",
                pending_count, tile_eligible, dispatch_ready, dut.selected_valid,
                dut.selected_attempt, dut.inflight_q, dut.entry_valid[0],
                dut.selected_context, dut.entry_workgroup_id[0]);
        end
    endtask

    task automatic wait_for_dispatch(
        input logic [5:0] expected_context,
        input logic [WG_WIDTH-1:0] expected_workgroup);
        begin
            wait_for_any_dispatch();
            if (dispatch_queue_context_id !== expected_context
                || dispatch_workgroup_id !== expected_workgroup)
                $fatal(1, "wrong dispatch selected: context=%0d workgroup=%0d expected=%0d/%0d",
                    dispatch_queue_context_id, dispatch_workgroup_id,
                    expected_context, expected_workgroup);
        end
    endtask

    task automatic finish_frontend_attempt(
        input logic accepted,
        input logic [4:0] failure,
        input integer expected_completion_status,
        input logic [4:0] expected_completion_failure);
        begin
            if (!dispatch_ready) $fatal(1, "test frontend was not ready for dispatch");
            @(posedge clk); #1;
            @(negedge clk);
            dispatch_result_valid = 1;
            dispatch_accepted = accepted;
            dispatch_failure = failure;
            @(posedge clk); #1;
            if (expected_completion_status < 0) begin
                if (completion_valid) $fatal(1, "retryable failure emitted a terminal completion");
            end else begin
                if (!completion_valid
                    || completion_status !== expected_completion_status[1:0]
                    || completion_failure !== expected_completion_failure)
                    $fatal(1, "completion mismatch: valid=%0b status=%0d failure=%0d",
                        completion_valid, completion_status, completion_failure);
            end
            @(negedge clk);
            dispatch_result_valid = 0;
            dispatch_accepted = 0;
            dispatch_failure = 0;
            dispatch_ready = 0;
            @(posedge clk); #1;
        end
    endtask

    task automatic service_success(
        input logic [5:0] expected_context,
        input logic [WG_WIDTH-1:0] expected_workgroup);
        begin
            wait_for_dispatch(expected_context, expected_workgroup);
            finish_frontend_attempt(1, 0, 0, 0);
            if (completion_queue_context_id !== expected_context
                || completion_workgroup_id !== expected_workgroup)
                $fatal(1, "completion lost queue or workgroup identity");
        end
    endtask

    task automatic service_next_success;
        logic [5:0] selected_context;
        logic [WG_WIDTH-1:0] selected_workgroup;
        begin
            wait_for_any_dispatch();
            selected_context = dispatch_queue_context_id;
            selected_workgroup = dispatch_workgroup_id;
            finish_frontend_attempt(1, 0, 0, 0);
            if (completion_queue_context_id !== selected_context
                || completion_workgroup_id !== selected_workgroup)
                $fatal(1, "completion did not match selected dispatch");
        end
    endtask

    initial begin : run_test
        integer step;
        integer guard;
        logic saw_low_priority;
        reset_n = 0;
        repeat (3) @(posedge clk);
        @(negedge clk); reset_n = 1;

        // The queue entry waits for both tile eligibility and frontend readiness.
        enqueue(5, 3, 40, 0, 64'h101, 64'h201);
        tile_eligible = 0;
        repeat (2) begin
            @(posedge clk); #1;
            if (dispatch_valid || pending_count != 1)
                $fatal(1, "ineligible tile consumed or offered queued work");
        end
        tile_eligible = 1;
        dispatch_ready = 0;
        repeat (2) begin
            @(posedge clk); #1;
            if (dispatch_valid || pending_count != 1)
                $fatal(1, "frontend backpressure lost the queued descriptor");
        end
        dispatch_ready = 1;
        wait_for_dispatch(5, 40);
        if (dispatch_process_id !== 64'h101 || dispatch_address_space_id !== 64'h201
            || dispatch_start_pc !== submit_start_pc
            || dispatch_initial_live_lane_mask_flat !== submit_initial_live_lane_mask_flat)
            $fatal(1, "dispatch payload or queue identity was not preserved");
        finish_frontend_attempt(1, 0, 0, 0);
        if (completion_queue_context_id !== 5 || completion_process_id !== 64'h101
            || completion_address_space_id !== 64'h201 || completion_workgroup_id !== 40)
            $fatal(1, "completion did not preserve submitted queue identity");

        // Same-context submissions remain FIFO; a retryable allocator result retains the head.
        dispatch_ready = 0;
        enqueue(5, 3, 41, 0, 64'h101, 64'h201);
        enqueue(5, 3, 42, 0, 64'h101, 64'h201);
        wait_for_dispatch(5, 41);
        finish_frontend_attempt(0, 5'd7, -1, 0);
        if (pending_count != 2) $fatal(1, "retryable resource pressure dropped the head");
        service_success(5, 41);
        service_success(5, 42);

        // Permanent resource impossibility completes with the frontend failure code.
        enqueue(5, 3, 43, 0, 64'h101, 64'h201);
        wait_for_dispatch(5, 43);
        finish_frontend_attempt(0, 5'd2, 1, 5'd2);
        if (pending_count != 0) $fatal(1, "permanently impossible dispatch remained queued");

        // Faulted queue contexts and graphics work are explicitly completed without CU admission.
        faulted_queue_mask[6] = 1;
        enqueue(6, 2, 50, 0, 64'h106, 64'h206);
        for (step = 0; step < 20 && !completion_valid; step = step + 1) begin
            @(posedge clk); #1;
        end
        if (!completion_valid || completion_status != 2'd2
            || completion_queue_context_id != 6 || completion_workgroup_id != 50)
            $fatal(1, "faulted queue was not reported");
        @(posedge clk); #1;
        enqueue(7, 2, 60, 1, 64'h107, 64'h207);
        for (step = 0; step < 20 && !completion_valid; step = step + 1) begin
            @(posedge clk); #1;
        end
        if (!completion_valid || completion_status != 2'd3
            || completion_queue_context_id != 7 || completion_workgroup_id != 60)
            $fatal(1, "unsupported engine class was not reported");
        @(posedge clk); #1;

        // Aging must let a persistent low-priority context reach dispatch service.
        dispatch_ready = 0;
        enqueue(8, 7, 70, 0, 64'h108, 64'h208);
        enqueue(8, 7, 71, 0, 64'h108, 64'h208);
        enqueue(9, 0, 80, 0, 64'h109, 64'h209);
        enqueue(9, 0, 81, 0, 64'h109, 64'h209);
        saw_low_priority = 0;
        for (step = 0; step < 20 && !saw_low_priority; step = step + 1) begin
            wait_for_any_dispatch();
            if (dispatch_queue_context_id == 9) saw_low_priority = 1;
            finish_frontend_attempt(1, 0, 0, 0);
        end
        if (!saw_low_priority) $fatal(1, "aging starved the lower-priority queue");
        for (step = 0; step < 8 && pending_count != 0; step = step + 1)
            service_next_success();
        if (pending_count != 0) $fatal(1, "fairness test left queued requests undrained");

        // Reset invalidates both queued state and an old frontend response.
        dispatch_ready = 0;
        enqueue(10, 3, 90, 0, 64'h10a, 64'h20a);
        wait_for_dispatch(10, 90);
        @(posedge clk); #1;
        @(negedge clk); reset_n = 0;
        repeat (2) @(posedge clk);
        #1;
        if (pending_count != 0 || completion_valid)
            $fatal(1, "reset retained dispatch state");
        @(negedge clk); reset_n = 1; dispatch_result_valid = 1;
        dispatch_accepted = 1;
        @(posedge clk); #1;
        if (completion_valid || pending_count != 0)
            $fatal(1, "stale dispatch response survived reset");

        $display("CGX1 compute workgroup dispatch scheduler checks passed.");
        $finish;
    end
endmodule
