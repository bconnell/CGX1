// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_matrix_vector_issue_arbiter_tb;
    logic matrix_valid;
    logic matrix_ready;
    logic matrix_service_window;
    logic vector_valid;
    logic vector_ready;
    logic matrix_accept;
    logic vector_accept;

    cgx1_matrix_vector_issue_arbiter dut (.*);

    task automatic check_case(
        input logic matrix_valid_value,
        input logic matrix_ready_value,
        input logic matrix_service_window_value,
        input logic vector_valid_value,
        input logic vector_ready_value,
        input logic expected_matrix_accept,
        input logic expected_vector_accept,
        input integer case_id
    );
        begin
            matrix_valid = matrix_valid_value;
            matrix_ready = matrix_ready_value;
            matrix_service_window = matrix_service_window_value;
            vector_valid = vector_valid_value;
            vector_ready = vector_ready_value;
            #1;
            if (matrix_accept !== expected_matrix_accept
                || vector_accept !== expected_vector_accept) begin
                $fatal(1, "issue arbiter case=%0d matrix_accept=%b expected=%b vector_accept=%b expected=%b",
                    case_id, matrix_accept, expected_matrix_accept,
                    vector_accept, expected_vector_accept);
            end
        end
    endtask

    initial begin
        check_case(1'b1, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1, 1'b0, 0);
        check_case(1'b1, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b1, 1);
        check_case(1'b1, 1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 2);
        check_case(1'b0, 1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 3);
        check_case(1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 4);
        check_case(1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 5);
        $display("[pass] CGX 1 matrix/vector issue arbitration checks passed.");
        $finish;
    end
endmodule
