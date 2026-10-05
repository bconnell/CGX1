// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_matrix_vector_issue_arbiter_formal;
    (* anyconst *) logic matrix_valid;
    (* anyconst *) logic matrix_ready;
    (* anyconst *) logic matrix_service_window;
    (* anyconst *) logic vector_valid;
    (* anyconst *) logic vector_ready;
    logic matrix_accept;
    logic vector_accept;

    cgx1_matrix_vector_issue_arbiter dut (.*);

    always_comb begin
        assert (matrix_accept == (matrix_valid && matrix_ready && !matrix_service_window));
        assert (vector_accept == ((!matrix_valid || !matrix_ready || matrix_service_window)
            && vector_valid && vector_ready));
        assert (!(matrix_accept && vector_accept));
    end
endmodule
