// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_matrix_wave_scoreboard_tb;

    logic clk = 1'b0;
    logic reset_n = 1'b0;

    logic issue_valid;
    logic issue_ready;
    logic issue_legal;
    logic issue_dependency_hazard;
    logic issue_accepted;
    logic [7:0] issue_accepted_d_base;
    logic [7:0] issue_accepted_a_base;
    logic [7:0] issue_accepted_b_base;
    logic illegal_issue;
    logic [3:0] issue_opcode;
    logic issue_full_wave_active;
    logic [7:0] issue_d_base;
    logic [7:0] issue_a_base;
    logic [7:0] issue_b_base;

    logic decode_active;
    logic capture_active;
    logic [2:0] capture_cycle_index;
    logic execute_active;
    logic writeback_active;
    logic rf_read_valid;
    logic [7:0] rf_read_addr0;
    logic [7:0] rf_read_addr1;
    logic rf_write_valid;
    logic [7:0] rf_write_addr;
    logic source_release_valid;
    logic [7:0] source_release_a_base;
    logic [7:0] source_release_b_base;
    logic destination_complete_valid;
    logic [7:0] destination_complete_base;

    logic [255:0] ordinary_read_mask;
    logic [255:0] ordinary_write_mask;
    logic ordinary_uses_read_ports;
    logic ordinary_uses_write_port;
    logic ordinary_raw_hazard;
    logic ordinary_waw_hazard;
    logic ordinary_war_hazard;
    logic ordinary_read_port_conflict;
    logic ordinary_write_port_conflict;
    logic ordinary_ready;
    logic [255:0] source_pending_mask;
    logic [255:0] destination_pending_mask;

    always #5 clk = ~clk;

    cgx1_matrix_pipeline_control control (
        .clk(clk),
        .reset_n(reset_n),
        .issue_valid(issue_valid),
        .issue_wave_slot(1'b0),
        .issue_ready(issue_ready),
        .issue_legal(issue_legal),
        .issue_dependency_hazard(issue_dependency_hazard),
        .issue_accepted(issue_accepted),
        .issue_accepted_d_base(issue_accepted_d_base),
        .issue_accepted_a_base(issue_accepted_a_base),
        .issue_accepted_b_base(issue_accepted_b_base),
        .illegal_issue(illegal_issue),
        .issue_opcode(issue_opcode),
        .issue_full_wave_active(issue_full_wave_active),
        .issue_d_base(issue_d_base),
        .issue_a_base(issue_a_base),
        .issue_b_base(issue_b_base),
        .decode_active(decode_active),
        .capture_active(capture_active),
        .capture_cycle_index(capture_cycle_index),
        .execute_active(execute_active),
        .writeback_active(writeback_active),
        .rf_read_valid(rf_read_valid),
        .rf_read_addr0(rf_read_addr0),
        .rf_read_addr1(rf_read_addr1),
        .rf_write_valid(rf_write_valid),
        .rf_write_addr(rf_write_addr),
        .source_release_valid(source_release_valid),
        .source_release_a_base(source_release_a_base),
        .source_release_b_base(source_release_b_base),
        .destination_complete_valid(destination_complete_valid),
        .destination_complete_base(destination_complete_base)
    );

    cgx1_matrix_wave_scoreboard scoreboard (
        .clk(clk),
        .reset_n(reset_n),
        .matrix_issue_accepted(issue_accepted),
        .matrix_accepted_d_base(issue_accepted_d_base),
        .matrix_accepted_a_base(issue_accepted_a_base),
        .matrix_accepted_b_base(issue_accepted_b_base),
        .matrix_source_release_valid(source_release_valid),
        .matrix_source_release_a_base(source_release_a_base),
        .matrix_source_release_b_base(source_release_b_base),
        .matrix_destination_complete_valid(destination_complete_valid),
        .matrix_destination_complete_base(destination_complete_base),
        .matrix_rf_read_valid(rf_read_valid),
        .matrix_rf_write_valid(rf_write_valid),
        .ordinary_read_mask(ordinary_read_mask),
        .ordinary_write_mask(ordinary_write_mask),
        .ordinary_uses_read_ports(ordinary_uses_read_ports),
        .ordinary_uses_write_port(ordinary_uses_write_port),
        .ordinary_raw_hazard(ordinary_raw_hazard),
        .ordinary_waw_hazard(ordinary_waw_hazard),
        .ordinary_war_hazard(ordinary_war_hazard),
        .ordinary_read_port_conflict(ordinary_read_port_conflict),
        .ordinary_write_port_conflict(ordinary_write_port_conflict),
        .ordinary_ready(ordinary_ready),
        .matrix_source_pending_mask(source_pending_mask),
        .matrix_destination_pending_mask(destination_pending_mask)
    );

    function automatic [255:0] one_register(input integer index);
        reg [255:0] mask;
        begin
            mask = '0;
            mask[index] = 1'b1;
            one_register = mask;
        end
    endfunction

    task automatic clear_ordinary_request;
        begin
            ordinary_read_mask = '0;
            ordinary_write_mask = '0;
            ordinary_uses_read_ports = 1'b0;
            ordinary_uses_write_port = 1'b0;
        end
    endtask

    task automatic reset_dut;
        begin
            reset_n = 1'b0;
            issue_valid = 1'b0;
            issue_opcode = 4'd0;
            issue_full_wave_active = 1'b1;
            issue_d_base = 8'd0;
            issue_a_base = 8'd0;
            issue_b_base = 8'd0;
            clear_ordinary_request();

            repeat (3) @(posedge clk);
            @(negedge clk);
            reset_n = 1'b1;
            @(posedge clk);
            #1;

            if (source_pending_mask !== '0
                || destination_pending_mask !== '0) begin
                $fatal(1, "matrix scoreboard was not empty after reset");
            end
        end
    endtask

    task automatic issue_matrix(
        input logic [7:0] d_base,
        input logic [7:0] a_base,
        input logic [7:0] b_base
    );
        begin
            @(negedge clk);
            issue_opcode = 4'h0;
            issue_d_base = d_base;
            issue_a_base = a_base;
            issue_b_base = b_base;
            issue_full_wave_active = 1'b1;
            issue_valid = 1'b1;
            #1;

            if (!issue_legal) begin
                $fatal(1, "scoreboard integration test matrix issue was not legal");
            end

            while (!issue_ready) begin
                @(negedge clk);
                #1;
            end

            @(posedge clk);
            #1;
            if (!issue_accepted || illegal_issue) begin
                $fatal(1, "scoreboard integration test matrix issue was not accepted");
            end

            if (!source_pending_mask[a_base]
                || !source_pending_mask[b_base]
                || !destination_pending_mask[d_base]) begin
                $fatal(1, "matrix reservation was not visible on acceptance");
            end

            @(negedge clk);
            issue_valid = 1'b0;

            // The producer may change the live issue payload after acceptance.
            // Scoreboard reservation must use the controller-latched bases.
            issue_d_base = 8'd0;
            issue_a_base = 8'd0;
            issue_b_base = 8'd0;

            @(posedge clk);
            #1;
            if (!source_pending_mask[a_base]
                || !source_pending_mask[b_base]
                || !destination_pending_mask[d_base]) begin
                $fatal(1, "matrix scoreboard did not preserve the accepted register bases");
            end
        end
    endtask

    initial begin
        reset_dut();
        issue_matrix(8'd32, 8'd64, 8'd68);

        ordinary_write_mask = one_register(64);
        ordinary_uses_write_port = 1'b1;
        #1;
        if (!ordinary_war_hazard || ordinary_ready) begin
            $fatal(1, "matrix source WAR hazard was not reported");
        end

        clear_ordinary_request();
        ordinary_read_mask = one_register(32);
        ordinary_uses_read_ports = 1'b1;
        #1;
        if (!ordinary_raw_hazard || ordinary_ready) begin
            $fatal(1, "matrix destination RAW hazard was not reported");
        end

        while (!capture_active) begin
            @(posedge clk);
            #1;
        end
        clear_ordinary_request();
        ordinary_read_mask = one_register(80);
        ordinary_uses_read_ports = 1'b1;
        #1;
        if (!ordinary_read_port_conflict || ordinary_ready) begin
            $fatal(1, "matrix capture read-port conflict was not reported");
        end

        clear_ordinary_request();
        ordinary_write_mask = one_register(80);
        ordinary_uses_write_port = 1'b1;
        #1;
        if (ordinary_war_hazard
            || ordinary_waw_hazard
            || ordinary_write_port_conflict
            || !ordinary_ready) begin
            $fatal(1, "unrelated write was incorrectly blocked during capture");
        end

        while (!source_release_valid) begin
            @(posedge clk);
            #1;
        end
        @(posedge clk);
        #1;

        clear_ordinary_request();
        ordinary_write_mask = one_register(64);
        ordinary_uses_write_port = 1'b1;
        #1;
        if (ordinary_war_hazard || !ordinary_ready) begin
            $fatal(1, "matrix source reservation did not clear after capture");
        end

        clear_ordinary_request();
        ordinary_write_mask = one_register(32);
        ordinary_uses_write_port = 1'b1;
        #1;
        if (!ordinary_waw_hazard || ordinary_ready) begin
            $fatal(1, "matrix destination WAW hazard cleared too early");
        end

        while (!writeback_active) begin
            @(posedge clk);
            #1;
        end

        clear_ordinary_request();
        ordinary_write_mask = one_register(80);
        ordinary_uses_write_port = 1'b1;
        #1;
        if (!ordinary_write_port_conflict || ordinary_ready) begin
            $fatal(1, "matrix writeback write-port conflict was not reported");
        end

        clear_ordinary_request();
        ordinary_read_mask = one_register(80);
        ordinary_uses_read_ports = 1'b1;
        #1;
        if (ordinary_read_port_conflict || !ordinary_ready) begin
            $fatal(1, "unrelated read was incorrectly blocked during writeback");
        end

        while (!destination_complete_valid) begin
            @(posedge clk);
            #1;
        end
        @(posedge clk);
        #1;

        clear_ordinary_request();
        ordinary_read_mask = one_register(32);
        ordinary_uses_read_ports = 1'b1;
        #1;
        if (ordinary_raw_hazard || !ordinary_ready) begin
            $fatal(1, "matrix destination reservation did not clear after completion");
        end

        clear_ordinary_request();
        ordinary_write_mask = one_register(32);
        ordinary_uses_write_port = 1'b1;
        #1;
        if (ordinary_waw_hazard || !ordinary_ready) begin
            $fatal(1, "matrix destination write remained blocked after completion");
        end

        $display("[pass] CGX 1 per-wave matrix scoreboard RTL checks passed.");
        $finish;
    end

endmodule
