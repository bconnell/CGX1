// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_matrix_int8_execution_tb;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic execute_valid;
    logic [4:0] execute_cycle;
    logic [4095:0] active_a_words;
    logic [4095:0] active_b_words;
    logic [8191:0] active_c_words;
    logic result_valid;
    logic [8191:0] result_words;

    integer row;
    integer column;
    integer k;
    integer cycle;
    integer lane;
    integer reg_index;
    integer byte_index;
    integer bit_index;
    integer signed a_value;
    integer signed b_value;
    integer signed c_value;
    integer signed expected_value;
    logic [31:0] expected_bits;

    always #5 clk = ~clk;

    cgx1_matrix_int8_execution dut (
        .clk(clk),
        .reset_n(reset_n),
        .execute_valid(execute_valid),
        .execute_cycle(execute_cycle),
        .active_a_words(active_a_words),
        .active_b_words(active_b_words),
        .active_c_words(active_c_words),
        .result_valid(result_valid),
        .result_words(result_words)
    );

    task automatic set_a(
        input integer in_row,
        input integer in_k,
        input integer signed value
    );
        begin
            lane = (in_row * 2) + (in_k / 16);
            reg_index = (in_k % 16) / 4;
            byte_index = (in_k % 16) % 4;
            bit_index =
                (reg_index * 1024)
                + (lane * 32)
                + (byte_index * 8);
            active_a_words[bit_index +: 8] = value[7:0];
        end
    endtask

    task automatic set_b(
        input integer in_k,
        input integer in_column,
        input integer signed value
    );
        begin
            lane = in_k;
            reg_index = in_column / 4;
            byte_index = in_column % 4;
            bit_index =
                (reg_index * 1024)
                + (lane * 32)
                + (byte_index * 8);
            active_b_words[bit_index +: 8] = value[7:0];
        end
    endtask

    task automatic set_c(
        input integer in_row,
        input integer in_column,
        input integer signed value
    );
        begin
            lane = (in_row * 2) + (in_column / 8);
            reg_index = in_column % 8;
            bit_index =
                (reg_index * 1024)
                + (lane * 32);
            active_c_words[bit_index +: 32] = value[31:0];
        end
    endtask

    function automatic signed [31:0] get_result(
        input integer in_row,
        input integer in_column
    );
        integer out_lane;
        integer out_reg;
        integer out_bit;
        begin
            out_lane = (in_row * 2) + (in_column / 8);
            out_reg = in_column % 8;
            out_bit = (out_reg * 1024) + (out_lane * 32);
            get_result = $signed(result_words[out_bit +: 32]);
        end
    endfunction

    task automatic run_execution;
        begin
            for (cycle = 0; cycle < 16; cycle = cycle + 1) begin
                @(negedge clk);
                execute_valid = 1'b1;
                execute_cycle = cycle[4:0];

                @(posedge clk);
                #1;
                if ((cycle == 15) != result_valid) begin
                    $fatal(
                        1,
                        "matrix INT8 result-valid timing mismatch at cycle %0d",
                        cycle
                    );
                end
            end

            @(negedge clk);
            execute_valid = 1'b0;
            execute_cycle = 5'd0;
        end
    endtask

    initial begin
        execute_valid = 1'b0;
        execute_cycle = 5'd0;
        active_a_words = '0;
        active_b_words = '0;
        active_c_words = '0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        @(posedge clk);
        #1;

        // Patterned full-tile test exercises every canonical A/B/C/D location.
        for (row = 0; row < 16; row = row + 1) begin
            for (k = 0; k < 32; k = k + 1) begin
                a_value = ((row * 7 + k * 3) % 17) - 8;
                set_a(row, k, a_value);
            end
        end
        for (k = 0; k < 32; k = k + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                b_value = ((k * 5 + column * 11) % 19) - 9;
                set_b(k, column, b_value);
            end
        end
        for (row = 0; row < 16; row = row + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                c_value = (row * 1000) + (column * 13);
                set_c(row, column, c_value);
            end
        end

        run_execution();

        for (row = 0; row < 16; row = row + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                expected_value = (row * 1000) + (column * 13);
                for (k = 0; k < 32; k = k + 1) begin
                    a_value = ((row * 7 + k * 3) % 17) - 8;
                    b_value = ((k * 5 + column * 11) % 19) - 9;
                    expected_value =
                        expected_value + (a_value * b_value);
                end

                if (get_result(row, column) !== expected_value[31:0]) begin
                    $fatal(
                        1,
                        "matrix INT8 result mismatch at row %0d column %0d: got %0d expected %0d",
                        row,
                        column,
                        get_result(row, column),
                        expected_value
                    );
                end
            end
        end

        // Signed extreme-value test.
        active_a_words = '0;
        active_b_words = '0;
        active_c_words = '0;
        for (row = 0; row < 16; row = row + 1) begin
            for (k = 0; k < 32; k = k + 1) begin
                set_a(row, k, -128);
            end
        end
        for (k = 0; k < 32; k = k + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                set_b(k, column, 127);
            end
        end

        run_execution();

        expected_value = -128 * 127 * 32;
        for (row = 0; row < 16; row = row + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                if (get_result(row, column) !== expected_value[31:0]) begin
                    $fatal(
                        1,
                        "matrix INT8 signed-extreme result mismatch at row %0d column %0d",
                        row,
                        column
                    );
                end
            end
        end

        // Explicit modulo-2^32 overflow test.
        active_a_words = '0;
        active_b_words = '0;
        active_c_words = '0;
        for (row = 0; row < 16; row = row + 1) begin
            for (k = 0; k < 32; k = k + 1) begin
                set_a(row, k, 127);
            end
        end
        for (k = 0; k < 32; k = k + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                set_b(k, column, 127);
            end
        end
        for (row = 0; row < 16; row = row + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                set_c(row, column, 32'h7ffff000);
            end
        end

        run_execution();

        expected_bits = 32'h7ffff000;
        for (k = 0; k < 32; k = k + 1) begin
            expected_bits = expected_bits + (127 * 127);
        end
        for (row = 0; row < 16; row = row + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                if ($unsigned(get_result(row, column)) !== expected_bits) begin
                    $fatal(
                        1,
                        "matrix INT8 modulo-overflow mismatch at row %0d column %0d",
                        row,
                        column
                    );
                end
            end
        end

        $display("[pass] CGX 1 matrix INT8 execution RTL checks passed.");
        $finish;
    end

endmodule
