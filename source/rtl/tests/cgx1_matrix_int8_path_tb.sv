// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_matrix_int8_path_tb;

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
    logic [4:0] execute_cycle_index;
    logic [3:0] execute_opcode;
    logic writeback_active;
    logic [2:0] writeback_cycle_index;

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

    logic [1023:0] rf_read_data0;
    logic [1023:0] rf_read_data1;
    logic [1023:0] rf_write_data;

    logic active_operands_valid;
    logic arithmetic_result_valid;
    logic result_stage_valid;
    logic result_stage_loaded;
    logic result_stage_consumed;

    logic [1023:0] vgpr [0:255];

    integer reg_index;
    integer lane;
    integer row;
    integer column;
    integer k;
    integer bit_index;
    integer byte_index;
    integer signed expected_value;

    always #5 clk = ~clk;

    assign rf_read_data0 = vgpr[rf_read_addr0];
    assign rf_read_data1 = vgpr[rf_read_addr1];

    always_ff @(posedge clk) begin
        if (reset_n && rf_write_valid) begin
            vgpr[rf_write_addr] <= rf_write_data;
        end
    end

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
        .execute_cycle_index(execute_cycle_index),
        .execute_opcode(execute_opcode),
        .writeback_active(writeback_active),
        .writeback_cycle_index(writeback_cycle_index),
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

    cgx1_matrix_int8_path path (
        .clk(clk),
        .reset_n(reset_n),
        .capture_valid(capture_active),
        .capture_cycle(capture_cycle_index),
        .rf_read_data0(rf_read_data0),
        .rf_read_data1(rf_read_data1),
        .execute_valid(execute_active),
        .execute_cycle(execute_cycle_index),
        .execute_opcode(execute_opcode),
        .writeback_valid(writeback_active),
        .writeback_cycle(writeback_cycle_index),
        .active_operands_valid(active_operands_valid),
        .arithmetic_result_valid(arithmetic_result_valid),
        .result_stage_valid(result_stage_valid),
        .result_stage_loaded(result_stage_loaded),
        .result_stage_consumed(result_stage_consumed),
        .rf_write_data(rf_write_data)
    );

    task automatic set_a(
        input integer in_row,
        input integer in_k,
        input integer signed value
    );
        integer in_lane;
        integer in_reg;
        integer in_byte;
        begin
            in_lane = (in_row * 2) + (in_k / 16);
            in_reg = (in_k % 16) / 4;
            in_byte = (in_k % 16) % 4;
            vgpr[64 + in_reg][(in_lane * 32) + (in_byte * 8) +: 8]
                = value[7:0];
        end
    endtask

    task automatic set_b(
        input integer in_k,
        input integer in_column,
        input integer signed value
    );
        integer in_reg;
        integer in_byte;
        begin
            in_reg = in_column / 4;
            in_byte = in_column % 4;
            vgpr[68 + in_reg][(in_k * 32) + (in_byte * 8) +: 8]
                = value[7:0];
        end
    endtask

    task automatic set_c(
        input integer in_row,
        input integer in_column,
        input integer signed value
    );
        integer in_lane;
        integer in_reg;
        begin
            in_lane = (in_row * 2) + (in_column / 8);
            in_reg = in_column % 8;
            vgpr[32 + in_reg][in_lane * 32 +: 32] = value[31:0];
        end
    endtask

    function automatic signed [31:0] get_d(
        input integer in_row,
        input integer in_column
    );
        integer out_lane;
        integer out_reg;
        begin
            out_lane = (in_row * 2) + (in_column / 8);
            out_reg = in_column % 8;
            get_d = $signed(vgpr[32 + out_reg][out_lane * 32 +: 32]);
        end
    endfunction

    initial begin
        issue_valid = 1'b0;
        issue_opcode = 4'd0;
        issue_full_wave_active = 1'b1;
        issue_d_base = 8'd0;
        issue_a_base = 8'd0;
        issue_b_base = 8'd0;

        for (reg_index = 0; reg_index < 256; reg_index = reg_index + 1) begin
            vgpr[reg_index] = '0;
        end

        for (row = 0; row < 16; row = row + 1) begin
            for (k = 0; k < 32; k = k + 1) begin
                set_a(row, k, ((row + k) % 7) - 3);
            end
        end
        for (k = 0; k < 32; k = k + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                set_b(k, column, ((k + column * 2) % 9) - 4);
            end
        end
        for (row = 0; row < 16; row = row + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                set_c(row, column, (row * 100) + column);
            end
        end

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        @(negedge clk);
        issue_opcode = 4'h6;
        issue_d_base = 8'd32;
        issue_a_base = 8'd64;
        issue_b_base = 8'd68;
        issue_valid = 1'b1;
        #1;

        if (!issue_legal || !issue_ready) begin
            $fatal(1, "matrix INT8 integration issue was not ready and legal");
        end

        @(posedge clk);
        #1;
        if (!issue_accepted || illegal_issue) begin
            $fatal(1, "matrix INT8 integration issue was not accepted");
        end

        @(negedge clk);
        issue_valid = 1'b0;

        while (!destination_complete_valid) begin
            @(posedge clk);
            #1;
        end

        @(posedge clk);
        #1;

        for (row = 0; row < 16; row = row + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                expected_value = (row * 100) + column;
                for (k = 0; k < 32; k = k + 1) begin
                    expected_value =
                        expected_value
                        + ((((row + k) % 7) - 3)
                            * (((k + column * 2) % 9) - 4));
                end

                if (get_d(row, column) !== expected_value[31:0]) begin
                    $fatal(
                        1,
                        "matrix INT8 integrated result mismatch at row %0d column %0d: got %0d expected %0d",
                        row,
                        column,
                        get_d(row, column),
                        expected_value
                    );
                end
            end
        end

        if (result_stage_valid) begin
            $fatal(1, "matrix INT8 result slot remained occupied after writeback");
        end

        $display("[pass] CGX 1 integrated matrix INT8 path checks passed.");
        $finish;
    end

endmodule
