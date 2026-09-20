// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Matrix operand staging only. Physical storage macros and arithmetic datapath are separate work.

module cgx1_matrix_operand_staging (
    input  logic          clk,
    input  logic          reset_n,

    input  logic          capture_valid,
    input  logic [2:0]    capture_cycle,
    input  logic [1023:0] rf_read_data0,
    input  logic [1023:0] rf_read_data1,

    output logic          active_operands_valid,
    output logic          active_operands_loaded,
    output logic [4095:0] active_a_words,
    output logic [4095:0] active_b_words,
    output logic [8191:0] active_c_words
);

    logic [4095:0] capture_a_q;
    logic [4095:0] capture_b_q;
    logic [8191:0] capture_c_q;

`ifndef SYNTHESIS
    logic [2:0] expected_capture_cycle_q;
`endif

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            capture_a_q <= '0;
            capture_b_q <= '0;
            capture_c_q <= '0;

            active_a_words <= '0;
            active_b_words <= '0;
            active_c_words <= '0;
            active_operands_valid <= 1'b0;
            active_operands_loaded <= 1'b0;

`ifndef SYNTHESIS
            expected_capture_cycle_q <= 3'd0;
`endif
        end else begin
            active_operands_loaded <= 1'b0;

            if (capture_valid) begin
                unique case (capture_cycle)
                    3'd0: begin
                        capture_a_q[1023:0] <= rf_read_data0;
                        capture_b_q[1023:0] <= rf_read_data1;
                    end
                    3'd1: begin
                        capture_a_q[2047:1024] <= rf_read_data0;
                        capture_b_q[2047:1024] <= rf_read_data1;
                    end
                    3'd2: begin
                        capture_a_q[3071:2048] <= rf_read_data0;
                        capture_b_q[3071:2048] <= rf_read_data1;
                    end
                    3'd3: begin
                        capture_a_q[4095:3072] <= rf_read_data0;
                        capture_b_q[4095:3072] <= rf_read_data1;
                    end
                    3'd4: begin
                        capture_c_q[1023:0] <= rf_read_data0;
                        capture_c_q[2047:1024] <= rf_read_data1;
                    end
                    3'd5: begin
                        capture_c_q[3071:2048] <= rf_read_data0;
                        capture_c_q[4095:3072] <= rf_read_data1;
                    end
                    3'd6: begin
                        capture_c_q[5119:4096] <= rf_read_data0;
                        capture_c_q[6143:5120] <= rf_read_data1;
                    end
                    3'd7: begin
                        capture_c_q[7167:6144] <= rf_read_data0;
                        capture_c_q[8191:7168] <= rf_read_data1;

                        active_a_words <= capture_a_q;
                        active_b_words <= capture_b_q;
                        active_c_words <= {
                            rf_read_data1,
                            rf_read_data0,
                            capture_c_q[6143:0]
                        };
                        active_operands_valid <= 1'b1;
                        active_operands_loaded <= 1'b1;
                    end
                endcase
            end

`ifndef SYNTHESIS
            if (capture_valid) begin
                if (capture_cycle != expected_capture_cycle_q) begin
                    $fatal(
                        1,
                        "matrix staging capture cycle out of order: got %0d expected %0d",
                        capture_cycle,
                        expected_capture_cycle_q
                    );
                end

                if (capture_cycle == 3'd7) begin
                    expected_capture_cycle_q <= 3'd0;
                end else begin
                    expected_capture_cycle_q <= expected_capture_cycle_q + 3'd1;
                end
            end
`endif
        end
    end

endmodule
