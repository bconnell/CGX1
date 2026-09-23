// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_pooled_vgpr_release_guard(
 input logic external_quiescent,
 input logic matrix_busy, vector_busy,
 input logic matrix_rf_active, vector_rf_active,
 input logic split_read_pending, restore_same_wave,
 output logic release_safe
);
 always_comb release_safe=external_quiescent && !matrix_busy && !vector_busy && !matrix_rf_active && !vector_rf_active && !split_read_pending && !restore_same_wave;
endmodule
