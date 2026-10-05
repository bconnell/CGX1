// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_workgroup_residency_barrier_tb;
    localparam integer SLOTS = 4;
    localparam integer SLOT_WIDTH = 2;
    localparam integer COUNT_WIDTH = 3;
    localparam integer GROUPS = 2;
    localparam integer GROUP_WIDTH = 1;
    logic clk = 0, reset_n = 0;
    logic commit_valid;
    logic [7:0] commit_workgroup_id;
    logic [COUNT_WIDTH-1:0] commit_wave_count;
    logic [(SLOTS*SLOT_WIDTH)-1:0] commit_wave_slot_map_flat;
    logic [15:0] commit_scalar_state_units_per_wave;
    logic [31:0] commit_shared_local_bytes;
    logic [31:0] commit_other_workgroup_state_units;
    logic commit_ready, commit_accepted;
    logic barrier_arrive_valid;
    logic [7:0] barrier_arrive_workgroup_id;
    logic [SLOTS-1:0] barrier_arrive_local_wave_mask, wave_execution_busy;
    logic [SLOTS-1:0] wave_control_reconverged = '1;
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
    logic [SLOTS-1:0] allocator_release_accepted_mask;
    logic [7:0] query_workgroup_id;
    logic query_workgroup_found;
    logic [COUNT_WIDTH-1:0] query_workgroup_wave_count;
    logic [SLOTS-1:0] query_workgroup_live_waves, query_workgroup_arrived_waves;
    logic [31:0] query_barrier_generation;
    logic [SLOTS-1:0] resident_wave_mask, live_wave_mask, barrier_waiting_mask;
    logic [SLOTS-1:0] issuable_wave_mask, release_pending_wave_mask;
    logic [GROUPS-1:0] workgroup_active_mask;
    logic [SLOTS-1:0] final_wave_release_mask;
    logic [(SLOTS*8)-1:0] slot_workgroup_id_flat;
    logic [COUNT_WIDTH-1:0] resident_wave_count;
    logic [31:0] scalar_state_units_used, shared_local_bytes_used;
    logic [63:0] other_workgroup_state_units_used;
    integer generation;
    always #5 clk = ~clk;

    cgx1_workgroup_residency_barrier #(
        .RESIDENT_WAVE_SLOTS(SLOTS), .MAX_WORKGROUP_CONTEXTS(GROUPS),
        .WORKGROUP_ID_WIDTH(8), .WAVE_SLOT_WIDTH(SLOT_WIDTH),
        .LOCAL_WAVE_WIDTH(SLOT_WIDTH), .WORKGROUP_CONTEXT_WIDTH(GROUP_WIDTH),
        .WAVE_COUNT_WIDTH(COUNT_WIDTH)
    ) dut(.*);

    task automatic commit_group(input logic [7:0] id, input logic [COUNT_WIDTH-1:0] waves,
                                input logic [(SLOTS*SLOT_WIDTH)-1:0] map);
    begin
        @(negedge clk);
        commit_workgroup_id = id;
        commit_wave_count = waves;
        commit_wave_slot_map_flat = map;
        commit_valid = 1'b1;
        #1;
        if (!commit_ready || !commit_accepted) $fatal(1, "barrier context commit was refused");
        @(posedge clk); #1; @(negedge clk); commit_valid = 1'b0;
    end
    endtask

    task automatic arrive(input logic [7:0] id, input logic [SLOTS-1:0] mask,
                          input logic expected_release, input integer expected_generation);
    begin
        barrier_arrive_workgroup_id = id;
        barrier_arrive_local_wave_mask = mask;
        barrier_arrive_valid = 1'b1;
        #1;
        if (!barrier_arrive_ready || !barrier_arrive_accepted)
            $fatal(1, "barrier arrival was not accepted");
        @(posedge clk); #1;
        if (barrier_release_valid !== expected_release)
            $fatal(1, "barrier release pulse mismatch");
        if (expected_release && barrier_release_generation != expected_generation)
            $fatal(1, "barrier release generation mismatch");
        @(negedge clk); barrier_arrive_valid = 1'b0;
    end
    endtask

    initial begin
        commit_valid = 0; commit_workgroup_id = 0; commit_wave_count = 0;
        commit_wave_slot_map_flat = 0; commit_scalar_state_units_per_wave = 2;
        commit_shared_local_bytes = 128; commit_other_workgroup_state_units = 3;
        barrier_arrive_valid = 0; barrier_arrive_workgroup_id = 0;
        barrier_arrive_local_wave_mask = 0; wave_execution_busy = 0;
        terminate_wave_valid = 0; terminate_wave_slot = 0; terminate_wave_reason = 0;
        workgroup_abort_valid = 0; workgroup_abort_id = 0;
        allocator_release_accepted_mask = 0; query_workgroup_id = 0;
        repeat (3) @(posedge clk); @(negedge clk); reset_n = 1;

        // Aggregate state accounting must not wrap when two valid per-group
        // requests sum to more than the 32-bit per-group request field.
        commit_other_workgroup_state_units = 32'h8000_0000;
        commit_group(8'd8, 1, 8'b0);
        commit_group(8'd9, 1, 8'b00_00_00_01);
        if (other_workgroup_state_units_used != 64'h0000_0001_0000_0000)
            $fatal(1, "aggregated other workgroup state wrapped: %h",
                other_workgroup_state_units_used);
        for (integer retire_slot = 0; retire_slot < 2; retire_slot = retire_slot + 1) begin
            @(negedge clk);
            terminate_wave_slot = retire_slot;
            terminate_wave_reason = 0;
            terminate_wave_valid = 1;
            #1;
            if (!terminate_wave_ready)
                $fatal(1, "overflow accounting fixture wave retirement was refused");
            @(posedge clk); #1; @(negedge clk); terminate_wave_valid = 0;
        end
        allocator_release_accepted_mask = 4'b0011;
        @(posedge clk); #1; @(negedge clk); allocator_release_accepted_mask = 0;
        if (other_workgroup_state_units_used != 0 || workgroup_active_mask != 0)
            $fatal(1, "overflow accounting fixture did not release all group state");

        // One-wave workgroup releases each reused generation immediately.
        commit_group(8'd1, 1, 8'b0);
        query_workgroup_id = 1;
        for (generation = 0; generation < 8; generation = generation + 1)
            arrive(1, 4'b0001, 1'b1, generation);
        if (query_barrier_generation != 8 || issuable_wave_mask[0] != 1'b1)
            $fatal(1, "single-wave barrier reuse lost residency or generation");
        @(negedge clk); terminate_wave_slot = 0; terminate_wave_reason = 0;
        terminate_wave_valid = 1; #1;
        if (!terminate_wave_ready) $fatal(1, "single-wave completion was not accepted");
        @(posedge clk); #1; @(negedge clk); terminate_wave_valid = 0;
        allocator_release_accepted_mask[0] = 1;
        @(posedge clk); #1; @(negedge clk); allocator_release_accepted_mask = 0;

        // Arbitrary local slot assignment; a waiting wave retains ownership and
        // a live sibling can keep progressing until the full participant set arrives.
        commit_other_workgroup_state_units = 32'h1234_5678;
        commit_group(8'd2, 2, {4'b0, 2'd3, 2'd1});
        if (other_workgroup_state_units_used != 32'h1234_5678)
            $fatal(1, "barrier context truncated full-width workgroup state: %h",
                other_workgroup_state_units_used);
        query_workgroup_id = 2;
        arrive(2, 4'b0001, 1'b0, 0);
        if (barrier_waiting_mask[1] != 1'b1 || issuable_wave_mask[3] != 1'b1
            || resident_wave_mask[1] != 1'b1)
            $fatal(1, "staggered wave wait did not retain its actual slot");
        wave_execution_busy[3] = 1'b1;
        barrier_arrive_local_wave_mask = 4'b0010;
        barrier_arrive_valid = 1'b1; #1;
        if (barrier_arrive_ready || barrier_arrive_accepted)
            $fatal(1, "busy wave arrived before its execution became quiescent");
        barrier_arrive_valid = 1'b0; wave_execution_busy[3] = 1'b0;
        arrive(2, 4'b0010, 1'b1, 0);
        if (barrier_release_wave_mask != 4'b1010 || issuable_wave_mask[1] != 1'b1
            || issuable_wave_mask[3] != 1'b1)
            $fatal(1, "barrier release did not wake the exact arbitrary slot set");

        // Retiring one participant lets the already-waiting survivor proceed,
        // while allocator ownership remains until release acceptance.
        arrive(2, 4'b0001, 1'b0, 1);
        @(negedge clk); terminate_wave_slot = 3; terminate_wave_reason = 1;
        terminate_wave_valid = 1; #1;
        if (!terminate_wave_ready || issuable_wave_mask[3])
            $fatal(1, "terminal event did not immediately block the departing wave");
        @(posedge clk); #1; @(negedge clk); terminate_wave_valid = 0;
        if (barrier_release_valid !== 1'b1 || barrier_release_generation != 1
            || barrier_release_wave_mask != 4'b0010 || release_pending_wave_mask[3] != 1'b1
            || resident_wave_mask[3] != 1'b1)
            $fatal(1, "survivor barrier release or deferred slot ownership failed");
        allocator_release_accepted_mask[3] = 1'b1;
        @(posedge clk); #1; @(negedge clk); allocator_release_accepted_mask = 0;
        if (resident_wave_mask[3] || !resident_wave_mask[1])
            $fatal(1, "allocator release completion did not clear only the retired slot");
        @(negedge clk); terminate_wave_slot = 1; terminate_wave_reason = 0;
        terminate_wave_valid = 1; #1;
        @(posedge clk); #1; @(negedge clk); terminate_wave_valid = 0;
        allocator_release_accepted_mask[1] = 1'b1;
        @(posedge clk); #1; @(negedge clk); allocator_release_accepted_mask = 0;
        if (workgroup_active_mask[1] || shared_local_bytes_used != 0)
            $fatal(1, "common workgroup state outlived its final allocator release");
        commit_other_workgroup_state_units = 3;

        // Retiring one participant cannot remove a temporarily busy survivor
        // from the required set for the barrier generation.
        commit_group(8'd4, 3, {2'b0, 2'd2, 2'd1, 2'd0});
        query_workgroup_id = 4;
        arrive(4, 4'b0001, 1'b0, 0);
        wave_execution_busy[1] = 1'b1;
        @(negedge clk); terminate_wave_slot = 2; terminate_wave_reason = 0;
        terminate_wave_valid = 1; #1;
        if (!terminate_wave_ready) $fatal(1, "retirement of another participant was refused");
        @(posedge clk); #1; @(negedge clk); terminate_wave_valid = 0;
        if (barrier_release_valid || query_workgroup_live_waves != 4'b0011
            || query_workgroup_arrived_waves != 4'b0001
            || query_barrier_generation != 0 || !release_pending_wave_mask[2])
            $fatal(1, "retirement dropped a live stalled participant from the barrier set");
        barrier_arrive_workgroup_id = 4;
        barrier_arrive_local_wave_mask = 4'b0010;
        barrier_arrive_valid = 1'b1; #1;
        if (barrier_arrive_ready || barrier_arrive_accepted)
            $fatal(1, "temporarily busy survivor arrived before becoming quiescent");
        @(negedge clk); barrier_arrive_valid = 0; wave_execution_busy[1] = 0;
        arrive(4, 4'b0010, 1'b1, 0);
        if (barrier_release_wave_mask != 4'b0011 || query_barrier_generation != 1)
            $fatal(1, "stalled survivor did not release with the remaining required participant");
        @(negedge clk); terminate_wave_slot = 0; terminate_wave_reason = 0;
        terminate_wave_valid = 1; #1;
        @(posedge clk); #1; @(negedge clk); terminate_wave_valid = 0;
        @(negedge clk); terminate_wave_slot = 1; terminate_wave_reason = 0;
        terminate_wave_valid = 1; #1;
        @(posedge clk); #1; @(negedge clk); terminate_wave_valid = 0;
        allocator_release_accepted_mask = 4'b0111;
        @(posedge clk); #1; @(negedge clk); allocator_release_accepted_mask = 0;
        if (workgroup_active_mask != '0 || resident_wave_mask != '0)
            $fatal(1, "stalled-survivor test workgroup did not release all slots");

        // All participants may arrive in one wave mask and receive the same release.
        commit_group(8'd3, 2, {4'b0, 2'd2, 2'd0});
        query_workgroup_id = 3;
        arrive(3, 4'b0011, 1'b1, 0);
        if (barrier_release_wave_mask != 4'b0101 || issuable_wave_mask[0] != 1'b1
            || issuable_wave_mask[2] != 1'b1)
            $fatal(1, "simultaneous participant arrival did not release all actual slots");
        @(negedge clk); terminate_wave_slot = 0; terminate_wave_reason = 0;
        terminate_wave_valid = 1; #1; @(posedge clk); #1; @(negedge clk); terminate_wave_valid = 0;
        @(negedge clk); terminate_wave_slot = 2; terminate_wave_reason = 0;
        terminate_wave_valid = 1; #1; @(posedge clk); #1; @(negedge clk); terminate_wave_valid = 0;
        allocator_release_accepted_mask = 4'b0101;
        @(posedge clk); #1; @(negedge clk); allocator_release_accepted_mask = 0;
        if (workgroup_active_mask != '0 || resident_wave_mask != '0)
            $fatal(1, "simultaneous-arrival workgroup did not retire cleanly");

        $display("[pass] barrier membership generations, arbitrary slot mapping, busy arrival exclusion, sibling progress, terminal release, and allocator completion checks passed.");
        $finish;
    end
endmodule
