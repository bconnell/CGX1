// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_pooled_vgpr_matrix_subsystem_tb;
    localparam integer ROWS=32, SLOTS=4, ROW_WIDTH=5, SLOT_WIDTH=2;
    logic clk=0, reset_n=0;
    logic reserve_valid; logic [SLOT_WIDTH-1:0] reserve_wave_slot; logic [8:0] reserve_register_count; logic reserve_ready,reserve_accepted;
    logic activate_valid; logic [SLOT_WIDTH-1:0] activate_wave_slot; logic activate_ready,activate_accepted;
    logic release_valid; logic [SLOT_WIDTH-1:0] release_wave_slot; logic release_quiescent,release_ready,release_accepted; logic [SLOTS-1:0] wave_execution_busy;
    logic restore_valid; logic [SLOT_WIDTH-1:0] restore_wave_slot; logic [7:0] restore_register; logic [1023:0] restore_data; logic restore_ready;
    logic [SLOTS-1:0] matrix_request_valid; logic [(SLOTS*8)-1:0] matrix_request_d_base,matrix_request_a_base,matrix_request_b_base;
    logic [SLOTS-1:0] matrix_request_preflight_ready,matrix_request_gated_valid;
    logic matrix_rf_read_valid; logic [SLOT_WIDTH-1:0] matrix_rf_read_wave_slot; logic [7:0] matrix_rf_read_addr0,matrix_rf_read_addr1;
    logic matrix_rf_read_ready,matrix_rf_read0_initialized,matrix_rf_read1_initialized; logic [1023:0] matrix_rf_read_data0,matrix_rf_read_data1;
    logic matrix_rf_write_valid; logic [SLOT_WIDTH-1:0] matrix_rf_write_wave_slot; logic [7:0] matrix_rf_write_addr; logic [1023:0] matrix_rf_write_data; logic matrix_rf_write_ready;
    integer r,timeout;

    always #5 clk=~clk;
    cgx1_pooled_vgpr_matrix_subsystem #(.PHYSICAL_ROWS(ROWS),.RESIDENT_WAVE_SLOTS(SLOTS),.ROW_WIDTH(ROW_WIDTH),.WAVE_SLOT_WIDTH(SLOT_WIDTH)) dut (.*);

    function automatic [1023:0] pattern(input logic [7:0] tag); integer lane; begin pattern='0; for(lane=0;lane<32;lane=lane+1) pattern[(lane*32)+:32]={tag,16'hBEEF,lane[7:0]}; end endfunction

    task automatic reserve72(input logic [SLOT_WIDTH-1:0] slot); begin
        @(negedge clk); reserve_wave_slot=slot; reserve_register_count=9'd72; reserve_valid=1; #1;
        if(!reserve_ready) $fatal(1,"72-VGPR reservation blocked"); @(posedge clk); #1; @(negedge clk); reserve_valid=0;
        timeout=0; activate_wave_slot=slot; while(!dut.allocation_sanitized_bitmap[slot]) begin @(posedge clk); #1; timeout=timeout+1; if(timeout>20) $fatal(1,"sanitization timeout"); end
    end endtask

    task automatic restore_reg(input logic [SLOT_WIDTH-1:0] slot,input logic [7:0] register_index,input logic [7:0] tag); begin
        @(negedge clk); restore_wave_slot=slot; restore_register=register_index; restore_data=pattern(tag); restore_valid=1; #1;
        if(!restore_ready) $fatal(1,"privileged restore write blocked"); @(posedge clk); #1; @(negedge clk); restore_valid=0;
    end endtask

    task automatic activate(input logic [SLOT_WIDTH-1:0] slot); begin
        @(negedge clk); activate_wave_slot=slot; activate_valid=1; #1; if(!activate_ready) $fatal(1,"activation blocked after sanitization");
        @(posedge clk); #1; @(negedge clk); activate_valid=0;
    end endtask

    initial begin
        reserve_valid=0; reserve_wave_slot='0; reserve_register_count='0; activate_valid=0; activate_wave_slot='0;
        release_valid=0; release_wave_slot='0; release_quiescent=0; wave_execution_busy='0; restore_valid=0; restore_wave_slot='0; restore_register='0; restore_data='0;
        matrix_request_valid='0; matrix_request_d_base='0; matrix_request_a_base='0; matrix_request_b_base='0;
        matrix_rf_read_valid=0; matrix_rf_read_wave_slot='0; matrix_rf_read_addr0='0; matrix_rf_read_addr1='0;
        matrix_rf_write_valid=0; matrix_rf_write_wave_slot='0; matrix_rf_write_addr='0; matrix_rf_write_data='0;
        repeat(3) @(posedge clk); @(negedge clk); reset_n=1;

        reserve72(0);
        for(r=32;r<40;r=r+1) restore_reg(0,r[7:0],8'hC0+r[7:0]);
        for(r=64;r<72;r=r+1) restore_reg(0,r[7:0],8'hA0+r[7:0]);
        activate(0);

        matrix_request_d_base[0 +: 8]=8'd32; matrix_request_a_base[0 +: 8]=8'd64; matrix_request_b_base[0 +: 8]=8'd68; matrix_request_valid[0]=1; #1;
        if(!matrix_request_preflight_ready[0] || !matrix_request_gated_valid[0]) $fatal(1,"restored wave failed matrix preflight");

        matrix_request_d_base[0 +: 8]=8'd33; #1;
        if(!matrix_request_preflight_ready[0] || !matrix_request_gated_valid[0])
            $fatal(1,"illegal matrix layout was swallowed by pooled preflight");
        matrix_request_d_base[0 +: 8]=8'd32; #1;

        matrix_rf_read_wave_slot=0; matrix_rf_read_addr0=8'd64; matrix_rf_read_addr1=8'd68; matrix_rf_read_valid=1; #1;
        if(!matrix_rf_read_ready || !matrix_rf_read0_initialized || !matrix_rf_read1_initialized) $fatal(1,"matrix pooled capture read failed");
        if(matrix_rf_read_data0!==pattern(8'hA0+8'd64) || matrix_rf_read_data1!==pattern(8'hA0+8'd68)) $fatal(1,"matrix pooled capture data mismatch");
        matrix_rf_read_valid=0;

        reserve72(1); restore_wave_slot=1; restore_register=8'd0; restore_data=pattern(8'h55); restore_valid=1;
        release_wave_slot=1; release_valid=1; release_quiescent=1; #1;
        if(release_ready || release_accepted) $fatal(1,"reserved wave released while restore was pending");
        release_valid=0; release_quiescent=0;
        matrix_rf_write_wave_slot=0; matrix_rf_write_addr=8'd32; matrix_rf_write_data=pattern(8'hD0); matrix_rf_write_valid=1; #1;
        if(!matrix_rf_write_ready || restore_ready) $fatal(1,"matrix writeback did not have priority over restore");
        @(posedge clk); #1; @(negedge clk); matrix_rf_write_valid=0; #1;
        if(!restore_ready) $fatal(1,"restore did not proceed after matrix traffic cleared");
        @(posedge clk); #1; @(negedge clk); restore_valid=0;

        restore_wave_slot=1; restore_register=8'd1; restore_data=pattern(8'h56); restore_valid=1;
        activate_wave_slot=1; activate_valid=1; #1;
        if(activate_ready || activate_accepted) $fatal(1,"activation raced a pending restore");
        @(posedge clk); #1; @(negedge clk); activate_valid=0; restore_valid=0;

        wave_execution_busy[0]=1; release_wave_slot=0; release_quiescent=1; release_valid=1; #1;
        if(release_ready || release_accepted) $fatal(1,"busy wave was releasable");
        wave_execution_busy[0]=0; matrix_rf_read_wave_slot=0; matrix_rf_read_addr0=8'd64; matrix_rf_read_addr1=8'd68; matrix_rf_read_valid=1; #1;
        if(release_ready || release_accepted) $fatal(1,"wave released during matrix RF read");
        matrix_rf_read_valid=0; release_valid=0; release_quiescent=0;

        $display("[pass] CGX 1 pooled VGPR matrix subsystem lifecycle/preflight/access checks passed.");
        $finish;
    end
endmodule
