// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_wave_control_flow_tb;
    localparam integer SLOTS = 2;
    localparam integer VA_WIDTH = 57;
    localparam integer CONTROL_DEPTH = 4;
    localparam integer CALL_DEPTH = 3;
    localparam integer SLOT_WIDTH = 1;
    localparam logic [2:0] EVENT_ADVANCE = 3'd0;
    localparam logic [2:0] EVENT_BRANCH = 3'd1;
    localparam logic [2:0] EVENT_CALL = 3'd2;
    localparam logic [2:0] EVENT_RETURN = 3'd3;
    localparam logic [2:0] EVENT_LOOP_BEGIN = 3'd4;
    localparam logic [2:0] EVENT_LOOP_BACKEDGE = 3'd5;
    localparam logic [2:0] EVENT_LOOP_TEST = 3'd6;
    localparam logic [2:0] EVENT_TERMINATE = 3'd7;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic [SLOTS-1:0] initialize_valid_mask = '0;
    logic [(SLOTS*VA_WIDTH)-1:0] initialize_pc_flat = '0;
    logic [(SLOTS*32)-1:0] initialize_live_mask_flat = '0;
    logic [SLOTS-1:0] clear_mask = '0;
    logic [SLOTS-1:0] issue_eligible_mask = '0;
    logic [SLOTS-1:0] advance_valid_mask = '0;
    logic [(SLOTS*VA_WIDTH)-1:0] advance_sequential_pc_flat = '0;
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
    logic [(SLOTS*VA_WIDTH)-1:0] current_pc_flat;
    logic [(SLOTS*32)-1:0] live_lane_mask_flat, active_lane_mask_flat;
    logic [SLOTS-1:0] reconverged_mask;
    logic terminal_valid;
    logic [SLOT_WIDTH-1:0] terminal_wave_slot;
    logic [3:0] terminal_fault_code;
    logic terminal_ready = 1'b0;
    logic [31:0] trace_lfsr;
    logic [31:0] trace_taken_mask;
    integer trace_index;

    always #5 clk = ~clk;

    cgx1_wave_control_flow #(
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .VIRTUAL_ADDRESS_WIDTH(VA_WIDTH),
        .CONTROL_STACK_DEPTH(CONTROL_DEPTH),
        .CALL_STACK_DEPTH(CALL_DEPTH)
    ) dut(.*);

    task automatic initialize_slot(input integer slot, input logic [VA_WIDTH-1:0] pc,
                                   input logic [31:0] lane_mask);
    begin
        @(negedge clk);
        initialize_pc_flat[(slot*VA_WIDTH)+:VA_WIDTH] = pc;
        initialize_live_mask_flat[(slot*32)+:32] = lane_mask;
        initialize_valid_mask[slot] = 1'b1;
        @(posedge clk); #1; @(negedge clk);
        initialize_valid_mask[slot] = 1'b0;
        issue_eligible_mask[slot] = 1'b1;
    end
    endtask

    task automatic send_branch(input integer slot, input logic [31:0] taken,
                               input logic [VA_WIDTH-1:0] target_pc,
                               input logic [VA_WIDTH-1:0] fallthrough_pc,
                               input logic [VA_WIDTH-1:0] join_pc);
    begin
        @(negedge clk);
        control_event_wave_slot = slot[SLOT_WIDTH-1:0];
        control_event_kind = EVENT_BRANCH;
        control_event_taken_mask = taken;
        control_event_target_pc = target_pc;
        control_event_fallthrough_pc = fallthrough_pc;
        control_event_join_pc = join_pc;
        control_event_valid = 1'b1;
        #1;
        if (!control_event_ready || !control_event_accepted)
            $fatal(1, "decoded branch event was not accepted");
        @(posedge clk); #1; @(negedge clk);
        control_event_valid = 1'b0;
    end
    endtask

    task automatic send_event(input integer slot, input logic [2:0] kind);
    begin
        @(negedge clk);
        control_event_wave_slot = slot[SLOT_WIDTH-1:0];
        control_event_kind = kind;
        control_event_valid = 1'b1;
        #1;
        if (!control_event_ready || !control_event_accepted)
            $fatal(1, "decoded control event %0d was not accepted", kind);
        @(posedge clk); #1; @(negedge clk);
        control_event_valid = 1'b0;
    end
    endtask

    task automatic advance_slot(input integer slot, input logic [VA_WIDTH-1:0] next_pc);
    begin
        @(negedge clk);
        advance_sequential_pc_flat[(slot*VA_WIDTH)+:VA_WIDTH] = next_pc;
        advance_valid_mask[slot] = 1'b1;
        @(posedge clk); #1; @(negedge clk);
        advance_valid_mask[slot] = 1'b0;
    end
    endtask

    task automatic send_call(input integer slot, input logic [VA_WIDTH-1:0] target_pc,
                             input logic [VA_WIDTH-1:0] return_pc);
    begin
        @(negedge clk);
        control_event_wave_slot = slot[SLOT_WIDTH-1:0];
        control_event_kind = EVENT_CALL;
        control_event_target_pc = target_pc;
        control_event_return_pc = return_pc;
        control_event_valid = 1'b1;
        #1;
        if (!control_event_ready || !control_event_accepted)
            $fatal(1, "call event was not accepted");
        @(posedge clk); #1; @(negedge clk);
        control_event_valid = 1'b0;
    end
    endtask

    task automatic send_loop_begin(input integer slot,
                                   input logic [VA_WIDTH-1:0] test_pc,
                                   input logic [VA_WIDTH-1:0] body_pc,
                                   input logic [VA_WIDTH-1:0] exit_pc);
    begin
        @(negedge clk);
        control_event_wave_slot = slot[SLOT_WIDTH-1:0];
        control_event_kind = EVENT_LOOP_BEGIN;
        control_event_loop_test_pc = test_pc;
        control_event_loop_body_pc = body_pc;
        control_event_loop_exit_pc = exit_pc;
        control_event_valid = 1'b1;
        #1;
        if (!control_event_ready || !control_event_accepted)
            $fatal(1, "loop begin event was not accepted");
        @(posedge clk); #1; @(negedge clk);
        control_event_valid = 1'b0;
    end
    endtask

    task automatic send_loop_test(input integer slot, input logic [31:0] continue_mask);
    begin
        @(negedge clk);
        control_event_wave_slot = slot[SLOT_WIDTH-1:0];
        control_event_kind = EVENT_LOOP_TEST;
        control_event_continue_mask = continue_mask;
        control_event_valid = 1'b1;
        #1;
        if (!control_event_ready || !control_event_accepted)
            $fatal(1, "loop test event was not accepted");
        @(posedge clk); #1; @(negedge clk);
        control_event_valid = 1'b0;
    end
    endtask

    task automatic cold_reset;
    begin
        reset_n = 1'b0; #1;
        reset_n = 1'b1;
        repeat (2) @(posedge clk);
    end
    endtask

    task automatic expect_fault(input logic [3:0] expected_code);
    begin
        #1;
        if (!terminal_valid || terminal_fault_code != expected_code)
            $fatal(1, "expected control fault %0d, valid=%b code=%0d",
                expected_code, terminal_valid, terminal_fault_code);
    end
    endtask

    initial begin
        #2; reset_n = 1'b1;
        repeat (2) @(posedge clk);

        initialize_slot(0, 57'h1000, 32'h0000000f);
        initialize_slot(1, 57'h80000001000, 32'h00000003);

        // A uniform branch redirects without using a divergence frame.
        @(negedge clk);
        control_event_wave_slot = 0;
        control_event_kind = EVENT_BRANCH;
        control_event_taken_mask = 32'hf;
        control_event_target_pc = 57'h2000;
        control_event_fallthrough_pc = 57'h2010;
        control_event_join_pc = 57'h2020;
        control_event_valid = 1;
        #1; if (!control_event_ready) $fatal(1, "uniform branch stalled");
        @(posedge clk); #1; @(negedge clk); control_event_valid = 0;
        if (current_pc_flat[0+:VA_WIDTH] != 57'h2000 || !reconverged_mask[0])
            $fatal(1, "uniform branch did not redirect its PC");
        advance_slot(0, 57'h2004);
        if (current_pc_flat[0+:VA_WIDTH] != 57'h2004)
            $fatal(1, "accepted sequential instruction did not advance the wave PC");

        // Backpressure leaves control state unchanged until the event is accepted.
        issue_eligible_mask[0] = 0;
        control_event_wave_slot = 0; control_event_kind = EVENT_BRANCH;
        control_event_taken_mask = 32'h3; control_event_target_pc = 57'h3000;
        control_event_fallthrough_pc = 57'h3010; control_event_join_pc = 57'h4000;
        control_event_valid = 1; #1;
        if (control_event_ready || control_event_accepted
            || current_pc_flat[0+:VA_WIDTH] != 57'h2004
            || active_lane_mask_flat[0+:32] != 32'hf)
            $fatal(1, "backpressured control event changed per-wave state");
        issue_eligible_mask[0] = 1;
        #1; if (!control_event_ready) $fatal(1, "control event did not resume after backpressure");
        @(posedge clk); #1; @(negedge clk); control_event_valid = 0;
        if (current_pc_flat[0+:VA_WIDTH] != 57'h3000
            || active_lane_mask_flat[0+:32] != 32'h3 || reconverged_mask[0])
            $fatal(1, "divergent branch did not select its first path");

        // A different wave advances while slot zero is divergent.
        advance_slot(1, 57'h80000001004);
        if (current_pc_flat[VA_WIDTH+:VA_WIDTH] != 57'h80000001004
            || active_lane_mask_flat[32+:32] != 32'h3)
            $fatal(1, "independent resident wave did not advance");

        // First path waits at the join; deferred path runs, then both merge.
        advance_slot(0, 57'h4000);
        if (current_pc_flat[0+:VA_WIDTH] != 57'h3010
            || active_lane_mask_flat[0+:32] != 32'hc
            || live_lane_mask_flat[0+:32] != 32'hf)
            $fatal(1, "first branch path did not defer at its join");
        advance_slot(0, 57'h4000);
        if (current_pc_flat[0+:VA_WIDTH] != 57'h4000
            || active_lane_mask_flat[0+:32] != 32'hf || !reconverged_mask[0])
            $fatal(1, "branch paths did not reconverge");

        // Nested branches may reconverge at distinct joins before the outer join.
        send_branch(0, 32'h3, 57'h5000, 57'h6000, 57'h7000);
        send_branch(0, 32'h1, 57'h5010, 57'h5020, 57'h5030);
        advance_slot(0, 57'h5030);
        if (active_lane_mask_flat[0+:32] != 32'h2 || current_pc_flat[0+:VA_WIDTH] != 57'h5020)
            $fatal(1, "inner branch did not schedule its deferred path");
        advance_slot(0, 57'h5030);
        if (active_lane_mask_flat[0+:32] != 32'h3 || current_pc_flat[0+:VA_WIDTH] != 57'h5030)
            $fatal(1, "inner branch did not reconverge before the outer path");
        advance_slot(0, 57'h7000);
        if (active_lane_mask_flat[0+:32] != 32'hc || current_pc_flat[0+:VA_WIDTH] != 57'h6000)
            $fatal(1, "outer branch did not schedule after the inner join");
        advance_slot(0, 57'h7000);
        if (active_lane_mask_flat[0+:32] != 32'hf || current_pc_flat[0+:VA_WIDTH] != 57'h7000)
            $fatal(1, "outer branch did not reconverge after the nested join");

        // Calls preserve full virtual PCs and returns pop the saved PC.
        @(negedge clk);
        control_event_wave_slot = 0; control_event_kind = EVENT_CALL;
        control_event_target_pc = 57'h100000012000;
        control_event_return_pc = 57'h4010;
        control_event_valid = 1;
        @(posedge clk); #1; @(negedge clk); control_event_valid = 0;
        if (current_pc_flat[0+:VA_WIDTH] != 57'h100000012000)
            $fatal(1, "call lost the high virtual PC bits");
        send_event(0, EVENT_RETURN);
        if (current_pc_flat[0+:VA_WIDTH] != 57'h4010)
            $fatal(1, "return did not restore the saved PC");

        // Loop lanes leave on different iterations and resume at one exit PC.
        @(negedge clk);
        control_event_wave_slot = 0; control_event_kind = EVENT_LOOP_BEGIN;
        control_event_loop_test_pc = 57'h4020;
        control_event_loop_body_pc = 57'h4024;
        control_event_loop_exit_pc = 57'h4030;
        control_event_valid = 1;
        @(posedge clk); #1; @(negedge clk); control_event_valid = 0;
        control_event_kind = EVENT_LOOP_TEST; control_event_continue_mask = 32'he;
        control_event_valid = 1; @(posedge clk); #1; @(negedge clk); control_event_valid = 0;
        if (active_lane_mask_flat[0+:32] != 32'he)
            $fatal(1, "loop test did not defer lanes that exit first");
        send_event(0, EVENT_LOOP_BACKEDGE);
        control_event_kind = EVENT_LOOP_TEST; control_event_continue_mask = 32'hc;
        control_event_valid = 1; @(posedge clk); #1; @(negedge clk); control_event_valid = 0;
        if (active_lane_mask_flat[0+:32] != 32'hc)
            $fatal(1, "second loop iteration lost its continuing lanes");
        send_event(0, EVENT_LOOP_BACKEDGE);
        control_event_kind = EVENT_LOOP_TEST; control_event_continue_mask = 0;
        control_event_valid = 1; @(posedge clk); #1; @(negedge clk); control_event_valid = 0;
        if (current_pc_flat[0+:VA_WIDTH] != 57'h4030
            || active_lane_mask_flat[0+:32] != 32'hf || !reconverged_mask[0])
            $fatal(1, "loop exits did not merge at the exit PC");

        // Terminating active lanes never resurrects them at a join.
        send_branch(0, 32'h3, 57'h5000, 57'h5010, 57'h5020);
        send_event(0, EVENT_TERMINATE);
        if (live_lane_mask_flat[0+:32] != 32'hc || active_lane_mask_flat[0+:32] != 32'hc)
            $fatal(1, "lane termination did not schedule only surviving deferred lanes");
        advance_slot(0, 57'h5020);
        if (live_lane_mask_flat[0+:32] != 32'hc || active_lane_mask_flat[0+:32] != 32'hc)
            $fatal(1, "terminated lanes were restored by branch reconvergence");

        // Invalid input faults one wave and retains an identity until terminal acceptance.
        @(negedge clk);
        control_event_wave_slot = 1; control_event_kind = EVENT_BRANCH;
        control_event_taken_mask = 32'h1; control_event_target_pc = 57'h9001;
        control_event_fallthrough_pc = 57'h9004; control_event_join_pc = 57'h9008;
        control_event_valid = 1;
        @(posedge clk); #1; @(negedge clk); control_event_valid = 0;
        if (live_lane_mask_flat[32+:32] != 0 || !terminal_valid
            || terminal_wave_slot != 1 || terminal_fault_code == 0)
            $fatal(1, "invalid control PC did not fault and retire its wave");
        terminal_ready = 1; @(posedge clk); #1; @(negedge clk); terminal_ready = 0;

        // Reset with branch state present clears masks, stack state, and terminal state.
        send_branch(0, 32'h4, 57'h6000, 57'h6010, 57'h6020);
        reset_n = 0; #1;
        if (live_lane_mask_flat != '0 || active_lane_mask_flat != '0 || terminal_valid)
            $fatal(1, "reset retained wave-control or terminal state");
        #4; reset_n = 1; repeat (2) @(posedge clk);

        // An enclosing branch join cannot be reached with an inner loop open.
        initialize_slot(0, 57'h1000, 32'hf);
        send_branch(0, 32'h3, 57'h2000, 57'h3000, 57'h4000);
        send_loop_begin(0, 57'h2010, 57'h2020, 57'h2040);
        advance_slot(0, 57'h4000);
        expect_fault(4'd6);

        // A terminated loop path cannot leak its deeper call stack to survivors.
        cold_reset();
        initialize_slot(0, 57'h1000, 32'hf);
        send_call(0, 57'h2000, 57'h1010);
        send_loop_begin(0, 57'h2010, 57'h2020, 57'h2040);
        send_loop_test(0, 32'he);
        send_call(0, 57'h3000, 57'h2030);
        send_event(0, EVENT_TERMINATE);
        if (active_lane_mask_flat[0+:32] != 32'h1 || current_pc_flat[0+:VA_WIDTH] != 57'h2040)
            $fatal(1, "loop exit did not resume surviving lanes");
        send_event(0, EVENT_RETURN);
        if (current_pc_flat[0+:VA_WIDTH] != 57'h1010)
            $fatal(1, "loop unwind retained a terminated path's return address");

        // Calls cannot return below the checkpoint of a live divergent frame.
        cold_reset();
        initialize_slot(0, 57'h1000, 32'hf);
        send_call(0, 57'h2000, 57'h1010);
        send_branch(0, 32'h3, 57'h2010, 57'h2020, 57'h2030);
        send_event(0, EVENT_RETURN);
        expect_fault(4'd7);

        // Loop tests/backedges must return to the call depth captured at entry.
        cold_reset();
        initialize_slot(0, 57'h1000, 32'hf);
        send_loop_begin(0, 57'h1010, 57'h1020, 57'h1030);
        send_call(0, 57'h2000, 57'h1024);
        send_event(0, EVENT_LOOP_BACKEDGE);
        expect_fault(4'd7);

        // RTL malformed input, stack limits, and seeded transition trace.
        cold_reset();
        initialize_slot(0, 57'h1000, 32'hf);
        send_branch(0, 32'h10, 57'h2000, 57'h2010, 57'h2020);
        expect_fault(4'd2);
        cold_reset();
        initialize_slot(0, 57'h1000, 32'hf);
        send_event(0, EVENT_RETURN);
        expect_fault(4'd5);
        cold_reset();
        initialize_slot(0, 57'h1000, 32'hff);
        send_branch(0, 32'h7f, 57'h2000, 57'h2100, 57'h2200);
        send_branch(0, 32'h3f, 57'h2010, 57'h2110, 57'h2210);
        send_branch(0, 32'h1f, 57'h2020, 57'h2120, 57'h2220);
        send_branch(0, 32'h0f, 57'h2030, 57'h2130, 57'h2230);
        send_branch(0, 32'h07, 57'h2040, 57'h2140, 57'h2240);
        expect_fault(4'd3);
        cold_reset();
        initialize_slot(0, 57'h1000, 32'hf);
        send_call(0, 57'h2000, 57'h1010);
        send_call(0, 57'h3000, 57'h2010);
        send_call(0, 57'h4000, 57'h3010);
        send_call(0, 57'h5000, 57'h4010);
        expect_fault(4'd4);
        cold_reset();
        initialize_slot(0, 57'h8000, 32'hf);
        trace_lfsr = 32'hc61f10a5;
        for (trace_index = 0; trace_index < 32; trace_index = trace_index + 1) begin
            trace_lfsr = {trace_lfsr[30:0], trace_lfsr[31] ^ trace_lfsr[21]
                ^ trace_lfsr[1] ^ trace_lfsr[0]};
            trace_taken_mask = trace_lfsr[3:0];
            if ((trace_taken_mask == 0) || (trace_taken_mask == 32'hf))
                trace_taken_mask = trace_taken_mask ^ 32'h1;
            send_branch(0, trace_taken_mask, 57'h9000 + (trace_index * 32),
                57'h9004 + (trace_index * 32), 57'h9008 + (trace_index * 32));
            advance_slot(0, 57'h9008 + (trace_index * 32));
            advance_slot(0, 57'h9008 + (trace_index * 32));
            if (active_lane_mask_flat[0+:32] != 32'hf || !reconverged_mask[0])
                $fatal(1, "seeded control trace failed to restore all live lanes at join %0d", trace_index);
        end

        $display("[pass] decoded per-wave control-flow state and RTL queue checks passed.");
        $finish;
    end
endmodule
