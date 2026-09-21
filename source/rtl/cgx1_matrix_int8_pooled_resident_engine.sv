// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Candidate resident-wave signed INT8 engine backed by pooled VGPR storage.
// Foundry storage macros and ordinary vector execution remain outside this boundary.

module cgx1_matrix_int8_pooled_resident_engine #(
    parameter integer PHYSICAL_ROWS = 128,
    parameter integer RESIDENT_WAVE_SLOTS = 16,
    parameter integer ROW_WIDTH = (PHYSICAL_ROWS <= 1) ? 1 : $clog2(PHYSICAL_ROWS),
    parameter integer WAVE_SLOT_WIDTH = (RESIDENT_WAVE_SLOTS <= 1) ? 1 : $clog2(RESIDENT_WAVE_SLOTS)
) (
    input  logic                               clk,
    input  logic                               reset_n,
    input  logic                               reserve_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         reserve_wave_slot,
    input  logic [8:0]                         reserve_register_count,
    output logic                               reserve_ready,
    output logic                               reserve_accepted,
    input  logic                               activate_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         activate_wave_slot,
    output logic                               activate_ready,
    output logic                               activate_accepted,
    input  logic                               release_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         release_wave_slot,
    input  logic                               release_quiescent,
    output logic                               release_ready,
    output logic                               release_accepted,
    input  logic                               restore_valid,
    input  logic [WAVE_SLOT_WIDTH-1:0]         restore_wave_slot,
    input  logic [7:0]                         restore_register,
    input  logic [1023:0]                      restore_data,
    output logic                               restore_ready,
    input  logic [RESIDENT_WAVE_SLOTS-1:0]     matrix_request_valid,
    input  logic [RESIDENT_WAVE_SLOTS-1:0]     matrix_request_full_wave_active,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_d_base,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_a_base,
    input  logic [(RESIDENT_WAVE_SLOTS*8)-1:0] matrix_request_b_base,
    output logic [RESIDENT_WAVE_SLOTS-1:0]     matrix_request_ready,
    output logic [RESIDENT_WAVE_SLOTS-1:0]     matrix_request_accepted,
    output logic                               illegal_issue,
    output logic [WAVE_SLOT_WIDTH-1:0]         illegal_wave_slot,
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
    output logic [RESIDENT_WAVE_SLOTS-1:0]     resident_wave_busy
);

    logic [RESIDENT_WAVE_SLOTS-1:0] preflight_ready;
    logic [RESIDENT_WAVE_SLOTS-1:0] preflight_gated_valid;
    logic [RESIDENT_WAVE_SLOTS-1:0] engine_request_valid;
    logic [RESIDENT_WAVE_SLOTS-1:0] engine_request_ready;
    logic rf_read_valid;
    logic [7:0] rf_read_addr0;
    logic [7:0] rf_read_addr1;
    logic [WAVE_SLOT_WIDTH-1:0] rf_read_wave_slot;
    logic [1023:0] rf_read_data0;
    logic [1023:0] rf_read_data1;
    logic rf_read_ready;
    logic rf_read0_initialized;
    logic rf_read1_initialized;
    logic rf_write_valid;
    logic [7:0] rf_write_addr;
    logic [WAVE_SLOT_WIDTH-1:0] rf_write_wave_slot;
    logic [1023:0] rf_write_data;
    logic rf_write_ready;
    integer request_index;

    always_comb begin
        engine_request_valid = '0;
        matrix_request_ready = '0;

        for (request_index = 0;
             request_index < RESIDENT_WAVE_SLOTS;
             request_index = request_index + 1) begin
            engine_request_valid[request_index] = matrix_request_valid[request_index]
                && (!matrix_request_full_wave_active[request_index]
                    || preflight_ready[request_index]);

            matrix_request_ready[request_index] = engine_request_ready[request_index]
                && (!matrix_request_full_wave_active[request_index]
                    || preflight_ready[request_index]);
        end
    end

    cgx1_pooled_vgpr_matrix_subsystem #(
        .PHYSICAL_ROWS(PHYSICAL_ROWS),
        .RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),
        .ROW_WIDTH(ROW_WIDTH),
        .WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)
    ) pooled (
        .clk(clk), .reset_n(reset_n),
        .reserve_valid(reserve_valid),
        .reserve_wave_slot(reserve_wave_slot),
        .reserve_register_count(reserve_register_count),
        .reserve_ready(reserve_ready),
        .reserve_accepted(reserve_accepted),
        .activate_valid(activate_valid),
        .activate_wave_slot(activate_wave_slot),
        .activate_ready(activate_ready),
        .activate_accepted(activate_accepted),
        .release_valid(release_valid),
        .release_wave_slot(release_wave_slot),
        .release_quiescent(release_quiescent),
        .release_ready(release_ready),
        .release_accepted(release_accepted),
        .wave_execution_busy(resident_wave_busy),
        .restore_valid(restore_valid),
        .restore_wave_slot(restore_wave_slot),
        .restore_register(restore_register),
        .restore_data(restore_data),
        .restore_ready(restore_ready),
        .matrix_request_valid(matrix_request_valid),
        .matrix_request_d_base(matrix_request_d_base),
        .matrix_request_a_base(matrix_request_a_base),
        .matrix_request_b_base(matrix_request_b_base),
        .matrix_request_preflight_ready(preflight_ready),
        .matrix_request_gated_valid(preflight_gated_valid),
        .matrix_rf_read_valid(rf_read_valid),
        .matrix_rf_read_wave_slot(rf_read_wave_slot),
        .matrix_rf_read_addr0(rf_read_addr0),
        .matrix_rf_read_addr1(rf_read_addr1),
        .matrix_rf_read_ready(rf_read_ready),
        .matrix_rf_read0_initialized(rf_read0_initialized),
        .matrix_rf_read_data0(rf_read_data0),
        .matrix_rf_read1_initialized(rf_read1_initialized),
        .matrix_rf_read_data1(rf_read_data1),
        .matrix_rf_write_valid(rf_write_valid),
        .matrix_rf_write_wave_slot(rf_write_wave_slot),
        .matrix_rf_write_addr(rf_write_addr),
        .matrix_rf_write_data(rf_write_data),
        .matrix_rf_write_ready(rf_write_ready)
    );

    cgx1_matrix_int8_resident_engine #(
        .RESIDENT_WAVE_SLOTS(RESIDENT_WAVE_SLOTS),
        .WAVE_SLOT_WIDTH(WAVE_SLOT_WIDTH)
    ) engine (
        .clk(clk),
        .reset_n(reset_n),
        .matrix_request_valid(engine_request_valid),
        .matrix_request_full_wave_active(matrix_request_full_wave_active),
        .matrix_request_d_base(matrix_request_d_base),
        .matrix_request_a_base(matrix_request_a_base),
        .matrix_request_b_base(matrix_request_b_base),
        .matrix_request_ready(engine_request_ready),
        .matrix_request_accepted(matrix_request_accepted),
        .illegal_issue(illegal_issue),
        .illegal_wave_slot(illegal_wave_slot),
        .rf_read_valid(rf_read_valid),
        .rf_read_addr0(rf_read_addr0),
        .rf_read_addr1(rf_read_addr1),
        .rf_read_wave_slot(rf_read_wave_slot),
        .rf_read_data0(rf_read_data0),
        .rf_read_data1(rf_read_data1),
        .rf_write_valid(rf_write_valid),
        .rf_write_addr(rf_write_addr),
        .rf_write_wave_slot(rf_write_wave_slot),
        .rf_write_data(rf_write_data),
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
        .resident_wave_busy(resident_wave_busy)
    );

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (reset_n && rf_read_valid
            && (!rf_read_ready || !rf_read0_initialized || !rf_read1_initialized)) begin
            $fatal(1, "pooled resident engine reached capture without serviceable initialized operands");
        end
        if (reset_n && rf_write_valid && !rf_write_ready) begin
            $fatal(1, "pooled resident engine writeback was not serviceable");
        end
    end
`endif

endmodule
