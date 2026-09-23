// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_matrix_vector_issue_arbiter(
 input logic matrix_valid, matrix_ready, matrix_service_window,
 input logic vector_valid, vector_ready,
 output logic matrix_accept, vector_accept
);
 always_comb begin
   matrix_accept=matrix_valid&&matrix_ready&&!matrix_service_window;
   vector_accept=!matrix_accept&&vector_valid&&vector_ready;
 end
endmodule
