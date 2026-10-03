// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_compute_workgroup_lsu_tb;
    localparam integer SLOTS = 2;
    localparam integer WG_WIDTH = 8;
    localparam integer SLOT_WIDTH = 1;
    localparam integer TAG_WIDTH = 64;
    localparam integer MEM_FAULT_NONE = 0;
    localparam integer MEM_FAULT_MISALIGNED = 2;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic [31:0] memory_epoch;
    logic [SLOTS-1:0] wave_live_mask;
    logic [(SLOTS*WG_WIDTH)-1:0] wave_workgroup_id_flat;

    logic [SLOTS-1:0] issue_valid, issue_ready, issue_accepted;
    logic [SLOTS-1:0] issue_global, issue_write;
    logic [(SLOTS*8)-1:0] issue_destination_flat;
    logic [(SLOTS*32)-1:0] issue_lane_mask_flat;
    logic [(SLOTS*1024)-1:0] issue_byte_addresses_flat, issue_store_data_flat;
    logic [SLOTS-1:0] memory_waiting_mask, busy_mask, fault_pending_mask;
    logic [SLOTS-1:0] load_destination_pending_mask;
    logic [(SLOTS*8)-1:0] load_destination_register_flat;

    logic local_request_valid, local_request_ready, local_request_accepted;
    logic [WG_WIDTH-1:0] local_request_workgroup_id;
    logic [SLOT_WIDTH-1:0] local_request_wave_id;
    logic [TAG_WIDTH-1:0] local_request_transaction_tag;
    logic local_request_write;
    logic [31:0] local_request_lane_mask;
    logic [1023:0] local_request_byte_addresses_flat, local_request_store_data_flat;
    logic local_response_valid, local_response_ready;
    logic [WG_WIDTH-1:0] local_response_workgroup_id;
    logic [SLOT_WIDTH-1:0] local_response_wave_id;
    logic [TAG_WIDTH-1:0] local_response_transaction_tag;
    logic local_response_write;
    logic [31:0] local_response_lane_mask;
    logic [1023:0] local_response_lane_data_flat;
    logic [1:0] local_response_fault_code;
    logic [5:0] local_response_fault_lane;
    logic local_cancel_valid, local_cancel_ready, local_cancel_accepted;
    logic [WG_WIDTH-1:0] local_cancel_workgroup_id;
    logic [SLOT_WIDTH-1:0] local_cancel_wave_id;
    logic [(1<<SLOT_WIDTH)-1:0] local_outstanding_wave_bitmap;

    logic global_request_valid, global_request_ready;
    logic [WG_WIDTH-1:0] global_request_workgroup_id;
    logic [SLOT_WIDTH-1:0] global_request_wave_id;
    logic [31:0] global_request_epoch;
    logic [TAG_WIDTH-1:0] global_request_transaction_tag;
    logic global_request_write;
    logic [31:0] global_request_lane_mask;
    logic [1023:0] global_request_byte_addresses_flat, global_request_store_data_flat;
    logic global_response_valid, global_response_ready;
    logic [WG_WIDTH-1:0] global_response_workgroup_id;
    logic [SLOT_WIDTH-1:0] global_response_wave_id;
    logic [31:0] global_response_epoch;
    logic [TAG_WIDTH-1:0] global_response_transaction_tag;
    logic global_response_write;
    logic [31:0] global_response_lane_mask;
    logic [1023:0] global_response_lane_data_flat;
    logic [2:0] global_response_fault_code;
    logic [5:0] global_response_fault_lane;

    logic writeback_valid, writeback_ready, writeback_address_fault;
    logic [WG_WIDTH-1:0] writeback_workgroup_id;
    logic [SLOT_WIDTH-1:0] writeback_wave_slot;
    logic [TAG_WIDTH-1:0] writeback_transaction_tag;
    logic [7:0] writeback_destination;
    logic [31:0] writeback_lane_mask;
    logic [1023:0] writeback_lane_data_flat;
    logic completion_valid, completion_ready, completion_write;
    logic [WG_WIDTH-1:0] completion_workgroup_id;
    logic [SLOT_WIDTH-1:0] completion_wave_slot;
    logic [TAG_WIDTH-1:0] completion_transaction_tag;
    logic fault_valid, fault_ready;
    logic [WG_WIDTH-1:0] fault_workgroup_id;
    logic [SLOT_WIDTH-1:0] fault_wave_slot;
    logic [TAG_WIDTH-1:0] fault_transaction_tag;
    logic [2:0] fault_code;
    logic [5:0] fault_lane;

    logic allocation_valid, allocation_ready, allocation_result_valid, allocation_accepted;
    logic [WG_WIDTH-1:0] allocation_workgroup_id;
    logic [31:0] allocation_byte_count, allocation_base_byte_address;
    logic [2:0] allocation_failure;
    logic release_valid, release_ready, release_accepted;
    logic [WG_WIDTH-1:0] release_workgroup_id;
    logic [31:0] allocated_bytes_used;
    logic [(1<<2)-1:0] outstanding_transaction_bitmap;
    integer timeout;
    integer random_iteration, random_slot, random_delay;
    reg [15:0] random_state;
    reg random_write;
    reg [2:0] random_fault;
    reg [63:0] random_tag;
    logic [TAG_WIDTH-1:0] tag0, tag1;
    integer lane;

    always #5 clk = ~clk;

    cgx1_compute_workgroup_lsu #(
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .WORKGROUP_ID_WIDTH(WG_WIDTH),
        .WAVE_SLOT_WIDTH(SLOT_WIDTH),
        .TRANSACTION_TAG_WIDTH(TAG_WIDTH)
    ) dut (.*);

    cgx1_cu_shared_local_memory #(
        .CU_SHARED_BYTES(256), .BANK_COUNT(1), .MAX_WORKGROUP_CONTEXTS(4),
        .MAX_OUTSTANDING_TRANSACTIONS(4), .WORKGROUP_ID_WIDTH(WG_WIDTH),
        .WAVE_ID_WIDTH(SLOT_WIDTH), .TRANSACTION_TAG_WIDTH(TAG_WIDTH)
    ) local_memory (
        .clk(clk), .reset_n(reset_n),
        .allocation_valid(allocation_valid), .allocation_ready(allocation_ready),
        .allocation_workgroup_id(allocation_workgroup_id),
        .allocation_byte_count(allocation_byte_count),
        .allocation_result_valid(allocation_result_valid),
        .allocation_accepted(allocation_accepted), .allocation_failure(allocation_failure),
        .allocation_base_byte_address(allocation_base_byte_address),
        .release_valid(release_valid), .release_workgroup_id(release_workgroup_id),
        .release_ready(release_ready), .release_accepted(release_accepted),
        .request_valid(local_request_valid), .request_ready(local_request_ready),
        .request_workgroup_id(local_request_workgroup_id),
        .request_wave_id(local_request_wave_id),
        .request_transaction_tag(local_request_transaction_tag),
        .request_write(local_request_write), .request_lane_mask(local_request_lane_mask),
        .request_byte_addresses_flat(local_request_byte_addresses_flat),
        .request_store_data_flat(local_request_store_data_flat),
        .request_accepted(local_request_accepted),
        .response_valid(local_response_valid), .response_ready(local_response_ready),
        .response_workgroup_id(local_response_workgroup_id),
        .response_wave_id(local_response_wave_id),
        .response_transaction_tag(local_response_transaction_tag),
        .response_write(local_response_write), .response_lane_mask(local_response_lane_mask),
        .response_lane_data_flat(local_response_lane_data_flat),
        .response_fault_code(local_response_fault_code),
        .response_fault_lane(local_response_fault_lane),
        .cancel_valid(local_cancel_valid), .cancel_workgroup_id(local_cancel_workgroup_id),
        .cancel_wave_id(local_cancel_wave_id), .cancel_ready(local_cancel_ready),
        .cancel_accepted(local_cancel_accepted), .allocated_bytes_used(allocated_bytes_used),
        .outstanding_transaction_bitmap(outstanding_transaction_bitmap),
        .outstanding_wave_bitmap(local_outstanding_wave_bitmap)
    );

    task automatic reset_inputs;
    begin
        memory_epoch = 32'd1;
        wave_live_mask = '0;
        wave_workgroup_id_flat = '0;
        issue_valid = '0; issue_global = '0; issue_write = '0;
        issue_destination_flat = '0; issue_lane_mask_flat = '0;
        issue_byte_addresses_flat = '0; issue_store_data_flat = '0;
        global_request_ready = 1'b0;
        global_response_valid = 1'b0;
        global_response_workgroup_id = '0; global_response_wave_id = '0;
        global_response_epoch = '0; global_response_transaction_tag = '0;
        global_response_write = 1'b0; global_response_lane_mask = '0;
        global_response_lane_data_flat = '0; global_response_fault_code = '0;
        global_response_fault_lane = '0;
        writeback_ready = 1'b1; writeback_address_fault = 1'b0;
        completion_ready = 1'b1; fault_ready = 1'b1;
        allocation_valid = 1'b0; allocation_workgroup_id = '0; allocation_byte_count = '0;
        release_valid = 1'b0; release_workgroup_id = '0;
    end
    endtask

    task automatic allocate_group(input logic [WG_WIDTH-1:0] id);
    begin
        @(negedge clk); allocation_workgroup_id = id; allocation_byte_count = 128;
        allocation_valid = 1'b1; #1;
        if (!allocation_ready) $fatal(1, "local region allocator was not ready");
        @(posedge clk); #1; @(negedge clk); allocation_valid = 1'b0;
        timeout = 0;
        while (!allocation_result_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 200) $fatal(1, "local region allocation did not complete");
        end
        if (!allocation_accepted || allocation_failure != 0)
            $fatal(1, "local region allocation failed");
    end
    endtask

    task automatic issue_one(input integer slot, input logic global_space, input logic write_access,
                             input logic [7:0] destination, input logic [31:0] mask,
                             input logic [31:0] address0, input logic [31:0] value0);
    begin
        @(negedge clk);
        issue_global[slot] = global_space; issue_write[slot] = write_access;
        issue_destination_flat[(slot*8)+:8] = destination;
        issue_lane_mask_flat[(slot*32)+:32] = mask;
        issue_byte_addresses_flat[(slot*1024)+:1024] = '0;
        issue_store_data_flat[(slot*1024)+:1024] = '0;
        issue_byte_addresses_flat[(slot*1024)+:32] = address0;
        issue_store_data_flat[(slot*1024)+:32] = value0;
        issue_valid[slot] = 1'b1; #1;
        if (!issue_ready[slot] || !issue_accepted[slot])
            $fatal(1, "LSU did not accept a runnable decoded request for slot %0d", slot);
        @(posedge clk); #1; @(negedge clk); issue_valid[slot] = 1'b0;
    end
    endtask

    task automatic wait_completion(input integer slot);
    begin
        timeout = 0;
        while (!completion_valid || completion_wave_slot != slot) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 128) $fatal(1, "memory completion timed out for slot %0d", slot);
        end
        @(posedge clk); #1; @(negedge clk);
    end
    endtask

    task automatic send_global_response(input integer slot, input logic [31:0] epoch,
                                        input logic [TAG_WIDTH-1:0] tag,
                                        input logic write_access, input logic [31:0] value0,
                                        input logic [2:0] fault);
    begin
        @(negedge clk);
        global_response_workgroup_id = wave_workgroup_id_flat[(slot*WG_WIDTH)+:WG_WIDTH];
        global_response_wave_id = slot[SLOT_WIDTH-1:0];
        global_response_epoch = epoch; global_response_transaction_tag = tag;
        global_response_write = write_access; global_response_lane_mask = 32'd1;
        global_response_lane_data_flat = '0;
        global_response_lane_data_flat[0+:32] = value0;
        global_response_fault_code = fault; global_response_valid = 1'b1;
        #1;
    end
    endtask

    initial begin
        reset_inputs();
        repeat (3) @(posedge clk);
        @(negedge clk); reset_n = 1'b1;
        wave_live_mask = 2'b11;
        wave_workgroup_id_flat[0+:WG_WIDTH] = 8'd1;
        wave_workgroup_id_flat[WG_WIDTH+:WG_WIDTH] = 8'd1;
        allocate_group(8'd1);

        // Local store/load use the real allocated region and captured issue payload.
        issue_one(0, 1'b0, 1'b1, 8'd0, 32'd1, 32'd0, 32'hc0decafe);
        issue_byte_addresses_flat[0+:32] = 32'd128;
        issue_store_data_flat[0+:32] = 32'hdeadbeef;
        timeout = 0;
        while (!completion_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 64) $fatal(1, "local store failed to complete");
        end
        if (!completion_write || completion_workgroup_id != 8'd1)
            $fatal(1, "local store completion lost operation identity");
        @(posedge clk); #1;
        issue_one(0, 1'b0, 1'b0, 8'd3, 32'd1, 32'd0, 32'd0);
        timeout = 0;
        while (!writeback_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 64) $fatal(1, "local load failed to reach VGPR writeback");
        end
        if (writeback_wave_slot != 0 || writeback_destination != 3
            || writeback_lane_data_flat[0+:32] != 32'hc0decafe)
            $fatal(1, "local load writeback data or destination was wrong");
        @(posedge clk); #1; wait_completion(0);

        // Local alignment faults are terminal completions and never write a VGPR.
        fault_ready = 1'b0;
        issue_one(0, 1'b0, 1'b0, 8'd4, 32'd1, 32'd1, 32'd0);
        timeout = 0;
        while (!fault_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 64) $fatal(1, "local alignment fault did not complete");
        end
        if (fault_code != MEM_FAULT_MISALIGNED || fault_lane != 0 || writeback_valid
            || !fault_pending_mask[0])
            $fatal(1, "local alignment fault was not reported atomically");
        repeat (2) begin
            @(posedge clk); #1;
            if (!fault_valid || !fault_pending_mask[0])
                $fatal(1, "backpressured fault lost terminal wave ownership");
        end
        @(negedge clk); fault_ready = 1'b1;
        @(posedge clk); #1;

        // Out-of-range local addresses fault, and a kill before downstream
        // service starts never allocates a shared-memory transaction.
        issue_one(0, 1'b0, 1'b0, 8'd4, 32'd1, 32'd128, 32'd0);
        timeout = 0;
        while (!fault_valid) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 64) $fatal(1, "local bounds fault did not complete");
        end
        if (fault_code != 3'd3 || fault_lane != 0 || writeback_valid)
            $fatal(1, "local bounds fault was not reported without writeback");
        @(posedge clk); #1;
        issue_one(1, 1'b0, 1'b0, 8'd4, 32'd1, 32'd0, 32'd0);
        if (!local_request_valid || local_outstanding_wave_bitmap[1])
            $fatal(1, "kill-before-service setup already entered shared memory");
        wave_live_mask[1] = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        if (memory_waiting_mask[1] || local_outstanding_wave_bitmap[1]
            || local_cancel_valid)
            $fatal(1, "kill before service leaked a local request or wait state");
        @(negedge clk); wave_live_mask[1] = 1'b1;

        // Two waves can own independent global requests; a stalled ready/valid payload is stable.
        issue_one(0, 1'b1, 1'b0, 8'd5, 32'd1, 32'h1000, 32'd0);
        issue_one(1, 1'b1, 1'b1, 8'd0, 32'd1, 32'h2000, 32'h12345678);
        if (memory_waiting_mask != 2'b11)
            $fatal(1, "independent memory requests did not block both issuing waves");
        if (!global_request_valid || global_request_wave_id != 0
            || global_request_byte_addresses_flat[0+:32] != 32'h1000)
            $fatal(1, "first global request was not held under backpressure");
        tag0 = global_request_transaction_tag;
        repeat (2) begin
            @(posedge clk); #1;
            if (!global_request_valid || global_request_transaction_tag != tag0
                || global_request_byte_addresses_flat[0+:32] != 32'h1000)
                $fatal(1, "global ready/valid payload changed before acceptance");
        end
        @(negedge clk); global_request_ready = 1'b1; #1;
        if (!global_request_valid || global_request_transaction_tag != tag0)
            $fatal(1, "global request identity changed on ready");
        @(posedge clk); #1;
        if (!global_request_valid || global_request_wave_id != 1)
            $fatal(1, "second independent global request did not make progress");
        tag1 = global_request_transaction_tag;
        @(posedge clk); #1; @(negedge clk); global_request_ready = 1'b0;

        // Store acknowledgement proceeds independently of VGPR writeback.
        send_global_response(1, 32'd1, tag1, 1'b1, 32'd0, MEM_FAULT_NONE);
        #1;
        if (!global_response_ready)
            $fatal(1, "store acknowledgement did not accept independently of VGPR writeback");
        @(posedge clk); #1; @(negedge clk); global_response_valid = 1'b0;
        wait_completion(1);

        // A load response remains stable at the ready/valid boundary while VGPR is busy.
        writeback_ready = 1'b0;
        send_global_response(0, 32'd1, tag0, 1'b0, 32'hface1234, MEM_FAULT_NONE);
        #1;
        if (global_response_ready || !writeback_valid)
            $fatal(1, "load response was consumed before VGPR writeback could accept it");
        repeat (2) begin
            @(posedge clk); #1;
            if (!global_response_valid || global_response_ready || !writeback_valid)
                $fatal(1, "stalled global response was not held stable");
        end
        @(negedge clk); writeback_ready = 1'b1; #1;
        if (!global_response_ready || !writeback_valid
            || writeback_lane_data_flat[0+:32] != 32'hface1234
            || writeback_destination != 5)
            $fatal(1, "global response did not drive captured load destination/data");
        @(posedge clk); #1; @(negedge clk); global_response_valid = 1'b0;
        wait_completion(0);

        // A response for a retired tag is dropped after the physical slot is reused.
        issue_one(0, 1'b1, 1'b0, 8'd6, 32'd1, 32'h3000, 32'd0);
        tag0 = global_request_transaction_tag;
        @(negedge clk); global_request_ready = 1'b1;
        @(posedge clk); #1; @(negedge clk); global_request_ready = 1'b0;
        send_global_response(0, 32'd1, tag1, 1'b0, 32'hbad0bad0, MEM_FAULT_NONE);
        #1;
        if (!global_response_ready || writeback_valid)
            $fatal(1, "stale response was not discarded without writeback");
        @(posedge clk); #1; @(negedge clk); global_response_valid = 1'b0;
        if (!memory_waiting_mask[0])
            $fatal(1, "stale response cleared a reused wave's current memory wait");
        send_global_response(0, 32'd1, tag0, 1'b0, 32'h600dcafe, MEM_FAULT_NONE);
        @(posedge clk); #1; @(negedge clk); global_response_valid = 1'b0;
        wait_completion(0);

        // Reset invalidates old ownership; the new epoch prevents a late response from matching.
        issue_one(1, 1'b1, 1'b0, 8'd7, 32'd1, 32'h4000, 32'd0);
        tag0 = global_request_transaction_tag;
        @(negedge clk); global_request_ready = 1'b1;
        @(posedge clk); #1; @(negedge clk); global_request_ready = 1'b0;
        reset_n = 1'b0; repeat (2) @(posedge clk); #1;
        memory_epoch = 32'd2; wave_live_mask = 2'b11;
        wave_workgroup_id_flat[0+:WG_WIDTH] = 8'd1;
        wave_workgroup_id_flat[WG_WIDTH+:WG_WIDTH] = 8'd1;
        @(negedge clk); reset_n = 1'b1;
        allocate_group(8'd1);
        issue_one(1, 1'b1, 1'b0, 8'd8, 32'd1, 32'h5000, 32'd0);
        tag1 = global_request_transaction_tag;
        @(negedge clk); global_request_ready = 1'b1;
        @(posedge clk); #1; @(negedge clk); global_request_ready = 1'b0;
        send_global_response(1, 32'd1, tag0, 1'b0, 32'h11111111, MEM_FAULT_NONE);
        #1;
        if (!global_response_ready || writeback_valid)
            $fatal(1, "pre-reset global response crossed the reset epoch");
        @(posedge clk); #1; @(negedge clk); global_response_valid = 1'b0;
        if (!memory_waiting_mask[1])
            $fatal(1, "pre-reset response cleared the new transaction wait");
        send_global_response(1, 32'd2, tag1, 1'b0, 32'h22222222, MEM_FAULT_NONE);
        @(posedge clk); #1; @(negedge clk); global_response_valid = 1'b0;
        wait_completion(1);

        // A terminal downstream fault and an invalid VGPR destination both
        // complete through the fault channel without publishing load data.
        issue_one(0, 1'b1, 1'b0, 8'd9, 32'd1, 32'h5500, 32'd0);
        random_tag = global_request_transaction_tag;
        @(negedge clk); global_request_ready = 1'b1;
        @(posedge clk); #1; @(negedge clk); global_request_ready = 1'b0;
        send_global_response(0, 32'd2, random_tag, 1'b0, 32'hdeadbeef, 3'd5);
        @(posedge clk); #1; @(negedge clk); global_response_valid = 1'b0;
        if (!fault_valid || fault_code != 3'd5 || writeback_valid)
            $fatal(1, "global terminal fault did not suppress load writeback");
        @(posedge clk); #1; @(negedge clk);
        issue_one(1, 1'b1, 1'b0, 8'd255, 32'd1, 32'h5600, 32'd0);
        random_tag = global_request_transaction_tag;
        @(negedge clk); global_request_ready = 1'b1;
        @(posedge clk); #1; @(negedge clk); global_request_ready = 1'b0;
        writeback_address_fault = 1'b1;
        send_global_response(1, 32'd2, random_tag, 1'b0, 32'hbad0cafe, MEM_FAULT_NONE);
        @(posedge clk); #1; @(negedge clk); global_response_valid = 1'b0;
        writeback_address_fault = 1'b0;
        if (!fault_valid || fault_code != 3'd4 || writeback_valid)
            $fatal(1, "invalid load destination was not converted to an LSU fault");
        @(posedge clk); #1; @(negedge clk);

        // Seeded randomized request, delayed/stale response, fault and slot
        // reuse traffic provides repeatable lifecycle stress.
        random_state = 16'h1ace;
        for (random_iteration = 0; random_iteration < 32; random_iteration = random_iteration + 1) begin
            random_state = {random_state[14:0],
                random_state[15] ^ random_state[13] ^ random_state[12] ^ random_state[10]};
            random_slot = random_state[0] ? 1 : 0;
            random_write = random_state[1];
            random_fault = (random_state[5:2] == 0) ? 3'd5 : MEM_FAULT_NONE;
            issue_one(random_slot, 1'b1, random_write,
                {4'b0, random_state[9:6]}, 32'd1,
                32'h6000 + (random_iteration * 4), 32'h70000000 + random_iteration);
            random_tag = global_request_transaction_tag;
            @(negedge clk); global_request_ready = 1'b1;
            @(posedge clk); #1; @(negedge clk); global_request_ready = 1'b0;
            if (random_state[14]) begin
                send_global_response(random_slot, memory_epoch, random_tag ^ 64'h55,
                    random_write, 32'hbad00000 + random_iteration, MEM_FAULT_NONE);
                #1;
                if (!global_response_ready || writeback_valid)
                    $fatal(1, "random stale response was not dropped");
                @(posedge clk); #1; @(negedge clk); global_response_valid = 1'b0;
                if (!memory_waiting_mask[random_slot])
                    $fatal(1, "random stale response cleared current request ownership");
            end
            random_delay = random_state[13:12];
            repeat (random_delay) @(posedge clk);
            if (!random_write && (random_fault == MEM_FAULT_NONE)
                && random_state[11]) writeback_ready = 1'b0;
            send_global_response(random_slot, memory_epoch, random_tag, random_write,
                32'h71000000 + random_iteration, random_fault);
            if (!random_write && (random_fault == MEM_FAULT_NONE) && !writeback_ready) begin
                repeat (2) begin
                    @(posedge clk); #1;
                    if (global_response_ready || !writeback_valid)
                        $fatal(1, "random delayed load response escaped backpressure");
                end
                @(negedge clk); writeback_ready = 1'b1;
            end
            @(posedge clk); #1; @(negedge clk); global_response_valid = 1'b0;
            if (random_fault != MEM_FAULT_NONE) begin
                timeout = 0;
                while (!fault_valid) begin
                    @(posedge clk); #1; timeout = timeout + 1;
                    if (timeout > 16) $fatal(1, "random memory fault was lost");
                end
                if (fault_code != random_fault)
                    $fatal(1, "random memory fault cause changed");
                @(posedge clk); #1; @(negedge clk);
            end else begin
                wait_completion(random_slot);
            end
        end

        // Killed local operations remain busy until the shared-memory service drains.
        issue_one(0, 1'b0, 1'b0, 8'd9, 32'h0000000f, 32'd0, 32'd0);
        timeout = 0;
        while (local_outstanding_wave_bitmap[0] !== 1'b1) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 16) $fatal(1, "local request did not enter the allocated memory region");
        end
        @(negedge clk); wave_live_mask[0] = 1'b0;
        timeout = 0;
        while (memory_waiting_mask[0]) begin
            @(posedge clk); #1; timeout = timeout + 1;
            if (timeout > 64) $fatal(1, "killed local request did not drain");
        end
        if (writeback_valid || fault_valid)
            $fatal(1, "killed local request produced an architectural completion");

        $display("[pass] CGX1 workgroup LSU checks passed.");
        $finish;
    end
endmodule
