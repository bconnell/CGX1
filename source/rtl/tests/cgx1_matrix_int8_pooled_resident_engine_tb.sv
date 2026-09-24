// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_matrix_int8_pooled_resident_engine_tb;
    localparam integer ROWS = 9;
    localparam integer SLOTS = 2;
    localparam integer ROW_WIDTH = 4;
    localparam integer SLOT_WIDTH = 1;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic reserve_valid;
    logic [SLOT_WIDTH-1:0] reserve_wave_slot;
    logic [8:0] reserve_register_count;
    logic reserve_ready;
    logic reserve_accepted;
    logic activate_valid;
    logic [SLOT_WIDTH-1:0] activate_wave_slot;
    logic activate_ready;
    logic activate_accepted;
    logic release_valid;
    logic [SLOT_WIDTH-1:0] release_wave_slot;
    logic release_quiescent;
    logic release_ready;
    logic release_accepted;
    logic restore_valid;
    logic [SLOT_WIDTH-1:0] restore_wave_slot;
    logic [7:0] restore_register;
    logic [1023:0] restore_data;
    logic restore_ready;
    logic [SLOTS-1:0] matrix_request_valid;
    logic [SLOTS-1:0] matrix_request_full_wave_active;
    logic [(SLOTS*8)-1:0] matrix_request_d_base;
    logic [(SLOTS*8)-1:0] matrix_request_a_base;
    logic [(SLOTS*8)-1:0] matrix_request_b_base;
    logic [SLOTS-1:0] matrix_request_ready;
    logic [SLOTS-1:0] matrix_request_accepted;
    logic illegal_issue;
    logic [SLOT_WIDTH-1:0] illegal_wave_slot;
    logic ordinary_issue_valid;
    logic [SLOT_WIDTH-1:0] ordinary_wave_slot;
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
    logic ordinary_issue_accepted;
    logic [SLOTS-1:0] resident_wave_busy;

    logic [1023:0] c_word [0:7];
    integer reg_index;
    integer timeout;

    always #5 clk = ~clk;

    cgx1_matrix_int8_pooled_resident_engine #(
        .PHYSICAL_ROWS(ROWS),
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .ROW_WIDTH(ROW_WIDTH),
        .WAVE_SLOT_WIDTH(SLOT_WIDTH)
    ) dut (.*);

    function automatic [1023:0] c_pattern(input logic [7:0] register_tag);
        integer lane;
        begin
            c_pattern = '0;
            for (lane = 0; lane < 32; lane = lane + 1) begin
                c_pattern[(lane*32)+:32] = {8'hC1, register_tag, 8'h5A, lane[7:0]};
            end
        end
    endfunction

    task automatic reserve72(input logic [SLOT_WIDTH-1:0] slot);
        begin
            @(negedge clk);
            reserve_wave_slot = slot;
            reserve_register_count = 9'd72;
            reserve_valid = 1'b1;
            #1;
            if (!reserve_ready) $fatal(1, "pooled resident 72-VGPR reservation blocked");
            @(posedge clk); #1;
            @(negedge clk);
            reserve_valid = 1'b0;
            timeout = 0;
            while (!dut.pooled.allocation_sanitized_bitmap[slot]) begin
                @(posedge clk); #1;
                timeout = timeout + 1;
                if (timeout > 20) $fatal(1, "pooled resident sanitization timeout");
            end
        end
    endtask

    task automatic restore_word(
        input logic [SLOT_WIDTH-1:0] slot,
        input logic [7:0] register_index,
        input logic [1023:0] value);
        begin
            @(negedge clk);
            restore_wave_slot = slot;
            restore_register = register_index;
            restore_data = value;
            restore_valid = 1'b1;
            #1;
            if (!restore_ready) $fatal(1, "pooled resident restore blocked");
            @(posedge clk); #1;
            @(negedge clk);
            restore_valid = 1'b0;
        end
    endtask

    task automatic activate_wave(input logic [SLOT_WIDTH-1:0] slot);
        begin
            @(negedge clk);
            activate_wave_slot = slot;
            activate_valid = 1'b1;
            #1;
            if (!activate_ready) $fatal(1, "pooled resident activation blocked");
            @(posedge clk); #1;
            @(negedge clk);
            activate_valid = 1'b0;
        end
    endtask

    initial begin
        $display("[phase] pooled resident INT8 test start");
        reserve_valid = 1'b0;
        reserve_wave_slot = '0;
        reserve_register_count = '0;
        activate_valid = 1'b0;
        activate_wave_slot = '0;
        release_valid = 1'b0;
        release_wave_slot = '0;
        release_quiescent = 1'b0;
        restore_valid = 1'b0;
        restore_wave_slot = '0;
        restore_register = '0;
        restore_data = '0;
        matrix_request_valid = '0;
        matrix_request_full_wave_active = '1;
        matrix_request_d_base = '0;
        matrix_request_a_base = '0;
        matrix_request_b_base = '0;
        ordinary_issue_valid = 1'b0;
        ordinary_wave_slot = '0;
        ordinary_read_mask = '0;
        ordinary_write_mask = '0;
        ordinary_uses_read_ports = 1'b0;
        ordinary_uses_write_port = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        $display("[phase] reset released");

        reserve72(0);
        $display("[phase] wave0 reserved and sanitized");
        for (reg_index = 64; reg_index < 72; reg_index = reg_index + 1)
            restore_word(0, reg_index[7:0], '0);
        for (reg_index = 0; reg_index < 8; reg_index = reg_index + 1) begin
            c_word[reg_index] = c_pattern(8'd32 + reg_index[7:0]);
            restore_word(0, 8'd32 + reg_index[7:0], c_word[reg_index]);
        end
        activate_wave(0);
        $display("[phase] wave0 restored and active");

        matrix_request_d_base[0 +: 8] = 8'd32;
        matrix_request_a_base[0 +: 8] = 8'd64;
        matrix_request_b_base[0 +: 8] = 8'd68;
        matrix_request_valid[0] = 1'b1;
        timeout = 0;
        while (!matrix_request_ready[0]) begin
            @(negedge clk); #1;
            timeout = timeout + 1;
            if (timeout > 48) $fatal(1, "pooled resident legal request never became ready");
        end
        @(posedge clk); #1;
        @(negedge clk);
        matrix_request_valid[0] = 1'b0;
        $display("[phase] wave0 matrix request accepted");

        timeout = 0;
        while (!resident_wave_busy[0]) begin
            @(posedge clk); #1;
            timeout = timeout + 1;
            if (timeout > 8) $fatal(1, "pooled resident request never became busy");
        end

        release_wave_slot = 0;
        release_quiescent = 1'b1;
        release_valid = 1'b1;
        #1;
        if (release_ready || release_accepted)
            $fatal(1, "pooled resident release ignored in-flight matrix work");
        release_valid = 1'b0;
        release_quiescent = 1'b0;

        timeout = 0;
        while (resident_wave_busy[0]) begin
            if (timeout == 0) $display("[phase] waiting for wave0 matrix drain");
            @(posedge clk); #1;
            timeout = timeout + 1;
            if (timeout > 96) $fatal(1, "pooled resident matrix operation did not drain");
        end

        for (reg_index = 0; reg_index < 8; reg_index = reg_index + 1) begin
            if (dut.pooled.storage.data[4][reg_index] !== c_word[reg_index])
                $fatal(1, "pooled resident INT8 writeback mismatch at D+%0d", reg_index);
        end

        @(negedge clk);
        release_wave_slot = 0;
        release_quiescent = 1'b1;
        release_valid = 1'b1;
        #1;
        if (!release_ready || !release_accepted)
            $fatal(1, "completed wave0 allocation was not releasable");
        @(posedge clk); #1;
        @(negedge clk);
        release_valid = 1'b0;
        release_quiescent = 1'b0;

        reserve72(1);
        $display("[phase] wave0 result checked; starting wave1 negative path");
        for (reg_index = 64; reg_index < 72; reg_index = reg_index + 1) begin
            if (reg_index != 69) restore_word(1, reg_index[7:0], '0);
        end
        for (reg_index = 32; reg_index < 40; reg_index = reg_index + 1)
            restore_word(1, reg_index[7:0], c_pattern(reg_index[7:0]));
        activate_wave(1);
        $display("[phase] wave1 restored with one missing source and active");
        matrix_request_d_base[8 +: 8] = 8'd32;
        matrix_request_a_base[8 +: 8] = 8'd64;
        matrix_request_b_base[8 +: 8] = 8'd68;
        matrix_request_valid[1] = 1'b1;
        #1;
        if (matrix_request_ready[1] || matrix_request_accepted[1])
            $fatal(1, "pooled resident uninitialized legal request was admitted");

        matrix_request_full_wave_active[1] = 1'b0;
        $display("[phase] wave1 legal request correctly blocked; testing illegal forwarding");
        timeout = 0;
        while (!matrix_request_ready[1]) begin
            @(negedge clk); #1;
            timeout = timeout + 1;
            if (timeout > 48) $fatal(1, "illegal full-wave request was swallowed by pooled preflight");
        end
        @(posedge clk); #1;
        @(negedge clk);
        matrix_request_valid[1] = 1'b0;
        matrix_request_full_wave_active[1] = 1'b1;

        timeout = 0;
        while (!illegal_issue) begin
            @(posedge clk); #1;
            timeout = timeout + 1;
            if (timeout > 8) $fatal(1, "illegal full-wave request did not reach controller authority");
        end
        if (illegal_wave_slot != 1)
            $fatal(1, "illegal full-wave request reported wrong resident wave");

        $display("[pass] CGX 1 pooled resident INT8 engine integration checks passed.");
        $display("[phase] illegal forwarding observed");
        $finish;
    end

    initial begin : simulation_watchdog
        #20000;
        $fatal(1, "pooled resident INT8 integration simulation-time watchdog expired");
    end

endmodule
