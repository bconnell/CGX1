// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_matrix_pipeline_control_tb;

    logic clk = 1'b0;
    logic reset_n = 1'b0;

    logic issue_valid;
    logic issue_ready;
    logic issue_legal;
    logic issue_dependency_hazard;
    logic issue_accepted;
    logic illegal_issue;
    logic [3:0] issue_opcode;
    logic issue_full_wave_active;
    logic [7:0] issue_d_base;
    logic [7:0] issue_a_base;
    logic [7:0] issue_b_base;

    logic decode_active;
    logic capture_active;
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

    integer accepted_cycles [0:7];
    integer accepted_count;
    integer source_release_count;
    integer destination_complete_count;
    integer sample_cycle;

    always #5 clk = ~clk;

    cgx1_matrix_pipeline_control dut (
        .clk(clk),
        .reset_n(reset_n),
        .issue_valid(issue_valid),
        .issue_ready(issue_ready),
        .issue_legal(issue_legal),
        .issue_dependency_hazard(issue_dependency_hazard),
        .issue_accepted(issue_accepted),
        .illegal_issue(illegal_issue),
        .issue_opcode(issue_opcode),
        .issue_full_wave_active(issue_full_wave_active),
        .issue_d_base(issue_d_base),
        .issue_a_base(issue_a_base),
        .issue_b_base(issue_b_base),
        .decode_active(decode_active),
        .capture_active(capture_active),
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

    always @(negedge clk) begin
        if (!reset_n) begin
            accepted_count = 0;
            source_release_count = 0;
            destination_complete_count = 0;
            sample_cycle = 0;
        end else begin
            if (issue_accepted) begin
                accepted_cycles[accepted_count] = sample_cycle;
                accepted_count = accepted_count + 1;
            end

            if (source_release_valid) begin
                source_release_count = source_release_count + 1;
            end

            if (destination_complete_valid) begin
                destination_complete_count = destination_complete_count + 1;
            end

            if (rf_read_valid && rf_write_valid) begin
                $fatal(1, "RTL exposed simultaneous matrix VGPR read/write");
            end

            if (rf_read_valid
                && (rf_read_addr0 != rf_read_addr1)
                && (rf_read_addr0[2:0] == rf_read_addr1[2:0])) begin
                $fatal(1, "RTL exposed a matrix register bank-class conflict");
            end

            sample_cycle = sample_cycle + 1;
        end
    end

    task automatic reset_dut;
        begin
            reset_n = 1'b0;
            issue_valid = 1'b0;
            issue_opcode = 4'd0;
            issue_full_wave_active = 1'b1;
            issue_d_base = 8'd0;
            issue_a_base = 8'd0;
            issue_b_base = 8'd0;

            repeat (3) @(posedge clk);
            @(negedge clk);
            #1;
            reset_n = 1'b1;
            @(posedge clk);
            #1;
            if (!issue_ready) begin
                $fatal(1, "issue path not ready after reset");
            end
        end
    endtask

    task automatic issue_legal_op (
        input logic [3:0] opcode,
        input logic [7:0] d_base,
        input logic [7:0] a_base,
        input logic [7:0] b_base
    );
        begin
            @(negedge clk);

            // Ready is allowed to depend on the presented register payload
            // because pending-destination hazards are instruction-specific.
            issue_opcode = opcode;
            issue_d_base = d_base;
            issue_a_base = a_base;
            issue_b_base = b_base;
            issue_full_wave_active = 1'b1;
            issue_valid = 1'b1;

            #1;
            if (!issue_legal) begin
                $fatal(1, "legal matrix issue was rejected");
            end

            while (!issue_ready) begin
                @(negedge clk);
                #1;
                if (!issue_legal) begin
                    $fatal(1, "legal matrix issue became statically illegal while stalled");
                end
            end

            @(posedge clk);
            #1;
            if (!issue_accepted || illegal_issue) begin
                $fatal(1, "legal matrix issue was not accepted cleanly");
            end

            @(negedge clk);
            issue_valid = 1'b0;
        end
    endtask

    task automatic check_single_operation;
        integer i;
        logic [7:0] expected0;
        logic [7:0] expected1;
        begin
            reset_dut();
            issue_legal_op(4'h0, 8'd32, 8'd64, 8'd68);

            if (!decode_active) begin
                $fatal(1, "decode stage was not active after issue");
            end

            for (i = 0; i < 8; i = i + 1) begin
                @(posedge clk);
                #1;

                if (!capture_active || !rf_read_valid || rf_write_valid) begin
                    $fatal(1, "capture stage timing mismatch at cycle %0d", i);
                end

                if (i < 4) begin
                    expected0 = 8'd64 + i;
                    expected1 = 8'd68 + i;
                end else begin
                    expected0 = 8'd32 + ((i - 4) * 2);
                    expected1 = expected0 + 1;
                end

                if (rf_read_addr0 !== expected0 || rf_read_addr1 !== expected1) begin
                    $fatal(
                        1,
                        "capture addresses mismatch at cycle %0d: got %0d/%0d expected %0d/%0d",
                        i,
                        rf_read_addr0,
                        rf_read_addr1,
                        expected0,
                        expected1
                    );
                end

                if ((i == 7) != source_release_valid) begin
                    $fatal(1, "source release timing mismatch");
                end
            end

            for (i = 0; i < 16; i = i + 1) begin
                @(posedge clk);
                #1;
                if (!execute_active || rf_read_valid || rf_write_valid) begin
                    $fatal(1, "execute stage timing mismatch at cycle %0d", i);
                end
            end

            for (i = 0; i < 8; i = i + 1) begin
                @(posedge clk);
                #1;

                if (!writeback_active || rf_read_valid || !rf_write_valid) begin
                    $fatal(1, "writeback stage timing mismatch at cycle %0d", i);
                end

                if (rf_write_addr !== (8'd32 + i)) begin
                    $fatal(1, "writeback address mismatch at cycle %0d", i);
                end

                if ((i == 7) != destination_complete_valid) begin
                    $fatal(1, "destination completion timing mismatch");
                end
            end

            @(posedge clk);
            #1;
            if (decode_active || capture_active || execute_active || writeback_active) begin
                $fatal(1, "pipeline did not return to idle");
            end
        end
    endtask

    task automatic check_invalid_issue;
        begin
            reset_dut();

            @(negedge clk);
            issue_valid = 1'b1;
            issue_opcode = 4'h0;
            issue_full_wave_active = 1'b1;
            issue_d_base = 8'd32;
            issue_a_base = 8'd68;
            issue_b_base = 8'd72;

            #1;
            if (issue_legal) begin
                $fatal(1, "invalid A bank class was accepted");
            end

            @(posedge clk);
            #1;
            if (!illegal_issue || issue_accepted) begin
                $fatal(1, "invalid matrix issue did not raise the expected pulse");
            end

            @(negedge clk);
            issue_valid = 1'b0;
        end
    endtask

    task automatic check_pending_destination_hazard (
        input logic [7:0] dependent_d_base,
        input logic [7:0] dependent_a_base,
        input logic [7:0] dependent_b_base
    );
        integer stall_cycles;
        begin
            reset_dut();
            issue_legal_op(4'h0, 8'd32, 8'd64, 8'd68);

            // Wait beyond the 16-cycle reissue interval while the older
            // destination is still pending.
            repeat (16) @(posedge clk);
            @(negedge clk);

            issue_opcode = 4'h1;
            issue_d_base = dependent_d_base;
            issue_a_base = dependent_a_base;
            issue_b_base = dependent_b_base;
            issue_full_wave_active = 1'b1;
            issue_valid = 1'b1;

            #1;
            if (!issue_legal) begin
                $fatal(1, "dependency test instruction was not statically legal");
            end
            if (!issue_dependency_hazard || issue_ready) begin
                $fatal(1, "pending destination dependency did not stall matrix issue");
            end

            stall_cycles = 0;
            while (issue_dependency_hazard) begin
                @(posedge clk);
                #1;
                if (issue_accepted || illegal_issue) begin
                    $fatal(1, "dependent matrix instruction was accepted or rejected while stalled");
                end
                @(negedge clk);
                stall_cycles = stall_cycles + 1;
                if (stall_cycles > 40) begin
                    $fatal(1, "pending destination dependency failed to clear");
                end
            end

            #1;
            if (!issue_ready) begin
                $fatal(1, "matrix issue did not become ready after destination completion");
            end

            @(posedge clk);
            #1;
            if (!issue_accepted || illegal_issue) begin
                $fatal(1, "dependent matrix instruction was not accepted after hazard clearance");
            end

            @(negedge clk);
            issue_valid = 1'b0;
        end
    endtask

    task automatic check_steady_state;
        integer i;
        begin
            reset_dut();

            issue_legal_op(4'h0, 8'd32, 8'd64, 8'd68);
            issue_legal_op(4'h1, 8'd40, 8'd80, 8'd84);
            issue_legal_op(4'h6, 8'd48, 8'd96, 8'd100);

            @(negedge clk);

            if (accepted_count != 3) begin
                $fatal(1, "expected three accepted matrix operations, got %0d", accepted_count);
            end

            if ((accepted_cycles[1] - accepted_cycles[0]) != 16
                || (accepted_cycles[2] - accepted_cycles[1]) != 16) begin
                $fatal(
                    1,
                    "matrix issue interval mismatch: %0d %0d %0d",
                    accepted_cycles[0],
                    accepted_cycles[1],
                    accepted_cycles[2]
                );
            end

            repeat (40) @(posedge clk);
            @(negedge clk);

            if (source_release_count != 3) begin
                $fatal(1, "expected three source-release events, got %0d", source_release_count);
            end

            if (destination_complete_count != 3) begin
                $fatal(
                    1,
                    "expected three destination-complete events, got %0d",
                    destination_complete_count
                );
            end

            for (i = 0; i < accepted_count; i = i + 1) begin
                if (accepted_cycles[i] < 0) begin
                    $fatal(1, "invalid accepted-cycle record");
                end
            end
        end
    endtask

    initial begin
        issue_valid = 1'b0;
        issue_opcode = 4'd0;
        issue_full_wave_active = 1'b1;
        issue_d_base = 8'd0;
        issue_a_base = 8'd0;
        issue_b_base = 8'd0;

        check_invalid_issue();
        check_single_operation();
        check_pending_destination_hazard(8'd48, 8'd32, 8'd84); // RAW through A
        check_pending_destination_hazard(8'd48, 8'd80, 8'd36); // RAW through B
        check_pending_destination_hazard(8'd32, 8'd80, 8'd84); // WAW / tied C-D
        check_steady_state();

        $display("[pass] CGX 1 matrix pipeline control RTL checks passed.");
        $finish;
    end

endmodule
