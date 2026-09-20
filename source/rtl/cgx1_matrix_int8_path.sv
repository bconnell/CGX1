// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Functional signed INT8 matrix path. Physical timing/area implementation is separate work.

module cgx1_matrix_int8_path (
    input  logic          clk,
    input  logic          reset_n,

    input  logic          capture_valid,
    input  logic [2:0]    capture_cycle,
    input  logic [1023:0] rf_read_data0,
    input  logic [1023:0] rf_read_data1,

    input  logic          execute_valid,
    input  logic [4:0]    execute_cycle,
    input  logic [3:0]    execute_opcode,

    input  logic          writeback_valid,
    input  logic [2:0]    writeback_cycle,

    output logic          active_operands_valid,
    output logic          arithmetic_result_valid,
    output logic          result_stage_valid,
    output logic          result_stage_loaded,
    output logic          result_stage_consumed,
    output logic [1023:0] rf_write_data
);

    logic          active_operands_loaded;
    logic [4095:0] active_a_words;
    logic [4095:0] active_b_words;
    logic [8191:0] active_c_words;
    logic [8191:0] arithmetic_result_words;
    logic          int8_execute_valid;

    assign int8_execute_valid =
        execute_valid && (execute_opcode == 4'h6);

    cgx1_matrix_operand_staging operand_staging (
        .clk(clk),
        .reset_n(reset_n),
        .capture_valid(capture_valid),
        .capture_cycle(capture_cycle),
        .rf_read_data0(rf_read_data0),
        .rf_read_data1(rf_read_data1),
        .active_operands_valid(active_operands_valid),
        .active_operands_loaded(active_operands_loaded),
        .active_a_words(active_a_words),
        .active_b_words(active_b_words),
        .active_c_words(active_c_words)
    );

    cgx1_matrix_int8_execution int8_execution (
        .clk(clk),
        .reset_n(reset_n),
        .execute_valid(int8_execute_valid),
        .execute_cycle(execute_cycle),
        .active_a_words(active_a_words),
        .active_b_words(active_b_words),
        .active_c_words(active_c_words),
        .result_valid(arithmetic_result_valid),
        .result_words(arithmetic_result_words)
    );

    cgx1_matrix_result_staging result_staging (
        .clk(clk),
        .reset_n(reset_n),
        .result_load_valid(arithmetic_result_valid),
        .result_words(arithmetic_result_words),
        .writeback_valid(writeback_valid),
        .writeback_cycle(writeback_cycle),
        .result_valid(result_stage_valid),
        .result_loaded(result_stage_loaded),
        .result_consumed(result_stage_consumed),
        .rf_write_data(rf_write_data)
    );

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (reset_n) begin
            if (execute_valid
                && execute_opcode == 4'h6
                && !active_operands_valid) begin
                $fatal(1, "matrix INT8 execution started without active operands");
            end
            if (arithmetic_result_valid
                && !(writeback_valid && writeback_cycle == 3'd0)) begin
                $fatal(1, "matrix INT8 result pulse was not aligned with writeback cycle zero");
            end
        end
    end
`endif

endmodule
