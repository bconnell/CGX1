// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_wave_control_flow #(
    parameter integer RESIDENT_WAVE_SLOTS = 4,
    parameter integer VIRTUAL_ADDRESS_WIDTH = 57,
    parameter integer CONTROL_STACK_DEPTH = 8,
    parameter integer CALL_STACK_DEPTH = 8,
    parameter integer WAVE_SLOT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS),
    parameter integer CONTROL_TOP_WIDTH = (CONTROL_STACK_DEPTH <= 1) ? 1 : $clog2(CONTROL_STACK_DEPTH + 1),
    parameter integer CALL_TOP_WIDTH = (CALL_STACK_DEPTH <= 1) ? 1 : $clog2(CALL_STACK_DEPTH + 1)
) (
    input logic clk,
    input logic reset_n,
    input logic [RESIDENT_WAVE_SLOTS-1:0] initialize_valid_mask,
    input logic [(RESIDENT_WAVE_SLOTS*VIRTUAL_ADDRESS_WIDTH)-1:0] initialize_pc_flat,
    input logic [(RESIDENT_WAVE_SLOTS*32)-1:0] initialize_live_mask_flat,
    input logic [RESIDENT_WAVE_SLOTS-1:0] clear_mask,
    input logic [RESIDENT_WAVE_SLOTS-1:0] issue_eligible_mask,
    input logic [RESIDENT_WAVE_SLOTS-1:0] advance_valid_mask,
    input logic [(RESIDENT_WAVE_SLOTS*VIRTUAL_ADDRESS_WIDTH)-1:0] advance_sequential_pc_flat,
    input logic control_event_valid,
    input logic [WAVE_SLOT_WIDTH-1:0] control_event_wave_slot,
    input logic [2:0] control_event_kind,
    input logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_event_sequential_pc,
    input logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_event_target_pc,
    input logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_event_fallthrough_pc,
    input logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_event_join_pc,
    input logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_event_return_pc,
    input logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_event_loop_test_pc,
    input logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_event_loop_body_pc,
    input logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_event_loop_exit_pc,
    input logic [31:0] control_event_taken_mask,
    input logic [31:0] control_event_continue_mask,
    output logic control_event_ready,
    output logic control_event_accepted,
    output logic [(RESIDENT_WAVE_SLOTS*VIRTUAL_ADDRESS_WIDTH)-1:0] current_pc_flat,
    output logic [(RESIDENT_WAVE_SLOTS*32)-1:0] live_lane_mask_flat,
    output logic [(RESIDENT_WAVE_SLOTS*32)-1:0] active_lane_mask_flat,
    output logic [RESIDENT_WAVE_SLOTS-1:0] reconverged_mask,
    output logic terminal_valid,
    output logic [WAVE_SLOT_WIDTH-1:0] terminal_wave_slot,
    output logic [3:0] terminal_fault_code,
    input logic terminal_ready
);
    localparam logic [2:0] EVENT_ADVANCE = 3'd0;
    localparam logic [2:0] EVENT_BRANCH = 3'd1;
    localparam logic [2:0] EVENT_CALL = 3'd2;
    localparam logic [2:0] EVENT_RETURN = 3'd3;
    localparam logic [2:0] EVENT_LOOP_BEGIN = 3'd4;
    localparam logic [2:0] EVENT_LOOP_BACKEDGE = 3'd5;
    localparam logic [2:0] EVENT_LOOP_TEST = 3'd6;
    localparam logic [2:0] EVENT_TERMINATE = 3'd7;

    localparam logic [2:0] FRAME_BRANCH = 3'd0;
    localparam logic [2:0] FRAME_LOOP = 3'd1;

    localparam logic [3:0] FAULT_NONE = 4'd0;
    localparam logic [3:0] FAULT_INVALID_PC = 4'd1;
    localparam logic [3:0] FAULT_INVALID_MASK = 4'd2;
    localparam logic [3:0] FAULT_CONTROL_OVERFLOW = 4'd3;
    localparam logic [3:0] FAULT_CALL_OVERFLOW = 4'd4;
    localparam logic [3:0] FAULT_CALL_UNDERFLOW = 4'd5;
    localparam logic [3:0] FAULT_MALFORMED_CONTROL = 4'd6;
    localparam logic [3:0] FAULT_UNBALANCED_CONTROL = 4'd7;
    localparam logic [3:0] FAULT_NO_RUNNABLE_LANES = 4'd8;
    localparam logic [3:0] FAULT_INVALID_EVENT = 4'd9;

    logic [RESIDENT_WAVE_SLOTS-1:0] initialized_q;
    logic [RESIDENT_WAVE_SLOTS-1:0] terminal_pending_q;
    logic [3:0] terminal_code_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [VIRTUAL_ADDRESS_WIDTH-1:0] pc_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [31:0] live_mask_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [31:0] active_mask_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [CONTROL_TOP_WIDTH-1:0] control_top_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [CALL_TOP_WIDTH-1:0] call_top_q [0:RESIDENT_WAVE_SLOTS-1];
    logic [2:0] control_kind_q [0:RESIDENT_WAVE_SLOTS-1][0:CONTROL_STACK_DEPTH-1];
    logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_join_pc_q [0:RESIDENT_WAVE_SLOTS-1][0:CONTROL_STACK_DEPTH-1];
    logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_deferred_pc_q [0:RESIDENT_WAVE_SLOTS-1][0:CONTROL_STACK_DEPTH-1];
    logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_test_pc_q [0:RESIDENT_WAVE_SLOTS-1][0:CONTROL_STACK_DEPTH-1];
    logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_body_pc_q [0:RESIDENT_WAVE_SLOTS-1][0:CONTROL_STACK_DEPTH-1];
    logic [VIRTUAL_ADDRESS_WIDTH-1:0] control_exit_pc_q [0:RESIDENT_WAVE_SLOTS-1][0:CONTROL_STACK_DEPTH-1];
    logic [31:0] control_deferred_mask_q [0:RESIDENT_WAVE_SLOTS-1][0:CONTROL_STACK_DEPTH-1];
    logic [31:0] control_waiting_mask_q [0:RESIDENT_WAVE_SLOTS-1][0:CONTROL_STACK_DEPTH-1];
    logic [31:0] control_member_mask_q [0:RESIDENT_WAVE_SLOTS-1][0:CONTROL_STACK_DEPTH-1];
    logic [CALL_TOP_WIDTH-1:0] control_saved_call_depth_q [0:RESIDENT_WAVE_SLOTS-1][0:CONTROL_STACK_DEPTH-1];
    logic control_deferred_scheduled_q [0:RESIDENT_WAVE_SLOTS-1][0:CONTROL_STACK_DEPTH-1];
    logic [VIRTUAL_ADDRESS_WIDTH-1:0] call_return_pc_q [0:RESIDENT_WAVE_SLOTS-1][0:CALL_STACK_DEPTH-1];

    function automatic logic pc_aligned(input logic [VIRTUAL_ADDRESS_WIDTH-1:0] value);
        pc_aligned = (value[1:0] == 2'b00);
    endfunction

    task automatic clear_slot(input integer slot);
        integer depth;
        begin
            initialized_q[slot] = 1'b0;
            terminal_pending_q[slot] = 1'b0;
            terminal_code_q[slot] = FAULT_NONE;
            pc_q[slot] = '0;
            live_mask_q[slot] = '0;
            active_mask_q[slot] = '0;
            control_top_q[slot] = '0;
            call_top_q[slot] = '0;
            for (depth = 0; depth < CONTROL_STACK_DEPTH; depth = depth + 1) begin
                control_kind_q[slot][depth] = FRAME_BRANCH;
                control_join_pc_q[slot][depth] = '0;
                control_deferred_pc_q[slot][depth] = '0;
                control_test_pc_q[slot][depth] = '0;
                control_body_pc_q[slot][depth] = '0;
                control_exit_pc_q[slot][depth] = '0;
                control_deferred_mask_q[slot][depth] = '0;
                control_waiting_mask_q[slot][depth] = '0;
                control_member_mask_q[slot][depth] = '0;
                control_saved_call_depth_q[slot][depth] = '0;
                control_deferred_scheduled_q[slot][depth] = 1'b0;
            end
            for (depth = 0; depth < CALL_STACK_DEPTH; depth = depth + 1)
                call_return_pc_q[slot][depth] = '0;
        end
    endtask

    task automatic fault_wave(input integer slot, input logic [3:0] code);
        begin
            live_mask_q[slot] = '0;
            active_mask_q[slot] = '0;
            control_top_q[slot] = '0;
            call_top_q[slot] = '0;
            terminal_code_q[slot] = code;
            terminal_pending_q[slot] = 1'b1;
        end
    endtask

    task automatic terminate_wave(input integer slot);
        begin
            live_mask_q[slot] = '0;
            active_mask_q[slot] = '0;
            control_top_q[slot] = '0;
            call_top_q[slot] = '0;
            terminal_code_q[slot] = FAULT_NONE;
            terminal_pending_q[slot] = 1'b1;
        end
    endtask

    task automatic stabilize_wave(input integer slot);
        integer iteration;
        integer top;
        integer saved_call_depth;
        integer scan_index;
        logic [31:0] deferred_mask;
        logic [31:0] waiting_mask;
        logic [31:0] member_mask;
        logic outer_join_match;
        logic done;
        begin
            done = 1'b0;
            for (iteration = 0; iteration < (CONTROL_STACK_DEPTH*3+4); iteration = iteration + 1) begin
                outer_join_match = 1'b0;
                if ($unsigned(control_top_q[slot]) > 1) begin
                    for (scan_index = 0;
                         scan_index < ($unsigned(control_top_q[slot]) - 1);
                         scan_index = scan_index + 1) begin
                        if ((control_kind_q[slot][scan_index] == FRAME_BRANCH)
                            && (control_join_pc_q[slot][scan_index] == pc_q[slot]))
                            outer_join_match = 1'b1;
                    end
                end
                if (!done && initialized_q[slot] && !terminal_pending_q[slot]) begin
                    if ((active_mask_q[slot] & ~live_mask_q[slot]) != 0) begin
                        fault_wave(slot, FAULT_INVALID_MASK);
                        done = 1'b1;
                    end else if (live_mask_q[slot] == 0) begin
                        terminate_wave(slot);
                        done = 1'b1;
                    end else if (active_mask_q[slot] == 0) begin
                        if (control_top_q[slot] == 0) begin
                            fault_wave(slot, FAULT_NO_RUNNABLE_LANES);
                            done = 1'b1;
                        end else begin
                            top = $unsigned(control_top_q[slot]) - 1;
                            deferred_mask = control_deferred_mask_q[slot][top] & live_mask_q[slot];
                            waiting_mask = control_waiting_mask_q[slot][top] & live_mask_q[slot];
                            if (control_kind_q[slot][top] == FRAME_BRANCH) begin
                                saved_call_depth = $unsigned(control_saved_call_depth_q[slot][top]);
                                if ($unsigned(call_top_q[slot]) < saved_call_depth) begin
                                    fault_wave(slot, FAULT_UNBALANCED_CONTROL);
                                    done = 1'b1;
                                end else if (!control_deferred_scheduled_q[slot][top]
                                    && (deferred_mask != 0)) begin
                                    call_top_q[slot] = saved_call_depth[CALL_TOP_WIDTH-1:0];
                                    control_deferred_mask_q[slot][top] = '0;
                                    control_waiting_mask_q[slot][top] = waiting_mask;
                                    control_deferred_scheduled_q[slot][top] = 1'b1;
                                    active_mask_q[slot] = deferred_mask;
                                    pc_q[slot] = control_deferred_pc_q[slot][top];
                                end else begin
                                    call_top_q[slot] = saved_call_depth[CALL_TOP_WIDTH-1:0];
                                    control_top_q[slot] = top[CONTROL_TOP_WIDTH-1:0];
                                    active_mask_q[slot] = waiting_mask;
                                    pc_q[slot] = control_join_pc_q[slot][top];
                                end
                            end else if (waiting_mask != 0) begin
                                saved_call_depth = $unsigned(control_saved_call_depth_q[slot][top]);
                                if ($unsigned(call_top_q[slot]) < saved_call_depth) begin
                                    fault_wave(slot, FAULT_UNBALANCED_CONTROL);
                                    done = 1'b1;
                                end else begin
                                    call_top_q[slot] = saved_call_depth[CALL_TOP_WIDTH-1:0];
                                    control_top_q[slot] = top[CONTROL_TOP_WIDTH-1:0];
                                    active_mask_q[slot] = waiting_mask;
                                    pc_q[slot] = control_exit_pc_q[slot][top];
                                end
                            end else begin
                                member_mask = control_member_mask_q[slot][top] & live_mask_q[slot];
                                if (member_mask == 0) begin
                                    saved_call_depth = $unsigned(control_saved_call_depth_q[slot][top]);
                                    if ($unsigned(call_top_q[slot]) < saved_call_depth) begin
                                        fault_wave(slot, FAULT_UNBALANCED_CONTROL);
                                        done = 1'b1;
                                    end else begin
                                        call_top_q[slot] = saved_call_depth[CALL_TOP_WIDTH-1:0];
                                        control_top_q[slot] = top[CONTROL_TOP_WIDTH-1:0];
                                        pc_q[slot] = control_exit_pc_q[slot][top];
                                    end
                                end else begin
                                    fault_wave(slot, FAULT_NO_RUNNABLE_LANES);
                                    done = 1'b1;
                                end
                            end
                        end
                    end else if ((control_top_q[slot] != 0)
                        && (control_kind_q[slot][$unsigned(control_top_q[slot])-1] == FRAME_BRANCH)
                        && (control_join_pc_q[slot][$unsigned(control_top_q[slot])-1] == pc_q[slot])) begin
                        top = $unsigned(control_top_q[slot]) - 1;
                        saved_call_depth = $unsigned(control_saved_call_depth_q[slot][top]);
                        if ($unsigned(call_top_q[slot]) != saved_call_depth) begin
                            fault_wave(slot, FAULT_UNBALANCED_CONTROL);
                            done = 1'b1;
                        end else if (!control_deferred_scheduled_q[slot][top]) begin
                            deferred_mask = control_deferred_mask_q[slot][top] & live_mask_q[slot];
                            waiting_mask = control_waiting_mask_q[slot][top]
                                | (active_mask_q[slot] & live_mask_q[slot]);
                            control_waiting_mask_q[slot][top] = waiting_mask;
                            if (deferred_mask != 0) begin
                                control_deferred_mask_q[slot][top] = '0;
                                control_deferred_scheduled_q[slot][top] = 1'b1;
                                active_mask_q[slot] = deferred_mask;
                                pc_q[slot] = control_deferred_pc_q[slot][top];
                            end else begin
                                active_mask_q[slot] = waiting_mask;
                                control_top_q[slot] = top[CONTROL_TOP_WIDTH-1:0];
                            end
                        end else begin
                            active_mask_q[slot] = active_mask_q[slot]
                                | (control_waiting_mask_q[slot][top] & live_mask_q[slot]);
                            control_top_q[slot] = top[CONTROL_TOP_WIDTH-1:0];
                        end
                    end else if (outer_join_match) begin
                        fault_wave(slot, FAULT_MALFORMED_CONTROL);
                        done = 1'b1;
                    end else begin
                        done = 1'b1;
                    end
                end
            end
            if (!done && initialized_q[slot] && !terminal_pending_q[slot])
                fault_wave(slot, FAULT_UNBALANCED_CONTROL);
        end
    endtask

    task automatic advance_wave(input integer slot, input logic [VIRTUAL_ADDRESS_WIDTH-1:0] next_pc);
        begin
            if (!pc_aligned(next_pc))
                fault_wave(slot, FAULT_INVALID_PC);
            else begin
                pc_q[slot] = next_pc;
                stabilize_wave(slot);
            end
        end
    endtask

    integer output_slot;
    integer pending_slot;
    always @* begin
        current_pc_flat = '0;
        live_lane_mask_flat = '0;
        active_lane_mask_flat = '0;
        reconverged_mask = '0;
        for (output_slot = 0; output_slot < RESIDENT_WAVE_SLOTS; output_slot = output_slot + 1) begin
            current_pc_flat[(output_slot*VIRTUAL_ADDRESS_WIDTH)+:VIRTUAL_ADDRESS_WIDTH] = pc_q[output_slot];
            live_lane_mask_flat[(output_slot*32)+:32] = live_mask_q[output_slot];
            active_lane_mask_flat[(output_slot*32)+:32] = active_mask_q[output_slot];
            reconverged_mask[output_slot] = initialized_q[output_slot]
                && (live_mask_q[output_slot] != 0)
                && (live_mask_q[output_slot] == active_mask_q[output_slot]);
        end

        control_event_ready = 1'b0;
        control_event_accepted = 1'b0;
        if (control_event_valid && ($unsigned(control_event_wave_slot) < RESIDENT_WAVE_SLOTS)
            && initialized_q[control_event_wave_slot]
            && (live_mask_q[control_event_wave_slot] != 0)
            && (active_mask_q[control_event_wave_slot] != 0)
            && issue_eligible_mask[control_event_wave_slot]
            && !terminal_pending_q[control_event_wave_slot]) begin
            control_event_ready = 1'b1;
            control_event_accepted = 1'b1;
        end

        terminal_valid = 1'b0;
        terminal_wave_slot = '0;
        terminal_fault_code = FAULT_NONE;
        for (pending_slot = RESIDENT_WAVE_SLOTS-1; pending_slot >= 0; pending_slot = pending_slot - 1) begin
            if (terminal_pending_q[pending_slot]) begin
                terminal_valid = 1'b1;
                terminal_wave_slot = pending_slot[WAVE_SLOT_WIDTH-1:0];
                terminal_fault_code = terminal_code_q[pending_slot];
            end
        end
    end

    integer seq_slot;
    integer frame_index;
    integer protected_call_depth;
    logic [31:0] expected_loop_mask;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            initialized_q = '0;
            terminal_pending_q = '0;
            for (seq_slot = 0; seq_slot < RESIDENT_WAVE_SLOTS; seq_slot = seq_slot + 1)
                clear_slot(seq_slot);
        end else begin
            if (terminal_valid && terminal_ready)
                terminal_pending_q[terminal_wave_slot] = 1'b0;

            for (seq_slot = 0; seq_slot < RESIDENT_WAVE_SLOTS; seq_slot = seq_slot + 1) begin
                if (clear_mask[seq_slot])
                    clear_slot(seq_slot);
                else if (initialize_valid_mask[seq_slot]) begin
                    clear_slot(seq_slot);
                    initialized_q[seq_slot] = 1'b1;
                    pc_q[seq_slot] = initialize_pc_flat[(seq_slot*VIRTUAL_ADDRESS_WIDTH)+:VIRTUAL_ADDRESS_WIDTH];
                    live_mask_q[seq_slot] = initialize_live_mask_flat[(seq_slot*32)+:32];
                    active_mask_q[seq_slot] = initialize_live_mask_flat[(seq_slot*32)+:32];
                    if (!pc_aligned(initialize_pc_flat[(seq_slot*VIRTUAL_ADDRESS_WIDTH)+:VIRTUAL_ADDRESS_WIDTH]))
                        fault_wave(seq_slot, FAULT_INVALID_PC);
                    else if (initialize_live_mask_flat[(seq_slot*32)+:32] == 0)
                        fault_wave(seq_slot, FAULT_INVALID_MASK);
                end else if (advance_valid_mask[seq_slot] && initialized_q[seq_slot]
                    && (live_mask_q[seq_slot] != 0) && (active_mask_q[seq_slot] != 0)
                    && !terminal_pending_q[seq_slot]
                    && !(control_event_accepted && (control_event_wave_slot == seq_slot))) begin
                    advance_wave(seq_slot,
                        advance_sequential_pc_flat[(seq_slot*VIRTUAL_ADDRESS_WIDTH)+:VIRTUAL_ADDRESS_WIDTH]);
                end
            end

            if (control_event_accepted) begin
                seq_slot = $unsigned(control_event_wave_slot);
                case (control_event_kind)
                    EVENT_ADVANCE: begin
                        advance_wave(seq_slot, control_event_sequential_pc);
                    end
                    EVENT_BRANCH: begin
                        if (!pc_aligned(control_event_target_pc)
                            || !pc_aligned(control_event_fallthrough_pc)
                            || !pc_aligned(control_event_join_pc))
                            fault_wave(seq_slot, FAULT_INVALID_PC);
                        else if ((control_event_taken_mask & ~active_mask_q[seq_slot]) != 0)
                            fault_wave(seq_slot, FAULT_INVALID_MASK);
                        else if ((control_event_taken_mask == 0)
                            || (control_event_taken_mask == active_mask_q[seq_slot])
                            || (control_event_target_pc == control_event_fallthrough_pc)) begin
                            if (control_event_taken_mask == 0)
                                pc_q[seq_slot] = control_event_fallthrough_pc;
                            else
                                pc_q[seq_slot] = control_event_target_pc;
                            stabilize_wave(seq_slot);
                        end else if ($unsigned(control_top_q[seq_slot]) >= CONTROL_STACK_DEPTH)
                            fault_wave(seq_slot, FAULT_CONTROL_OVERFLOW);
                        else begin
                            frame_index = $unsigned(control_top_q[seq_slot]);
                            control_kind_q[seq_slot][frame_index] = FRAME_BRANCH;
                            control_join_pc_q[seq_slot][frame_index] = control_event_join_pc;
                            control_deferred_pc_q[seq_slot][frame_index] = control_event_fallthrough_pc;
                            control_deferred_mask_q[seq_slot][frame_index] = active_mask_q[seq_slot]
                                & ~control_event_taken_mask;
                            control_waiting_mask_q[seq_slot][frame_index] = '0;
                            control_member_mask_q[seq_slot][frame_index] = '0;
                            control_saved_call_depth_q[seq_slot][frame_index] = call_top_q[seq_slot];
                            control_deferred_scheduled_q[seq_slot][frame_index] = 1'b0;
                            control_top_q[seq_slot] = control_top_q[seq_slot] + 1'b1;
                            active_mask_q[seq_slot] = control_event_taken_mask;
                            pc_q[seq_slot] = control_event_target_pc;
                            stabilize_wave(seq_slot);
                        end
                    end
                    EVENT_CALL: begin
                        if (!pc_aligned(control_event_target_pc) || !pc_aligned(control_event_return_pc))
                            fault_wave(seq_slot, FAULT_INVALID_PC);
                        else if ($unsigned(call_top_q[seq_slot]) >= CALL_STACK_DEPTH)
                            fault_wave(seq_slot, FAULT_CALL_OVERFLOW);
                        else begin
                            call_return_pc_q[seq_slot][$unsigned(call_top_q[seq_slot])] = control_event_return_pc;
                            call_top_q[seq_slot] = call_top_q[seq_slot] + 1'b1;
                            pc_q[seq_slot] = control_event_target_pc;
                        end
                    end
                    EVENT_RETURN: begin
                        if (call_top_q[seq_slot] == 0)
                            fault_wave(seq_slot, FAULT_CALL_UNDERFLOW);
                        else begin
                            protected_call_depth = 0;
                            for (frame_index = 0;
                                 frame_index < $unsigned(control_top_q[seq_slot]);
                                 frame_index = frame_index + 1) begin
                                if ($unsigned(control_saved_call_depth_q[seq_slot][frame_index])
                                    > protected_call_depth)
                                    protected_call_depth = $unsigned(
                                        control_saved_call_depth_q[seq_slot][frame_index]);
                            end
                            if ($unsigned(call_top_q[seq_slot]) <= protected_call_depth)
                                fault_wave(seq_slot, FAULT_UNBALANCED_CONTROL);
                            else begin
                                call_top_q[seq_slot] = call_top_q[seq_slot] - 1'b1;
                                pc_q[seq_slot] = call_return_pc_q[seq_slot][$unsigned(call_top_q[seq_slot])];
                                stabilize_wave(seq_slot);
                            end
                        end
                    end
                    EVENT_LOOP_BEGIN: begin
                        if (!pc_aligned(control_event_loop_test_pc)
                            || !pc_aligned(control_event_loop_body_pc)
                            || !pc_aligned(control_event_loop_exit_pc))
                            fault_wave(seq_slot, FAULT_INVALID_PC);
                        else if (active_mask_q[seq_slot] == 0)
                            fault_wave(seq_slot, FAULT_INVALID_MASK);
                        else if ($unsigned(control_top_q[seq_slot]) >= CONTROL_STACK_DEPTH)
                            fault_wave(seq_slot, FAULT_CONTROL_OVERFLOW);
                        else begin
                            frame_index = $unsigned(control_top_q[seq_slot]);
                            control_kind_q[seq_slot][frame_index] = FRAME_LOOP;
                            control_test_pc_q[seq_slot][frame_index] = control_event_loop_test_pc;
                            control_body_pc_q[seq_slot][frame_index] = control_event_loop_body_pc;
                            control_exit_pc_q[seq_slot][frame_index] = control_event_loop_exit_pc;
                            control_waiting_mask_q[seq_slot][frame_index] = '0;
                            control_member_mask_q[seq_slot][frame_index] = active_mask_q[seq_slot];
                            control_deferred_mask_q[seq_slot][frame_index] = '0;
                            control_saved_call_depth_q[seq_slot][frame_index] = call_top_q[seq_slot];
                            control_deferred_scheduled_q[seq_slot][frame_index] = 1'b0;
                            control_top_q[seq_slot] = control_top_q[seq_slot] + 1'b1;
                            pc_q[seq_slot] = control_event_loop_test_pc;
                        end
                    end
                    EVENT_LOOP_BACKEDGE: begin
                        if ((control_top_q[seq_slot] == 0)
                            || (control_kind_q[seq_slot][$unsigned(control_top_q[seq_slot])-1] != FRAME_LOOP))
                            fault_wave(seq_slot, FAULT_MALFORMED_CONTROL);
                        else if (call_top_q[seq_slot]
                            != control_saved_call_depth_q[seq_slot][$unsigned(control_top_q[seq_slot])-1])
                            fault_wave(seq_slot, FAULT_UNBALANCED_CONTROL);
                        else
                            pc_q[seq_slot] = control_test_pc_q[seq_slot][$unsigned(control_top_q[seq_slot])-1];
                    end
                    EVENT_LOOP_TEST: begin
                        if ((control_top_q[seq_slot] == 0)
                            || (control_kind_q[seq_slot][$unsigned(control_top_q[seq_slot])-1] != FRAME_LOOP))
                            fault_wave(seq_slot, FAULT_MALFORMED_CONTROL);
                        else if (call_top_q[seq_slot]
                            != control_saved_call_depth_q[seq_slot][$unsigned(control_top_q[seq_slot])-1])
                            fault_wave(seq_slot, FAULT_UNBALANCED_CONTROL);
                        else begin
                            frame_index = $unsigned(control_top_q[seq_slot]) - 1;
                            expected_loop_mask = control_member_mask_q[seq_slot][frame_index]
                                & live_mask_q[seq_slot] & ~control_waiting_mask_q[seq_slot][frame_index];
                            if ((active_mask_q[seq_slot] != expected_loop_mask)
                                || ((control_event_continue_mask & ~active_mask_q[seq_slot]) != 0))
                                fault_wave(seq_slot, FAULT_INVALID_MASK);
                            else begin
                                control_waiting_mask_q[seq_slot][frame_index]
                                    = control_waiting_mask_q[seq_slot][frame_index]
                                    | (active_mask_q[seq_slot] & ~control_event_continue_mask);
                                if (control_event_continue_mask != 0) begin
                                    active_mask_q[seq_slot] = control_event_continue_mask;
                                    pc_q[seq_slot] = control_body_pc_q[seq_slot][frame_index];
                                end else begin
                                    active_mask_q[seq_slot] = control_waiting_mask_q[seq_slot][frame_index]
                                        & live_mask_q[seq_slot];
                                    pc_q[seq_slot] = control_exit_pc_q[seq_slot][frame_index];
                                    control_top_q[seq_slot] = frame_index[CONTROL_TOP_WIDTH-1:0];
                                    stabilize_wave(seq_slot);
                                end
                            end
                        end
                    end
                    EVENT_TERMINATE: begin
                        live_mask_q[seq_slot] = live_mask_q[seq_slot] & ~active_mask_q[seq_slot];
                        active_mask_q[seq_slot] = '0;
                        for (frame_index = 0; frame_index < CONTROL_STACK_DEPTH; frame_index = frame_index + 1) begin
                            control_deferred_mask_q[seq_slot][frame_index]
                                = control_deferred_mask_q[seq_slot][frame_index] & live_mask_q[seq_slot];
                            control_waiting_mask_q[seq_slot][frame_index]
                                = control_waiting_mask_q[seq_slot][frame_index] & live_mask_q[seq_slot];
                            control_member_mask_q[seq_slot][frame_index]
                                = control_member_mask_q[seq_slot][frame_index] & live_mask_q[seq_slot];
                        end
                        stabilize_wave(seq_slot);
                    end
                    default: fault_wave(seq_slot, FAULT_INVALID_EVENT);
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (reset_n) begin
            for (integer check_slot = 0; check_slot < RESIDENT_WAVE_SLOTS; check_slot = check_slot + 1) begin
                if ((active_mask_q[check_slot] & ~live_mask_q[check_slot]) != 0)
                    $fatal(1, "wave control active lanes are not a subset of live lanes");
                if ($unsigned(control_top_q[check_slot]) > CONTROL_STACK_DEPTH
                    || $unsigned(call_top_q[check_slot]) > CALL_STACK_DEPTH)
                    $fatal(1, "wave control stack depth exceeded its allocation");
                if (initialized_q[check_slot] && (live_mask_q[check_slot] != 0)
                    && !pc_aligned(pc_q[check_slot]))
                    $fatal(1, "wave control PC is not four-byte aligned");
            end
        end
    end
`endif
endmodule
