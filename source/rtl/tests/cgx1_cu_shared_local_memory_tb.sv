// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_cu_shared_local_memory_tb;
    logic clk = 1'b0;
    logic reset_n = 1'b0;
    always #5 clk = ~clk;

    logic allocation_valid = 1'b0;
    logic allocation_ready;
    logic [7:0] allocation_workgroup_id = '0;
    logic [31:0] allocation_byte_count = '0;
    logic allocation_result_valid;
    logic allocation_accepted;
    logic [2:0] allocation_failure;
    logic [31:0] allocation_base_byte_address;

    logic release_valid = 1'b0;
    logic [7:0] release_workgroup_id = '0;
    logic release_ready;
    logic release_accepted;

    logic request_valid = 1'b0;
    logic request_ready;
    logic [7:0] request_workgroup_id = '0;
    logic [2:0] request_wave_id = '0;
    logic [7:0] request_transaction_tag = '0;
    logic request_write = 1'b0;
    logic [31:0] request_lane_mask = '0;
    logic [1023:0] request_byte_addresses_flat = '0;
    logic [1023:0] request_store_data_flat = '0;
    logic request_accepted;

    logic response_valid;
    logic response_ready = 1'b0;
    logic [7:0] response_workgroup_id;
    logic [2:0] response_wave_id;
    logic [7:0] response_transaction_tag;
    logic response_write;
    logic [31:0] response_lane_mask;
    logic [1023:0] response_lane_data_flat;
    logic [1:0] response_fault_code;
    logic [5:0] response_fault_lane;

    logic cancel_valid = 1'b0;
    logic [7:0] cancel_workgroup_id = '0;
    logic [2:0] cancel_wave_id = '0;
    logic cancel_ready;
    logic cancel_accepted;
    logic [7:0] outstanding_transaction_bitmap;

    cgx1_cu_shared_local_memory #(
        .CU_SHARED_BYTES(128),
        .BANK_COUNT(3),
        .MAX_WORKGROUP_CONTEXTS(4),
        .MAX_OUTSTANDING_TRANSACTIONS(8),
        .WORKGROUP_ID_WIDTH(8),
        .WAVE_ID_WIDTH(3),
        .TRANSACTION_TAG_WIDTH(8)
    ) dut (.*);

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic allocate_group(
        input logic [7:0] group_id,
        input logic [31:0] bytes,
        input logic expect_accepted,
        input logic [2:0] expect_failure,
        input logic [31:0] expect_base
    );
        integer timeout_cycles;
        begin
            @(negedge clk);
            while (!allocation_ready)
                @(negedge clk);
            allocation_workgroup_id = group_id;
            allocation_byte_count = bytes;
            allocation_valid = 1'b1;
            #1;
            if (!allocation_ready)
                $fatal(1, "allocation request was not ready before acceptance");
            @(posedge clk);
            #1;
            allocation_valid = 1'b0;
            timeout_cycles = 0;
            while (!allocation_result_valid && timeout_cycles < 200) begin
                tick();
                timeout_cycles = timeout_cycles + 1;
            end
            if (!allocation_result_valid)
                $fatal(1, "allocation did not report a result");
            if (allocation_accepted !== expect_accepted)
                $fatal(1, "allocation acceptance mismatch for group %0d", group_id);
            if (allocation_failure !== expect_failure)
                $fatal(1, "allocation failure mismatch for group %0d: got %0d expected %0d",
                    group_id, allocation_failure, expect_failure);
            if (expect_accepted && allocation_base_byte_address !== expect_base)
                $fatal(1, "allocation base mismatch for group %0d", group_id);
        end
    endtask

    task automatic submit_request(
        input logic [7:0] group_id,
        input logic [2:0] wave_id,
        input logic [7:0] tag,
        input logic write_access,
        input logic [31:0] lane_mask,
        input logic [1023:0] addresses,
        input logic [1023:0] store_data
    );
        begin
            @(negedge clk);
            request_workgroup_id = group_id;
            request_wave_id = wave_id;
            request_transaction_tag = tag;
            request_write = write_access;
            request_lane_mask = lane_mask;
            request_byte_addresses_flat = addresses;
            request_store_data_flat = store_data;
            request_valid = 1'b1;
            #1;
            if (!request_ready || !request_accepted)
                $fatal(1, "request %0d was not accepted", tag);
            @(posedge clk);
            #1;
            request_valid = 1'b0;
        end
    endtask

    task automatic expect_response(
        input logic [7:0] expected_tag,
        input logic [1:0] expected_fault,
        input logic [5:0] expected_fault_lane,
        input logic [31:0] expected_lane0_data,
        input logic check_lane0_data
    );
        integer timeout_cycles;
        begin
            timeout_cycles = 0;
            while (!response_valid && timeout_cycles < 64) begin
                tick();
                timeout_cycles = timeout_cycles + 1;
            end
            if (!response_valid)
                $fatal(1, "response %0d did not arrive", expected_tag);
            if (response_transaction_tag !== expected_tag)
                $fatal(1, "response tag mismatch: got %0d expected %0d",
                    response_transaction_tag, expected_tag);
            if (response_fault_code !== expected_fault
                || response_fault_lane !== expected_fault_lane)
                $fatal(1, "response fault mismatch for tag %0d", expected_tag);
            if (check_lane0_data
                && response_lane_data_flat[31:0] !== expected_lane0_data)
                $fatal(1, "response lane 0 data mismatch for tag %0d", expected_tag);
            @(negedge clk);
            response_ready = 1'b1;
            @(posedge clk);
            #1;
            response_ready = 1'b0;
        end
    endtask

    task automatic release_group(input logic [7:0] group_id);
        begin
            @(negedge clk);
            release_workgroup_id = group_id;
            release_valid = 1'b1;
            #1;
            if (!release_ready || !release_accepted)
                $fatal(1, "quiescent group %0d was not releasable", group_id);
            @(posedge clk);
            #1;
            release_valid = 1'b0;
        end
    endtask

    logic [1023:0] addresses;
    logic [1023:0] data;
    logic [1023:0] competing_addresses;
    logic [1023:0] competing_data;
    integer wait_cycles;
    integer lane;
    initial begin
        addresses = '0;
        data = '0;
        competing_addresses = '0;
        competing_data = '0;
        repeat (3) tick();
        reset_n = 1'b1;
        tick();

        allocate_group(8'd1, 32'd32, 1'b1, 3'd0, 32'd0);
        allocate_group(8'd2, 32'd32, 1'b1, 3'd0, 32'd32);
        allocate_group(8'd3, 32'd32, 1'b1, 3'd0, 32'd64);

        addresses[0+:32] = 32'd0;
        addresses[32+:32] = 32'd4;
        data[0+:32] = 32'h12345678;
        data[32+:32] = 32'habcdef01;
        submit_request(8'd1, 3'd0, 8'd1, 1'b1, 32'h00000003, addresses, data);
        @(negedge clk);
        request_workgroup_id = 8'd1;
        request_wave_id = 3'd0;
        request_transaction_tag = 8'd99;
        request_write = 1'b0;
        request_lane_mask = 32'h00000001;
        request_valid = 1'b1;
        #1;
        if (request_ready || request_accepted)
            $fatal(1, "wave accepted a second outstanding memory request");
        request_valid = 1'b0;
        if (!outstanding_transaction_bitmap[0])
            $fatal(1, "accepted store did not retain transaction ownership");
        @(negedge clk);
        release_workgroup_id = 8'd1;
        release_valid = 1'b1;
        #1;
        if (release_ready || release_accepted)
            $fatal(1, "in-flight shared memory was released early");
        release_valid = 1'b0;
        expect_response(8'd1, 2'd0, 6'h3f, 32'd0, 1'b0);
        if (outstanding_transaction_bitmap[0])
            $fatal(1, "consumed response retained transaction ownership");
        release_group(8'd1);

        addresses = '0;
        addresses[0+:32] = 32'd0;
        submit_request(8'd2, 3'd0, 8'd2, 1'b0, 32'h00000001, addresses, '0);
        expect_response(8'd2, 2'd0, 6'h3f, 32'd0, 1'b1);

        addresses[0+:32] = 32'd0;
        addresses[32+:32] = 32'd32;
        data[0+:32] = 32'hfeedface;
        data[32+:32] = 32'hbad0bad0;
        submit_request(8'd2, 3'd0, 8'd3, 1'b1, 32'h00000003, addresses, data);
        expect_response(8'd3, 2'd3, 6'd1, 32'd0, 1'b0);
        addresses[0+:32] = 32'd0;
        submit_request(8'd2, 3'd1, 8'd4, 1'b0, 32'h00000001, addresses, '0);
        expect_response(8'd4, 2'd0, 6'h3f, 32'd0, 1'b1);

        addresses[0+:32] = 32'd2;
        submit_request(8'd2, 3'd0, 8'd5, 1'b0, 32'h00000001, addresses, '0);
        expect_response(8'd5, 2'd2, 6'd0, 32'd0, 1'b0);
        addresses[0+:32] = 32'd0;
        addresses[32+:32] = 32'd32; // invalid but inactive lane
        submit_request(8'd2, 3'd0, 8'd6, 1'b1, 32'h00000001, addresses, data);
        expect_response(8'd6, 2'd0, 6'h3f, 32'd0, 1'b0);
        submit_request(8'd2, 3'd2, 8'd7, 1'b0, 32'h00000001, addresses, '0);
        expect_response(8'd7, 2'd0, 6'h3f, 32'hfeedface, 1'b1);

        addresses = '0;
        addresses[0+:32] = 32'd0;
        addresses[32+:32] = 32'd12; // word 3 aliases bank zero with three banks
        submit_request(8'd2, 3'd0, 8'd8, 1'b1, 32'h00000003, addresses, data);
        tick();
        if (response_valid)
            $fatal(1, "bank-conflicting lanes completed in one cycle");
        expect_response(8'd8, 2'd0, 6'h3f, 32'd0, 1'b0);

        competing_addresses = '0;
        competing_addresses[0+:32] = 32'd0;
        competing_addresses[32+:32] = 32'd12;
        competing_data = '0;
        submit_request(8'd2, 3'd0, 8'd9, 1'b1, 32'h00000003,
            competing_addresses, competing_data);
        competing_addresses[0+:32] = 32'd0;
        submit_request(8'd2, 3'd1, 8'd10, 1'b1, 32'h00000001,
            competing_addresses, competing_data);
        wait_cycles = 0;
        while (!response_valid && wait_cycles < 16) begin
            tick();
            wait_cycles = wait_cycles + 1;
        end
        if (!response_valid || response_transaction_tag !== 8'd10)
            $fatal(1, "round-robin bank requester did not complete first");
        tick(); // Keep the response stalled while the older request completes.
        if (!response_valid || response_transaction_tag !== 8'd10)
            $fatal(1, "stalled response changed when another request completed");
        expect_response(8'd10, 2'd0, 6'h3f, 32'd0, 1'b0);
        expect_response(8'd9, 2'd0, 6'h3f, 32'd0, 1'b0);

        addresses = '0;
        addresses[0+:32] = 32'd0;
        addresses[32+:32] = 32'd12;
        submit_request(8'd3, 3'd2, 8'd11, 1'b0, 32'h00000003, addresses, '0);
        @(negedge clk);
        cancel_workgroup_id = 8'd3;
        cancel_wave_id = 3'd2;
        cancel_valid = 1'b1;
        #1;
        if (!cancel_ready || !cancel_accepted)
            $fatal(1, "terminal wave could not cancel its memory response");
        @(posedge clk);
        #1;
        cancel_valid = 1'b0;
        @(negedge clk);
        release_workgroup_id = 8'd3;
        release_valid = 1'b1;
        #1;
        if (release_ready)
            $fatal(1, "workgroup released before cancelled service drained");
        release_valid = 1'b0;
        wait_cycles = 0;
        while (outstanding_transaction_bitmap[0] && wait_cycles < 8) begin
            tick();
            wait_cycles = wait_cycles + 1;
        end
        if (response_valid)
            $fatal(1, "cancelled wave received a memory response");
        release_group(8'd3);

        allocate_group(8'd4, 32'd32, 1'b1, 3'd0, 32'd0);
        submit_request(8'd4, 3'd0, 8'd12, 1'b0, 32'h00000001,
            addresses, '0);
        expect_response(8'd12, 2'd0, 6'h3f, 32'd0, 1'b1);

        allocate_group(8'd5, 32'd32, 1'b1, 3'd0, 32'd64);
        allocate_group(8'd6, 32'd32, 1'b1, 3'd0, 32'd96);
        release_group(8'd4);
        release_group(8'd5);
        allocate_group(8'd7, 32'd48, 1'b0, 3'd3, 32'd0);
        allocate_group(8'd7, 32'd129, 1'b0, 3'd1, 32'd0);

        submit_request(8'd99, 3'd0, 8'd13, 1'b0, 32'h00000001,
            addresses, '0);
        expect_response(8'd13, 2'd1, 6'h3f, 32'd0, 1'b0);

        release_group(8'd2);
        release_group(8'd6);
        allocate_group(8'd8, 32'd128, 1'b1, 3'd0, 32'd0);
        addresses = '0;
        data = '0;
        for (lane = 0; lane < 32; lane = lane + 1) begin
            addresses[(lane*32)+:32] = lane * 4;
            data[(lane*32)+:32] = 32'hca000000 | lane;
        end
        submit_request(8'd8, 3'd0, 8'd14, 1'b1, 32'hffffffff, addresses, data);
        expect_response(8'd14, 2'd0, 6'h3f, 32'd0, 1'b0);
        submit_request(8'd8, 3'd1, 8'd15, 1'b0, 32'hffffffff, addresses, '0);
        wait_cycles = 0;
        while (!response_valid && wait_cycles < 32) begin
            tick();
            wait_cycles = wait_cycles + 1;
        end
        if (!response_valid || response_transaction_tag !== 8'd15
            || response_lane_mask !== 32'hffffffff)
            $fatal(1, "wave32 load response was incomplete");
        for (lane = 0; lane < 32; lane = lane + 1) begin
            if (response_lane_data_flat[(lane*32)+:32] !== (32'hca000000 | lane))
                $fatal(1, "wave32 load data mismatch in lane %0d", lane);
        end
        @(negedge clk);
        response_ready = 1'b1;
        @(posedge clk);
        #1;
        response_ready = 1'b0;

        addresses = '0;
        addresses[0+:32] = 32'd0;
        submit_request(8'd8, 3'd2, 8'd16, 1'b0, 32'h00000001, addresses, '0);
        @(negedge clk);
        reset_n = 1'b0;
        #1;
        if (outstanding_transaction_bitmap != '0)
            $fatal(1, "reset retained an outstanding transaction");
        repeat (2) tick();
        reset_n = 1'b1;
        tick();
        allocate_group(8'd9, 32'd128, 1'b1, 3'd0, 32'd0);
        submit_request(8'd9, 3'd0, 8'd17, 1'b0, 32'h00000001, addresses, '0);
        expect_response(8'd17, 2'd0, 6'h3f, 32'd0, 1'b1);
        release_group(8'd9);

        $display("CGX1 CU shared/local memory RTL checks passed.");
        $finish;
    end
endmodule
