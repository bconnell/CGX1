// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

module cgx1_matrix_pooled_vgpr_frontend_tb;
    localparam integer PHYSICAL_ROWS = 32;
    localparam integer ROW_WIDTH = 5;
    logic allocation_active;
    logic [ROW_WIDTH-1:0] allocation_row_base;
    logic [8:0] allocation_register_count;
    logic [(PHYSICAL_ROWS*8)-1:0] valid_bitmap;
    logic [7:0] destination_base, source_a_base, source_b_base;
    logic matrix_issue_legal;
    logic capture_valid;
    logic [2:0] capture_cycle;
    logic capture_addresses_valid;
    logic [ROW_WIDTH-1:0] capture_read0_row, capture_read1_row;
    logic [2:0] capture_read0_bank, capture_read1_bank;
    logic writeback_valid;
    logic [2:0] writeback_cycle;
    logic writeback_address_valid;
    logic [ROW_WIDTH-1:0] writeback_row;
    logic [2:0] writeback_bank;
    integer r;
    integer row;
    integer bank;

    cgx1_matrix_pooled_vgpr_frontend #(.PHYSICAL_ROWS(PHYSICAL_ROWS),.ROW_WIDTH(ROW_WIDTH)) dut (
        .allocation_active(allocation_active), .allocation_row_base(allocation_row_base),
        .allocation_register_count(allocation_register_count), .valid_bitmap(valid_bitmap),
        .destination_base(destination_base), .source_a_base(source_a_base), .source_b_base(source_b_base),
        .matrix_issue_legal(matrix_issue_legal), .capture_valid(capture_valid), .capture_cycle(capture_cycle),
        .capture_addresses_valid(capture_addresses_valid), .capture_read0_row(capture_read0_row),
        .capture_read0_bank(capture_read0_bank), .capture_read1_row(capture_read1_row),
        .capture_read1_bank(capture_read1_bank), .writeback_valid(writeback_valid),
        .writeback_cycle(writeback_cycle), .writeback_address_valid(writeback_address_valid),
        .writeback_row(writeback_row), .writeback_bank(writeback_bank)
    );

    task automatic mark_valid(input integer architectural_register);
        begin
            row = allocation_row_base + (architectural_register >> 3);
            bank = architectural_register & 7;
            valid_bitmap[(row*8)+bank]=1'b1;
        end
    endtask

    initial begin
        allocation_active=1'b1; allocation_row_base=5'd5; allocation_register_count=9'd72;
        destination_base=8'd32; source_a_base=8'd64; source_b_base=8'd68;
        valid_bitmap='0; capture_valid=1'b0; capture_cycle='0; writeback_valid=1'b0; writeback_cycle='0;
        for(r=32;r<40;r=r+1) mark_valid(r);
        for(r=64;r<72;r=r+1) mark_valid(r);
        #1;
        if(!matrix_issue_legal) $fatal(1,"canonical pooled matrix preflight was rejected");

        capture_valid=1'b1;
        for(r=0;r<4;r=r+1) begin
            capture_cycle=r[2:0]; #1;
            if(!capture_addresses_valid || capture_read0_row!=5'd13 || capture_read1_row!=5'd13
               || capture_read0_bank!=r[2:0] || capture_read1_bank!=(r+4))
                $fatal(1,"A/B pooled capture mapping mismatch at cycle %0d",r);
        end
        for(r=4;r<8;r=r+1) begin
            capture_cycle=r[2:0]; #1;
            if(!capture_addresses_valid) $fatal(1,"C pooled capture mapping invalid at cycle %0d",r);
            if(capture_read0_row!=5'd9 || capture_read1_row!=5'd9)
                $fatal(1,"C pooled row mapping mismatch at cycle %0d",r);
        end
        capture_valid=1'b0;

        writeback_valid=1'b1;
        for(r=0;r<8;r=r+1) begin
            writeback_cycle=r[2:0]; #1;
            if(!writeback_address_valid || writeback_row!=5'd9 || writeback_bank!=r[2:0])
                $fatal(1,"pooled writeback mapping mismatch at cycle %0d",r);
        end
        writeback_valid=1'b0;

        source_b_base=8'd64; #1;
        if(!matrix_issue_legal) $fatal(1,"exact A/B alias was rejected");
        capture_valid=1'b1; capture_cycle=3'd0; #1;
        if(capture_read0_row!=capture_read1_row || capture_read0_bank!=capture_read1_bank)
            $fatal(1,"exact A/B alias did not map to one physical address");

        $display("[pass] CGX 1 pooled matrix frontend mapping checks passed.");
        $finish;
    end
endmodule
