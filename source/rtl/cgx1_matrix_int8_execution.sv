// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Signed INT8 matrix arithmetic only. Floating-point matrix arithmetic is separate work.

module cgx1_matrix_int8_execution (
    input  logic          clk,
    input  logic          reset_n,

    input  logic          execute_valid,
    input  logic [4:0]    execute_cycle,
    input  logic [4095:0] active_a_words,
    input  logic [4095:0] active_b_words,
    input  logic [8191:0] active_c_words,

    output logic          result_valid,
    output logic [8191:0] result_words
);

    logic [31:0] even_acc_q [0:255];
    logic [31:0] odd_acc_q [0:255];

`ifndef SYNTHESIS
    logic       execution_active_q;
    logic [4:0] expected_cycle_q;
`endif

    function automatic signed [7:0] a_element (
        input logic [4095:0] words,
        input integer row,
        input integer k
    );
        integer lane;
        integer element;
        integer reg_index;
        integer byte_index;
        integer bit_index;
        begin
            lane = (row * 2) + (k / 16);
            element = k % 16;
            reg_index = element / 4;
            byte_index = element % 4;
            bit_index =
                (reg_index * 1024)
                + (lane * 32)
                + (byte_index * 8);
            a_element = $signed(words[bit_index +: 8]);
        end
    endfunction

    function automatic signed [7:0] b_element (
        input logic [4095:0] words,
        input integer k,
        input integer column
    );
        integer lane;
        integer reg_index;
        integer byte_index;
        integer bit_index;
        begin
            lane = k;
            reg_index = column / 4;
            byte_index = column % 4;
            bit_index =
                (reg_index * 1024)
                + (lane * 32)
                + (byte_index * 8);
            b_element = $signed(words[bit_index +: 8]);
        end
    endfunction

    function automatic logic [31:0] c_element (
        input logic [8191:0] words,
        input integer row,
        input integer column
    );
        integer lane;
        integer reg_index;
        integer bit_index;
        begin
            lane = (row * 2) + (column / 8);
            reg_index = column % 8;
            bit_index =
                (reg_index * 1024)
                + (lane * 32);
            c_element = words[bit_index +: 32];
        end
    endfunction

    function automatic logic [31:0] int8_product_bits (
        input signed [7:0] left,
        input signed [7:0] right
    );
        logic signed [15:0] product;
        begin
            product = left * right;
            int8_product_bits = {{16{product[15]}}, product};
        end
    endfunction

    integer row;
    integer column;
    integer index;
    integer result_lane;
    integer result_reg;
    integer result_bit;
    integer even_k;
    integer odd_k;
    logic [31:0] next_even;
    logic [31:0] next_odd;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            result_valid <= 1'b0;
            result_words <= '0;
            for (index = 0; index < 256; index = index + 1) begin
                even_acc_q[index] <= 32'd0;
                odd_acc_q[index] <= 32'd0;
            end

`ifndef SYNTHESIS
            execution_active_q <= 1'b0;
            expected_cycle_q <= 5'd0;
`endif
        end else begin
            result_valid <= 1'b0;

            if (execute_valid) begin
                even_k = execute_cycle * 2;
                odd_k = even_k + 1;

                for (row = 0; row < 16; row = row + 1) begin
                    for (column = 0; column < 16; column = column + 1) begin
                        index = (row * 16) + column;

                        if (execute_cycle == 5'd0) begin
                            next_even =
                                c_element(active_c_words, row, column)
                                + int8_product_bits(
                                    a_element(active_a_words, row, even_k),
                                    b_element(active_b_words, even_k, column));
                            next_odd =
                                int8_product_bits(
                                    a_element(active_a_words, row, odd_k),
                                    b_element(active_b_words, odd_k, column));
                        end else begin
                            next_even =
                                even_acc_q[index]
                                + int8_product_bits(
                                    a_element(active_a_words, row, even_k),
                                    b_element(active_b_words, even_k, column));
                            next_odd =
                                odd_acc_q[index]
                                + int8_product_bits(
                                    a_element(active_a_words, row, odd_k),
                                    b_element(active_b_words, odd_k, column));
                        end

                        even_acc_q[index] <= next_even;
                        odd_acc_q[index] <= next_odd;

                        if (execute_cycle == 5'd15) begin
                            result_lane =
                                (row * 2) + (column / 8);
                            result_reg = column % 8;
                            result_bit =
                                (result_reg * 1024)
                                + (result_lane * 32);
                            result_words[result_bit +: 32]
                                <= next_even + next_odd;
                        end
                    end
                end

                if (execute_cycle == 5'd15) begin
                    result_valid <= 1'b1;
                end
            end

`ifndef SYNTHESIS
            if (execute_valid) begin
                if (!execution_active_q && execute_cycle != 5'd0) begin
                    $fatal(1, "matrix INT8 execution did not start at cycle zero");
                end
                if (execution_active_q && execute_cycle != expected_cycle_q) begin
                    $fatal(
                        1,
                        "matrix INT8 execution cycle out of order: got %0d expected %0d",
                        execute_cycle,
                        expected_cycle_q
                    );
                end

                if (execute_cycle == 5'd15) begin
                    execution_active_q <= 1'b0;
                    expected_cycle_q <= 5'd0;
                end else begin
                    execution_active_q <= 1'b1;
                    expected_cycle_q <= execute_cycle + 5'd1;
                end
            end else if (execution_active_q) begin
                $fatal(1, "matrix INT8 execution cycle stream was interrupted");
            end
`endif
        end
    end

endmodule
