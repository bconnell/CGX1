// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_matrix_int8_engine_shell_tb;

    logic clk = 1'b0;
    logic reset_n = 1'b0;

    logic issue_valid;
    logic [3:0] issue_opcode;
    logic issue_full_wave_active;
    logic [7:0] issue_d_base;
    logic [7:0] issue_a_base;
    logic [7:0] issue_b_base;
    logic issue_ready;
    logic issue_legal;
    logic issue_accepted;
    logic illegal_issue;

    logic rf_read_valid;
    logic [7:0] rf_read_addr0;
    logic [7:0] rf_read_addr1;
    logic [1023:0] rf_read_data0;
    logic [1023:0] rf_read_data1;
    logic rf_write_valid;
    logic [7:0] rf_write_addr;
    logic [1023:0] rf_write_data;

    logic [255:0] ordinary_read_mask;
    logic [255:0] ordinary_write_mask;
    logic ordinary_uses_read_ports;
    logic ordinary_uses_write_port;
    logic ordinary_raw_hazard;
    logic ordinary_waw_hazard;
    logic ordinary_war_hazard;
    logic ordinary_read_port_conflict;
    logic ordinary_write_port_conflict;
    logic ordinary_ready;

    logic [255:0] matrix_source_pending_mask;
    logic [255:0] matrix_destination_pending_mask;
    logic destination_complete_valid;

    logic [1023:0] vgpr [0:255];

    integer reg_index;
    integer row;
    integer column;
    integer k;
    integer expected_value;

    always #5 clk = ~clk;

    assign rf_read_data0 = vgpr[rf_read_addr0];
    assign rf_read_data1 = vgpr[rf_read_addr1];

    always_ff @(posedge clk) begin
        if (reset_n && rf_write_valid) begin
            vgpr[rf_write_addr] <= rf_write_data;
        end
    end

    cgx1_matrix_int8_engine_shell dut (
        .clk(clk),
        .reset_n(reset_n),
        .issue_valid(issue_valid),
        .issue_opcode(issue_opcode),
        .issue_full_wave_active(issue_full_wave_active),
        .issue_d_base(issue_d_base),
        .issue_a_base(issue_a_base),
        .issue_b_base(issue_b_base),
        .issue_ready(issue_ready),
        .issue_legal(issue_legal),
        .issue_accepted(issue_accepted),
        .illegal_issue(illegal_issue),
        .rf_read_valid(rf_read_valid),
        .rf_read_addr0(rf_read_addr0),
        .rf_read_addr1(rf_read_addr1),
        .rf_read_data0(rf_read_data0),
        .rf_read_data1(rf_read_data1),
        .rf_write_valid(rf_write_valid),
        .rf_write_addr(rf_write_addr),
        .rf_write_data(rf_write_data),
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
        .matrix_destination_pending_mask(matrix_destination_pending_mask),
        .destination_complete_valid(destination_complete_valid)
    );

    task automatic clear_ordinary;
        begin
            ordinary_read_mask = '0;
            ordinary_write_mask = '0;
            ordinary_uses_read_ports = 1'b0;
            ordinary_uses_write_port = 1'b0;
        end
    endtask

    task automatic set_a(
        input integer in_row,
        input integer in_k,
        input integer signed value
    );
        integer in_lane;
        integer in_reg;
        integer in_byte;
        begin
            in_lane = (in_row * 2) + (in_k / 16);
            in_reg = (in_k % 16) / 4;
            in_byte = (in_k % 16) % 4;
            vgpr[64 + in_reg][(in_lane * 32) + (in_byte * 8) +: 8]
                = value[7:0];
        end
    endtask

    task automatic set_b(
        input integer in_k,
        input integer in_column,
        input integer signed value
    );
        integer in_reg;
        integer in_byte;
        begin
            in_reg = in_column / 4;
            in_byte = in_column % 4;
            vgpr[68 + in_reg][(in_k * 32) + (in_byte * 8) +: 8]
                = value[7:0];
        end
    endtask

    task automatic set_c(
        input integer in_row,
        input integer in_column,
        input integer signed value
    );
        integer in_lane;
        integer in_reg;
        begin
            in_lane = (in_row * 2) + (in_column / 8);
            in_reg = in_column % 8;
            vgpr[32 + in_reg][in_lane * 32 +: 32] = value[31:0];
        end
    endtask

    function automatic signed [31:0] get_d(
        input integer in_row,
        input integer in_column
    );
        integer out_lane;
        integer out_reg;
        begin
            out_lane = (in_row * 2) + (in_column / 8);
            out_reg = in_column % 8;
            get_d = $signed(vgpr[32 + out_reg][out_lane * 32 +: 32]);
        end
    endfunction

    initial begin
        issue_valid = 1'b0;
        issue_opcode = 4'd0;
        issue_full_wave_active = 1'b1;
        issue_d_base = 8'd0;
        issue_a_base = 8'd0;
        issue_b_base = 8'd0;
        clear_ordinary();

        for (reg_index = 0; reg_index < 256; reg_index = reg_index + 1) begin
            vgpr[reg_index] = '0;
        end

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        // The shell is intentionally INT8-only at this boundary.
        @(negedge clk);
        issue_valid = 1'b1;
        issue_opcode = 4'h0;
        issue_d_base = 8'd32;
        issue_a_base = 8'd64;
        issue_b_base = 8'd68;
        #1;
        if (issue_legal || issue_accepted || !illegal_issue) begin
            $fatal(1, "INT8 shell failed to reject a non-INT8 opcode");
        end
        @(negedge clk);
        issue_valid = 1'b0;

        for (row = 0; row < 16; row = row + 1) begin
            for (k = 0; k < 32; k = k + 1) begin
                set_a(row, k, ((row + k * 2) % 11) - 5);
            end
        end
        for (k = 0; k < 32; k = k + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                set_b(k, column, ((k * 3 + column) % 13) - 6);
            end
        end
        for (row = 0; row < 16; row = row + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                set_c(row, column, row * 200 + column * 3);
            end
        end

        @(negedge clk);
        issue_valid = 1'b1;
        issue_opcode = 4'h6;
        issue_d_base = 8'd32;
        issue_a_base = 8'd64;
        issue_b_base = 8'd68;
        #1;
        if (!issue_ready || !issue_legal || illegal_issue) begin
            $fatal(1, "legal INT8 shell issue was not ready");
        end

        @(posedge clk);
        #1;
        if (!issue_accepted) begin
            $fatal(1, "legal INT8 shell issue was not accepted");
        end
        if (!matrix_source_pending_mask[64]
            || !matrix_source_pending_mask[68]
            || !matrix_destination_pending_mask[32]) begin
            $fatal(1, "INT8 shell scoreboard did not reserve accepted registers");
        end

        @(negedge clk);
        issue_valid = 1'b0;

        // A source overwrite must wait while matrix capture owns A/B.
        ordinary_write_mask = '0;
        ordinary_write_mask[64] = 1'b1;
        ordinary_uses_write_port = 1'b1;
        #1;
        if (!ordinary_war_hazard || ordinary_ready) begin
            $fatal(1, "INT8 shell did not block ordinary source overwrite");
        end

        while (matrix_source_pending_mask[64]) begin
            @(posedge clk);
            #1;
        end
        clear_ordinary();

        // D remains pending until the complete writeback sequence finishes.
        ordinary_read_mask = '0;
        ordinary_read_mask[32] = 1'b1;
        ordinary_uses_read_ports = 1'b1;
        #1;
        if (!ordinary_raw_hazard || ordinary_ready) begin
            $fatal(1, "INT8 shell did not block ordinary read of pending D");
        end
        clear_ordinary();

        while (!destination_complete_valid) begin
            @(posedge clk);
            #1;
        end
        @(posedge clk);
        #1;

        if (|matrix_destination_pending_mask) begin
            $fatal(1, "INT8 shell destination reservation did not clear");
        end

        for (row = 0; row < 16; row = row + 1) begin
            for (column = 0; column < 16; column = column + 1) begin
                expected_value = row * 200 + column * 3;
                for (k = 0; k < 32; k = k + 1) begin
                    expected_value =
                        expected_value
                        + ((((row + k * 2) % 11) - 5)
                           * (((k * 3 + column) % 13) - 6));
                end
                if (get_d(row, column) !== expected_value[31:0]) begin
                    $fatal(
                        1,
                        "INT8 shell result mismatch at row %0d column %0d",
                        row,
                        column
                    );
                end
            end
        end

        $display("[pass] CGX 1 signed INT8 matrix-engine shell checks passed.");
        $finish;
    end

endmodule
