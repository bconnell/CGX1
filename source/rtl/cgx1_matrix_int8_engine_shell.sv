// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// One-wave signed INT8 matrix-engine shell.
// Multi-wave arbitration, the physical VGPR file, and floating datapaths are separate work.

module cgx1_matrix_int8_engine_shell (
    input  logic          clk,
    input  logic          reset_n,

    input  logic          issue_valid,
    input  logic [3:0]    issue_opcode,
    input  logic          issue_full_wave_active,
    input  logic [7:0]    issue_d_base,
    input  logic [7:0]    issue_a_base,
    input  logic [7:0]    issue_b_base,

    output logic          issue_ready,
    output logic          issue_legal,
    output logic          issue_accepted,
    output logic          illegal_issue,

    output logic          rf_read_valid,
    output logic [7:0]    rf_read_addr0,
    output logic [7:0]    rf_read_addr1,
    input  logic [1023:0] rf_read_data0,
    input  logic [1023:0] rf_read_data1,

    output logic          rf_write_valid,
    output logic [7:0]    rf_write_addr,
    output logic [1023:0] rf_write_data,

    input  logic [255:0]  ordinary_read_mask,
    input  logic [255:0]  ordinary_write_mask,
    input  logic          ordinary_uses_read_ports,
    input  logic          ordinary_uses_write_port,

    output logic          ordinary_raw_hazard,
    output logic          ordinary_waw_hazard,
    output logic          ordinary_war_hazard,
    output logic          ordinary_read_port_conflict,
    output logic          ordinary_write_port_conflict,
    output logic          ordinary_ready,

    output logic [255:0]  matrix_source_pending_mask,
    output logic [255:0]  matrix_destination_pending_mask,
    output logic          destination_complete_valid
);

    localparam logic [3:0] INT8_OPCODE = 4'h6;

    logic controller_issue_valid;
    logic controller_issue_ready;
    logic controller_issue_legal;
    logic controller_issue_dependency_hazard;
    logic controller_issue_accepted;
    logic controller_illegal_issue;
    logic [7:0] accepted_d_base;
    logic [7:0] accepted_a_base;
    logic [7:0] accepted_b_base;

    logic decode_active;
    logic capture_active;
    logic [2:0] capture_cycle;
    logic execute_active;
    logic [4:0] execute_cycle;
    logic [3:0] execute_opcode;
    logic writeback_active;
    logic [2:0] writeback_cycle;

    logic source_release_valid;
    logic [7:0] source_release_a_base;
    logic [7:0] source_release_b_base;
    logic [7:0] destination_complete_base;

    logic active_operands_valid;
    logic arithmetic_result_valid;
    logic result_stage_valid;
    logic result_stage_loaded;
    logic result_stage_consumed;

    assign controller_issue_valid =
        issue_valid && (issue_opcode == INT8_OPCODE);

    assign issue_ready = controller_issue_ready;
    assign issue_legal =
        (issue_opcode == INT8_OPCODE) && controller_issue_legal;
    assign issue_accepted = controller_issue_accepted;
    assign illegal_issue =
        controller_illegal_issue
        || (issue_valid
            && controller_issue_ready
            && issue_opcode != INT8_OPCODE);

    cgx1_matrix_pipeline_control control (
        .clk(clk),
        .reset_n(reset_n),
        .issue_valid(controller_issue_valid),
        .issue_wave_slot(1'b0),
        .issue_ready(controller_issue_ready),
        .issue_legal(controller_issue_legal),
        .issue_dependency_hazard(controller_issue_dependency_hazard),
        .issue_accepted(controller_issue_accepted),
        .issue_accepted_d_base(accepted_d_base),
        .issue_accepted_a_base(accepted_a_base),
        .issue_accepted_b_base(accepted_b_base),
        .illegal_issue(controller_illegal_issue),
        .issue_opcode(issue_opcode),
        .issue_full_wave_active(issue_full_wave_active),
        .issue_d_base(issue_d_base),
        .issue_a_base(issue_a_base),
        .issue_b_base(issue_b_base),
        .decode_active(decode_active),
        .capture_active(capture_active),
        .capture_cycle_index(capture_cycle),
        .execute_active(execute_active),
        .execute_cycle_index(execute_cycle),
        .execute_opcode(execute_opcode),
        .writeback_active(writeback_active),
        .writeback_cycle_index(writeback_cycle),
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

    cgx1_matrix_int8_path int8_path (
        .clk(clk),
        .reset_n(reset_n),
        .capture_valid(capture_active),
        .capture_cycle(capture_cycle),
        .rf_read_data0(rf_read_data0),
        .rf_read_data1(rf_read_data1),
        .execute_valid(execute_active),
        .execute_cycle(execute_cycle),
        .execute_opcode(execute_opcode),
        .writeback_valid(writeback_active),
        .writeback_cycle(writeback_cycle),
        .active_operands_valid(active_operands_valid),
        .arithmetic_result_valid(arithmetic_result_valid),
        .result_stage_valid(result_stage_valid),
        .result_stage_loaded(result_stage_loaded),
        .result_stage_consumed(result_stage_consumed),
        .rf_write_data(rf_write_data)
    );

    cgx1_matrix_wave_scoreboard scoreboard (
        .clk(clk),
        .reset_n(reset_n),
        .matrix_issue_accepted(controller_issue_accepted),
        .matrix_accepted_d_base(accepted_d_base),
        .matrix_accepted_a_base(accepted_a_base),
        .matrix_accepted_b_base(accepted_b_base),
        .matrix_source_release_valid(source_release_valid),
        .matrix_source_release_a_base(source_release_a_base),
        .matrix_source_release_b_base(source_release_b_base),
        .matrix_destination_complete_valid(destination_complete_valid),
        .matrix_destination_complete_base(destination_complete_base),
        .matrix_rf_read_valid(rf_read_valid),
        .matrix_rf_write_valid(rf_write_valid),
        .ordinary_read_mask(ordinary_read_mask),
        .ordinary_write_mask(ordinary_write_mask),
        .ordinary_uses_read_ports(ordinary_uses_read_ports),
        .ordinary_uses_write_port(ordinary_uses_write_port),
        .ordinary_raw_hazard(ordinary_raw_hazard),
        .ordinary_waw_hazard(ordinary_waw_hazard),
        .ordinary_war_hazard(ordinary_war_hazard),
        .ordinary_read_port_conflict(ordinary_read_port_conflict),
        .ordinary_write_port_conflict(ordinary_write_port_conflict),
        .ordinary_ready(ordinary_ready),
        .matrix_source_pending_mask(matrix_source_pending_mask),
        .matrix_destination_pending_mask(matrix_destination_pending_mask)
    );

endmodule
