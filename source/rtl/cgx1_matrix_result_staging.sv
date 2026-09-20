// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Matrix output-result staging only. Arithmetic production is separate work.

module cgx1_matrix_result_staging (
    input  logic          clk,
    input  logic          reset_n,

    input  logic          result_load_valid,
    input  logic [8191:0] result_words,

    input  logic          writeback_valid,
    input  logic [2:0]    writeback_cycle,

    output logic          result_valid,
    output logic          result_loaded,
    output logic          result_consumed,
    output logic [1023:0] rf_write_data
);

    logic [8191:0] result_q;
    logic [2:0] expected_writeback_cycle_q;

    always_comb begin
        if (!result_valid
            && result_load_valid
            && writeback_valid
            && writeback_cycle == 3'd0) begin
            rf_write_data = result_words[1023:0];
        end else begin
            unique case (writeback_cycle)
                3'd0: rf_write_data = result_q[1023:0];
                3'd1: rf_write_data = result_q[2047:1024];
                3'd2: rf_write_data = result_q[3071:2048];
                3'd3: rf_write_data = result_q[4095:3072];
                3'd4: rf_write_data = result_q[5119:4096];
                3'd5: rf_write_data = result_q[6143:5120];
                3'd6: rf_write_data = result_q[7167:6144];
                3'd7: rf_write_data = result_q[8191:7168];
                default: rf_write_data = '0;
            endcase
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            result_q <= '0;
            expected_writeback_cycle_q <= 3'd0;
            result_valid <= 1'b0;
            result_loaded <= 1'b0;
            result_consumed <= 1'b0;
        end else begin
            result_loaded <= 1'b0;
            result_consumed <= 1'b0;

            if (result_load_valid && !result_valid) begin
                result_q <= result_words;
                result_loaded <= 1'b1;

                if (writeback_valid && writeback_cycle == 3'd0) begin
                    expected_writeback_cycle_q <= 3'd1;
                    result_valid <= 1'b1;
                end else begin
                    expected_writeback_cycle_q <= 3'd0;
                    result_valid <= 1'b1;
                end
            end else if (writeback_valid && result_valid) begin
                if (writeback_cycle == 3'd7) begin
                    result_valid <= 1'b0;
                    expected_writeback_cycle_q <= 3'd0;
                    result_consumed <= 1'b1;
                end else begin
                    expected_writeback_cycle_q <=
                        expected_writeback_cycle_q + 3'd1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (reset_n) begin
            if (result_load_valid && result_valid) begin
                $fatal(1, "matrix output-result staging load attempted while occupied");
            end
            if (writeback_valid
                && !result_valid
                && !(result_load_valid && writeback_cycle == 3'd0)) begin
                $fatal(1, "matrix output-result writeback attempted while empty");
            end
            if (writeback_valid
                && result_valid
                && writeback_cycle != expected_writeback_cycle_q) begin
                $fatal(
                    1,
                    "matrix output-result writeback cycle out of order: got %0d expected %0d",
                    writeback_cycle,
                    expected_writeback_cycle_q
                );
            end
        end
    end
`endif

endmodule
