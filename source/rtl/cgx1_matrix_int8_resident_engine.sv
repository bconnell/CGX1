// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Parameterized resident-wave signed INT8 matrix-engine boundary.
// The physical VGPR file and ordinary vector execution datapath remain external.

module cgx1_matrix_int8_resident_engine #(
    parameter integer RESIDENT_WAVE_SLOTS = 4,
    parameter integer WAVE_SLOT_WIDTH = 2
) (
    input  logic                               clk,
    input  logic                               reset_n,
    input  logic [RESIDENT_WAVE_SLOTS-1:0]     matrix_request_valid,
    input  logic [RESIDENT_WAVE_SLOTS-1:0]     matrix_request_full_wave_active,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_d_base,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_a_base,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_b_base,
    output logic [RESIDENT_WAVE_SLOTS-1:0]     matrix_request_ready,
    output logic [RESIDENT_WAVE_SLOTS-1:0]     matrix_request_accepted,
    output logic                               illegal_issue,
    output logic [WAVE_SLOT_WIDTH-1:0]         illegal_wave_slot,
    output logic                               rf_read_valid,
    output logic [7:0]                         rf_read_addr0,
    output logic [7:0]                         rf_read_addr1,
    output logic [WAVE_SLOT_WIDTH-1:0]         rf_read_wave_slot,
    input  logic [1023:0]                      rf_read_data0,
    input  logic [1023:0]                      rf_read_data1,
    output logic                               rf_write_valid,
    output logic [7:0]                         rf_write_addr,
    output logic [WAVE_SLOT_WIDTH-1:0]         rf_write_wave_slot,
    output logic [1023:0]                      rf_write_data,
    input  logic                               ordinary_issue_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         ordinary_wave_slot,
    input  logic [255:0]                       ordinary_read_mask,
    input  logic [255:0]                       ordinary_write_mask,
    input  logic                               ordinary_uses_read_ports,
    input  logic                               ordinary_uses_write_port,
    output logic                               ordinary_raw_hazard,
    output logic                               ordinary_waw_hazard,
    output logic                               ordinary_war_hazard,
    output logic                               ordinary_read_port_conflict,
    output logic                               ordinary_write_port_conflict,
    output logic                               ordinary_ready,
    output logic                               ordinary_issue_accepted,
    output logic [(RESIDENT_WAVE_SLOTS*256)-1:0] matrix_source_pending_mask_flat,
    output logic [(RESIDENT_WAVE_SLOTS*256)-1:0] matrix_destination_pending_mask_flat,
    output logic [RESIDENT_WAVE_SLOTS-1:0]     resident_wave_busy
);

    localparam logic [3:0] INT8_OPCODE = 4'h6;

    logic arbiter_grant_valid;
    logic [WAVE_SLOT_WIDTH-1:0] arbiter_grant_wave_slot;
    logic arbiter_grant_full_wave_active;
    logic [7:0] arbiter_grant_d_base;
    logic [7:0] arbiter_grant_a_base;
    logic [7:0] arbiter_grant_b_base;

    logic controller_issue_ready;
    logic controller_issue_legal;
    logic controller_issue_dependency_hazard;
    logic controller_issue_accepted;
    logic controller_illegal_issue;
    logic [7:0] accepted_d_base;
    logic [7:0] accepted_a_base;
    logic [7:0] accepted_b_base;
    logic [WAVE_SLOT_WIDTH-1:0] accepted_wave_slot;

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
    logic [WAVE_SLOT_WIDTH-1:0] source_release_wave_slot;
    logic destination_complete_valid;
    logic [7:0] destination_complete_base;
    logic [WAVE_SLOT_WIDTH-1:0] destination_complete_wave_slot;

    logic active_operands_valid;
    logic arithmetic_result_valid;
    logic result_stage_valid;
    logic result_stage_loaded;
    logic result_stage_consumed;
    logic [255:0] selected_source_pending_mask;
    logic [255:0] selected_destination_pending_mask;

    logic illegal_issue_d;
    logic [WAVE_SLOT_WIDTH-1:0] illegal_wave_slot_d;
    integer accepted_index;

    cgx1_matrix_resident_wave_arbiter #(
        .RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),
        .WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)
    ) arbiter (
        .clk(clk),
        .reset_n(reset_n),
        .request_valid(matrix_request_valid),
        .request_full_wave_active(matrix_request_full_wave_active),
        .request_d_base(matrix_request_d_base),
        .request_a_base(matrix_request_a_base),
        .request_b_base(matrix_request_b_base),
        .request_ready(matrix_request_ready),
        .grant_valid(arbiter_grant_valid),
        .grant_wave_slot(arbiter_grant_wave_slot),
        .grant_full_wave_active(arbiter_grant_full_wave_active),
        .grant_d_base(arbiter_grant_d_base),
        .grant_a_base(arbiter_grant_a_base),
        .grant_b_base(arbiter_grant_b_base),
        .grant_ready(controller_issue_ready)
    );

    cgx1_matrix_pipeline_control #(
        .WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)
    ) control (
        .clk(clk),
        .reset_n(reset_n),
        .issue_valid(arbiter_grant_valid),
        .issue_wave_slot(arbiter_grant_wave_slot),
        .issue_ready(controller_issue_ready),
        .issue_legal(controller_issue_legal),
        .issue_dependency_hazard(controller_issue_dependency_hazard),
        .issue_accepted(controller_issue_accepted),
        .issue_accepted_d_base(accepted_d_base),
        .issue_accepted_a_base(accepted_a_base),
        .issue_accepted_b_base(accepted_b_base),
        .issue_accepted_wave_slot(accepted_wave_slot),
        .illegal_issue(controller_illegal_issue),
        .issue_opcode(INT8_OPCODE),
        .issue_full_wave_active(arbiter_grant_full_wave_active),
        .issue_d_base(arbiter_grant_d_base),
        .issue_a_base(arbiter_grant_a_base),
        .issue_b_base(arbiter_grant_b_base),
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
        .rf_read_wave_slot(rf_read_wave_slot),
        .rf_write_valid(rf_write_valid),
        .rf_write_addr(rf_write_addr),
        .rf_write_wave_slot(rf_write_wave_slot),
        .source_release_valid(source_release_valid),
        .source_release_a_base(source_release_a_base),
        .source_release_b_base(source_release_b_base),
        .source_release_wave_slot(source_release_wave_slot),
        .destination_complete_valid(destination_complete_valid),
        .destination_complete_base(destination_complete_base),
        .destination_complete_wave_slot(destination_complete_wave_slot)
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

    cgx1_matrix_resident_wave_scoreboard #(
        .RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),
        .WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)
    ) scoreboard (
        .clk(clk),
        .reset_n(reset_n),
        .matrix_issue_accepted(controller_issue_accepted),
        .matrix_issue_wave_slot(accepted_wave_slot),
        .matrix_accepted_d_base(accepted_d_base),
        .matrix_accepted_a_base(accepted_a_base),
        .matrix_accepted_b_base(accepted_b_base),
        .matrix_source_release_valid(source_release_valid),
        .matrix_source_release_wave_slot(source_release_wave_slot),
        .matrix_source_release_a_base(source_release_a_base),
        .matrix_source_release_b_base(source_release_b_base),
        .matrix_destination_complete_valid(destination_complete_valid),
        .matrix_destination_complete_wave_slot(destination_complete_wave_slot),
        .matrix_destination_complete_base(destination_complete_base),
        .matrix_rf_read_valid(rf_read_valid),
        .matrix_rf_write_valid(rf_write_valid),
        .ordinary_issue_valid(ordinary_issue_valid),
        .ordinary_wave_slot(ordinary_wave_slot),
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
        .ordinary_issue_accepted(ordinary_issue_accepted),
        .selected_source_pending_mask(selected_source_pending_mask),
        .selected_destination_pending_mask(selected_destination_pending_mask),
        .resident_source_pending_mask_flat(matrix_source_pending_mask_flat),
        .resident_destination_pending_mask_flat(matrix_destination_pending_mask_flat),
        .resident_wave_busy(resident_wave_busy)
    );

    always_comb begin
        matrix_request_accepted = '0;
        if (controller_issue_accepted
            && ($unsigned(accepted_wave_slot) < RESIDENT_WAVE_SLOTS)) begin
            matrix_request_accepted[accepted_wave_slot] = 1'b1;
        end

        illegal_issue_d =
            arbiter_grant_valid
            && controller_issue_ready
            && !controller_issue_legal;
        illegal_wave_slot_d = arbiter_grant_wave_slot;
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            illegal_issue <= 1'b0;
            illegal_wave_slot <= '0;
        end else begin
            illegal_issue <= illegal_issue_d;
            if (illegal_issue_d) begin
                illegal_wave_slot <= illegal_wave_slot_d;
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (reset_n && controller_illegal_issue != illegal_issue) begin
            $fatal(1, "resident engine illegal-issue reporting diverged from matrix control");
        end
    end
`endif
endmodule
