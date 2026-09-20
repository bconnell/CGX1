// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_matrix_result_staging_tb;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic result_load_valid;
    logic [8191:0] result_words;
    logic writeback_valid;
    logic [2:0] writeback_cycle;
    logic result_valid;
    logic result_loaded;
    logic result_consumed;
    logic [1023:0] rf_write_data;

    integer i;

    always #5 clk = ~clk;

    cgx1_matrix_result_staging dut (
        .clk(clk),
        .reset_n(reset_n),
        .result_load_valid(result_load_valid),
        .result_words(result_words),
        .writeback_valid(writeback_valid),
        .writeback_cycle(writeback_cycle),
        .result_valid(result_valid),
        .result_loaded(result_loaded),
        .result_consumed(result_consumed),
        .rf_write_data(rf_write_data)
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

    task automatic load_result(input integer base_tag);
        integer reg_index;
        begin
            @(negedge clk);
            result_words = '0;
            for (reg_index = 0; reg_index < 8; reg_index = reg_index + 1) begin
                result_words[(reg_index * 1024) +: 1024] =
                    make_wave(base_tag + reg_index);
            end
            result_load_valid = 1'b1;
            @(posedge clk);
            #1;
            if (!result_valid || !result_loaded) begin
                $fatal(1, "matrix output-result staging did not load");
            end
            @(negedge clk);
            result_load_valid = 1'b0;
        end
    endtask

    task automatic drain_result(input integer base_tag);
        begin
            for (i = 0; i < 8; i = i + 1) begin
                @(negedge clk);
                writeback_valid = 1'b1;
                writeback_cycle = i[2:0];
                #1;
                if (rf_write_data !== make_wave(base_tag + i)) begin
                    $fatal(
                        1,
                        "matrix output-result writeback data mismatch at cycle %0d",
                        i
                    );
                end

                @(posedge clk);
                #1;
                if ((i == 7) != result_consumed) begin
                    $fatal(1, "matrix output-result consumed pulse mismatch");
                end
                if ((i != 7) != result_valid) begin
                    $fatal(1, "matrix output-result valid-state mismatch");
                end
            end

            @(negedge clk);
            writeback_valid = 1'b0;
            writeback_cycle = 3'd0;
        end
    endtask

    initial begin
        result_load_valid = 1'b0;
        result_words = '0;
        writeback_valid = 1'b0;
        writeback_cycle = 3'd0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        @(posedge clk);
        #1;

        if (result_valid || result_loaded || result_consumed) begin
            $fatal(1, "matrix output-result staging was not empty after reset");
        end

        load_result(256);
        drain_result(256);

        if (result_valid) begin
            $fatal(1, "matrix output-result staging remained occupied after drain");
        end

        load_result(512);
        drain_result(512);

        $display("[pass] CGX 1 matrix output-result staging RTL checks passed.");
        $finish;
    end

endmodule
