// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Matrix pipeline control only. Arithmetic datapath and physical VGPR macros are separate work.

module cgx1_matrix_pipeline_control (
    input  logic       clk,
    input  logic       reset_n,

    input  logic       issue_valid,
    output logic       issue_ready,
    output logic       issue_legal,
    output logic       issue_dependency_hazard,
    output logic       issue_accepted,
    output logic       illegal_issue,

    input  logic [3:0] issue_opcode,
    input  logic       issue_full_wave_active,
    input  logic [7:0] issue_d_base,
    input  logic [7:0] issue_a_base,
    input  logic [7:0] issue_b_base,

    output logic       decode_active,
    output logic       capture_active,
    output logic       execute_active,
    output logic       writeback_active,

    output logic       rf_read_valid,
    output logic [7:0] rf_read_addr0,
    output logic [7:0] rf_read_addr1,
    output logic       rf_write_valid,
    output logic [7:0] rf_write_addr,

    output logic       source_release_valid,
    output logic [7:0] source_release_a_base,
    output logic [7:0] source_release_b_base,

    output logic       destination_complete_valid,
    output logic [7:0] destination_complete_base
);

    localparam integer MATRIX_CAPTURE_CYCLES = 8;
    localparam integer MATRIX_EXECUTE_CYCLES = 16;
    localparam integer MATRIX_WRITEBACK_CYCLES = 8;
    localparam integer MATRIX_ISSUE_INTERVAL_CYCLES = 16;
    localparam integer MATRIX_REGISTER_BANK_CLASSES = 8;
    localparam logic [2:0] MATRIX_SOURCE_A_BANK_CLASS = 3'd0;
    localparam logic [2:0] MATRIX_SOURCE_B_BANK_CLASS = 3'd4;
    localparam logic [3:0] MATRIX_OPCODE_MAX = 4'h6;
    localparam logic [3:0] ISSUE_COOLDOWN_RELOAD = MATRIX_ISSUE_INTERVAL_CYCLES - 1;

    logic [3:0] issue_cooldown_q, issue_cooldown_d;

    logic       decode_valid_q, decode_valid_d;
    logic [3:0] decode_opcode_q, decode_opcode_d;
    logic [7:0] decode_d_q, decode_d_d;
    logic [7:0] decode_a_q, decode_a_d;
    logic [7:0] decode_b_q, decode_b_d;

    logic       capture_valid_q, capture_valid_d;
    logic [2:0] capture_cycle_q, capture_cycle_d;
    logic [3:0] capture_opcode_q, capture_opcode_d;
    logic [7:0] capture_d_q, capture_d_d;
    logic [7:0] capture_a_q, capture_a_d;
    logic [7:0] capture_b_q, capture_b_d;

    logic       execute_valid_q, execute_valid_d;
    logic [4:0] execute_cycle_q, execute_cycle_d;
    logic [3:0] execute_opcode_q, execute_opcode_d;
    logic [7:0] execute_d_q, execute_d_d;

    logic       writeback_valid_q, writeback_valid_d;
    logic [2:0] writeback_cycle_q, writeback_cycle_d;
    logic [7:0] writeback_d_q, writeback_d_d;

    logic       issue_fire;
    logic       invalid_fire;
    logic       issue_structural_ready;
    logic       capture_finishing;
    logic       execute_finishing;
    logic       writeback_finishing;

    function automatic logic spans_overlap (
        input logic [7:0] left_base,
        input logic [8:0] left_count,
        input logic [7:0] right_base,
        input logic [8:0] right_count
    );
        logic [8:0] left_start;
        logic [8:0] left_end;
        logic [8:0] right_start;
        logic [8:0] right_end;
        begin
            left_start = {1'b0, left_base};
            right_start = {1'b0, right_base};
            left_end = left_start + left_count;
            right_end = right_start + right_count;
            spans_overlap = (left_start < right_end) && (right_start < left_end);
        end
    endfunction

    function automatic logic register_layout_legal (
        input logic [7:0] d_base,
        input logic [7:0] a_base,
        input logic [7:0] b_base
    );
        logic a_bank_class_ok;
        logic b_bank_class_ok;
        logic ranges_fit;
        logic destination_disjoint;
        begin
            a_bank_class_ok = (a_base[2:0] == MATRIX_SOURCE_A_BANK_CLASS);
            b_bank_class_ok =
                (b_base == a_base)
                || (b_base[2:0] == MATRIX_SOURCE_B_BANK_CLASS);
            ranges_fit = (d_base <= 8'd248)
                && (a_base <= 8'd252)
                && (b_base <= 8'd252);
            destination_disjoint =
                !spans_overlap(d_base, 9'd8, a_base, 9'd4)
                && !spans_overlap(d_base, 9'd8, b_base, 9'd4);

            register_layout_legal =
                (d_base[2:0] == 3'b000)
                && a_bank_class_ok
                && b_bank_class_ok
                && ranges_fit
                && destination_disjoint;
        end
    endfunction

    function automatic logic depends_on_pending_destination (
        input logic [7:0] new_d_base,
        input logic [7:0] new_a_base,
        input logic [7:0] new_b_base,
        input logic [7:0] older_d_base
    );
        begin
            depends_on_pending_destination =
                spans_overlap(new_a_base, 9'd4, older_d_base, 9'd8)
                || spans_overlap(new_b_base, 9'd4, older_d_base, 9'd8)
                || spans_overlap(new_d_base, 9'd8, older_d_base, 9'd8);
        end
    endfunction

    always_comb begin
        issue_legal =
            (issue_opcode <= MATRIX_OPCODE_MAX)
            && issue_full_wave_active
            && register_layout_legal(issue_d_base, issue_a_base, issue_b_base);

        issue_dependency_hazard = 1'b0;
        if (capture_valid_q) begin
            issue_dependency_hazard =
                issue_dependency_hazard
                || depends_on_pending_destination(
                    issue_d_base,
                    issue_a_base,
                    issue_b_base,
                    capture_d_q);
        end
        if (execute_valid_q) begin
            issue_dependency_hazard =
                issue_dependency_hazard
                || depends_on_pending_destination(
                    issue_d_base,
                    issue_a_base,
                    issue_b_base,
                    execute_d_q);
        end
        if (writeback_valid_q) begin
            issue_dependency_hazard =
                issue_dependency_hazard
                || depends_on_pending_destination(
                    issue_d_base,
                    issue_a_base,
                    issue_b_base,
                    writeback_d_q);
        end

        issue_structural_ready = !decode_valid_q && (issue_cooldown_q == 4'd0);
        issue_ready = issue_structural_ready && !issue_dependency_hazard;
        issue_fire = issue_valid && issue_ready && issue_legal;
        invalid_fire = issue_valid && issue_structural_ready && !issue_legal;

        decode_active = decode_valid_q;
        capture_active = capture_valid_q;
        execute_active = execute_valid_q;
        writeback_active = writeback_valid_q;

        rf_read_valid = capture_valid_q;
        rf_read_addr0 = 8'd0;
        rf_read_addr1 = 8'd0;

        if (capture_valid_q) begin
            if (capture_cycle_q < 3'd4) begin
                rf_read_addr0 = capture_a_q + {5'd0, capture_cycle_q};
                rf_read_addr1 = capture_b_q + {5'd0, capture_cycle_q};
            end else begin
                rf_read_addr0 =
                    capture_d_q + {4'd0, (capture_cycle_q - 3'd4), 1'b0};
                rf_read_addr1 =
                    capture_d_q + {4'd0, (capture_cycle_q - 3'd4), 1'b0} + 8'd1;
            end
        end

        rf_write_valid = writeback_valid_q;
        rf_write_addr = writeback_d_q + {5'd0, writeback_cycle_q};

        capture_finishing = capture_valid_q && (capture_cycle_q == MATRIX_CAPTURE_CYCLES - 1);
        execute_finishing = execute_valid_q && (execute_cycle_q == MATRIX_EXECUTE_CYCLES - 1);
        writeback_finishing = writeback_valid_q && (writeback_cycle_q == MATRIX_WRITEBACK_CYCLES - 1);

        source_release_valid = capture_finishing;
        source_release_a_base = capture_a_q;
        source_release_b_base = capture_b_q;

        destination_complete_valid = writeback_finishing;
        destination_complete_base = writeback_d_q;

        issue_cooldown_d = issue_cooldown_q;

        decode_valid_d = decode_valid_q;
        decode_opcode_d = decode_opcode_q;
        decode_d_d = decode_d_q;
        decode_a_d = decode_a_q;
        decode_b_d = decode_b_q;

        capture_valid_d = capture_valid_q;
        capture_cycle_d = capture_cycle_q;
        capture_opcode_d = capture_opcode_q;
        capture_d_d = capture_d_q;
        capture_a_d = capture_a_q;
        capture_b_d = capture_b_q;

        execute_valid_d = execute_valid_q;
        execute_cycle_d = execute_cycle_q;
        execute_opcode_d = execute_opcode_q;
        execute_d_d = execute_d_q;

        writeback_valid_d = writeback_valid_q;
        writeback_cycle_d = writeback_cycle_q;
        writeback_d_d = writeback_d_q;

        if (issue_fire) begin
            issue_cooldown_d = ISSUE_COOLDOWN_RELOAD;
        end else if (issue_cooldown_q != 4'd0) begin
            issue_cooldown_d = issue_cooldown_q - 4'd1;
        end

        if (writeback_valid_q) begin
            if (writeback_finishing) begin
                writeback_valid_d = 1'b0;
                writeback_cycle_d = 3'd0;
            end else begin
                writeback_cycle_d = writeback_cycle_q + 3'd1;
            end
        end

        if (execute_valid_q) begin
            if (execute_finishing) begin
                execute_valid_d = 1'b0;
                execute_cycle_d = 5'd0;
            end else begin
                execute_cycle_d = execute_cycle_q + 5'd1;
            end
        end

        if (capture_valid_q) begin
            if (capture_finishing) begin
                capture_valid_d = 1'b0;
                capture_cycle_d = 3'd0;
            end else begin
                capture_cycle_d = capture_cycle_q + 3'd1;
            end
        end

        if (decode_valid_q) begin
            decode_valid_d = 1'b0;

            if (!capture_valid_q || capture_finishing) begin
                capture_valid_d = 1'b1;
                capture_cycle_d = 3'd0;
                capture_opcode_d = decode_opcode_q;
                capture_d_d = decode_d_q;
                capture_a_d = decode_a_q;
                capture_b_d = decode_b_q;
            end
        end

        if (capture_finishing) begin
            if (!execute_valid_q || execute_finishing) begin
                execute_valid_d = 1'b1;
                execute_cycle_d = 5'd0;
                execute_opcode_d = capture_opcode_q;
                execute_d_d = capture_d_q;
            end
        end

        if (execute_finishing) begin
            if (!writeback_valid_q || writeback_finishing) begin
                writeback_valid_d = 1'b1;
                writeback_cycle_d = 3'd0;
                writeback_d_d = execute_d_q;
            end
        end

        if (issue_fire) begin
            decode_valid_d = 1'b1;
            decode_opcode_d = issue_opcode;
            decode_d_d = issue_d_base;
            decode_a_d = issue_a_base;
            decode_b_d = issue_b_base;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            issue_cooldown_q <= 4'd0;
            issue_accepted <= 1'b0;
            illegal_issue <= 1'b0;

            decode_valid_q <= 1'b0;
            decode_opcode_q <= 4'd0;
            decode_d_q <= 8'd0;
            decode_a_q <= 8'd0;
            decode_b_q <= 8'd0;

            capture_valid_q <= 1'b0;
            capture_cycle_q <= 3'd0;
            capture_opcode_q <= 4'd0;
            capture_d_q <= 8'd0;
            capture_a_q <= 8'd0;
            capture_b_q <= 8'd0;

            execute_valid_q <= 1'b0;
            execute_cycle_q <= 5'd0;
            execute_opcode_q <= 4'd0;
            execute_d_q <= 8'd0;

            writeback_valid_q <= 1'b0;
            writeback_cycle_q <= 3'd0;
            writeback_d_q <= 8'd0;
        end else begin
            issue_cooldown_q <= issue_cooldown_d;
            issue_accepted <= issue_fire;
            illegal_issue <= invalid_fire;

            decode_valid_q <= decode_valid_d;
            decode_opcode_q <= decode_opcode_d;
            decode_d_q <= decode_d_d;
            decode_a_q <= decode_a_d;
            decode_b_q <= decode_b_d;

            capture_valid_q <= capture_valid_d;
            capture_cycle_q <= capture_cycle_d;
            capture_opcode_q <= capture_opcode_d;
            capture_d_q <= capture_d_d;
            capture_a_q <= capture_a_d;
            capture_b_q <= capture_b_d;

            execute_valid_q <= execute_valid_d;
            execute_cycle_q <= execute_cycle_d;
            execute_opcode_q <= execute_opcode_d;
            execute_d_q <= execute_d_d;

            writeback_valid_q <= writeback_valid_d;
            writeback_cycle_q <= writeback_cycle_d;
            writeback_d_q <= writeback_d_d;
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (reset_n) begin
            if (rf_read_valid && rf_write_valid) begin
                $fatal(1, "matrix control scheduled simultaneous VGPR read and write");
            end
            if (issue_accepted && issue_dependency_hazard) begin
                $fatal(1, "matrix control accepted an instruction with a pending-destination dependency");
            end
            if (decode_valid_q && capture_valid_q && !capture_finishing) begin
                $fatal(1, "matrix decode reached an occupied capture slot");
            end
            if (capture_finishing && execute_valid_q && !execute_finishing) begin
                $fatal(1, "matrix capture reached an occupied execute slot");
            end
            if (execute_finishing && writeback_valid_q && !writeback_finishing) begin
                $fatal(1, "matrix execute reached an occupied writeback slot");
            end
        end
    end
`endif

endmodule
