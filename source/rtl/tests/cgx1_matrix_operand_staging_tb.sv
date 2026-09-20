// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_matrix_operand_staging_tb;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic capture_valid;
    logic [2:0] capture_cycle;
    logic [1023:0] rf_read_data0;
    logic [1023:0] rf_read_data1;
    logic active_operands_valid;
    logic active_operands_loaded;
    logic [4095:0] active_a_words;
    logic [4095:0] active_b_words;
    logic [8191:0] active_c_words;

    logic [4095:0] first_a;
    logic [4095:0] first_b;
    logic [8191:0] first_c;

    integer i;

    always #5 clk = ~clk;

    cgx1_matrix_operand_staging dut (
        .clk(clk),
        .reset_n(reset_n),
        .capture_valid(capture_valid),
        .capture_cycle(capture_cycle),
        .rf_read_data0(rf_read_data0),
        .rf_read_data1(rf_read_data1),
        .active_operands_valid(active_operands_valid),
        .active_operands_loaded(active_operands_loaded),
        .active_a_words(active_a_words),
        .active_b_words(active_b_words),
        .active_c_words(active_c_words)
    );

    function automatic [1023:0] make_wave(input integer tag);
        integer lane;
        reg [1023:0] wave;
        begin
            wave = '0;
            for (lane = 0; lane < 32; lane = lane + 1) begin
                wave[(lane * 32) +: 32] = (tag << 8) | lane;
            end
            make_wave = wave;
        end
    endfunction

    task automatic reset_dut;
        begin
            reset_n = 1'b0;
            capture_valid = 1'b0;
            capture_cycle = 3'd0;
            rf_read_data0 = '0;
            rf_read_data1 = '0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            reset_n = 1'b1;
            @(posedge clk);
            #1;

            if (active_operands_valid || active_operands_loaded) begin
                $fatal(1, "matrix staging was unexpectedly valid after reset");
            end
        end
    endtask

    task automatic drive_capture_cycle(
        input integer operation_base,
        input integer cycle_index
    );
        integer pair;
        begin
            @(negedge clk);
            capture_valid = 1'b1;
            capture_cycle = cycle_index[2:0];

            if (cycle_index < 4) begin
                rf_read_data0 = make_wave(operation_base + 16 + cycle_index);
                rf_read_data1 = make_wave(operation_base + 32 + cycle_index);
            end else begin
                pair = (cycle_index - 4) * 2;
                rf_read_data0 = make_wave(operation_base + 48 + pair);
                rf_read_data1 = make_wave(operation_base + 48 + pair + 1);
            end

            @(posedge clk);
            #1;
        end
    endtask

    task automatic check_active(input integer operation_base);
        integer reg_index;
        begin
            if (!active_operands_valid) begin
                $fatal(1, "matrix active operands were not marked valid");
            end

            for (reg_index = 0; reg_index < 4; reg_index = reg_index + 1) begin
                if (active_a_words[(reg_index * 1024) +: 1024]
                    !== make_wave(operation_base + 16 + reg_index)) begin
                    $fatal(1, "matrix A active staging mismatch at register %0d", reg_index);
                end
                if (active_b_words[(reg_index * 1024) +: 1024]
                    !== make_wave(operation_base + 32 + reg_index)) begin
                    $fatal(1, "matrix B active staging mismatch at register %0d", reg_index);
                end
            end

            for (reg_index = 0; reg_index < 8; reg_index = reg_index + 1) begin
                if (active_c_words[(reg_index * 1024) +: 1024]
                    !== make_wave(operation_base + 48 + reg_index)) begin
                    $fatal(1, "matrix C active staging mismatch at register %0d", reg_index);
                end
            end
        end
    endtask

    initial begin
        reset_dut();

        for (i = 0; i < 8; i = i + 1) begin
            drive_capture_cycle(256, i);
            if ((i == 7) != active_operands_loaded) begin
                $fatal(1, "matrix active-load pulse mismatch on first operation");
            end
        end

        check_active(256);
        first_a = active_a_words;
        first_b = active_b_words;
        first_c = active_c_words;

        // Start capturing a second operation. The active execution operands
        // must remain unchanged through capture cycles 0..6.
        for (i = 0; i < 7; i = i + 1) begin
            drive_capture_cycle(512, i);
            if (active_operands_loaded) begin
                $fatal(1, "matrix active operands committed too early");
            end
            if (active_a_words !== first_a
                || active_b_words !== first_b
                || active_c_words !== first_c) begin
                $fatal(1, "active matrix operands changed before capture commit");
            end
        end

        drive_capture_cycle(512, 7);
        if (!active_operands_loaded) begin
            $fatal(1, "matrix active operands did not commit on capture cycle 7");
        end
        check_active(512);

        @(negedge clk);
        capture_valid = 1'b0;
        @(posedge clk);
        #1;
        if (active_operands_loaded) begin
            $fatal(1, "matrix active-load pulse did not clear");
        end

        $display("[pass] CGX 1 matrix operand staging RTL checks passed.");
        $finish;
    end

endmodule
