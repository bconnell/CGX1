// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Parameterized CU-local wave32 dword memory model. Bank count/service details
// are implementation parameters and are not frozen ISA architecture.
module cgx1_cu_shared_local_memory #(
    parameter integer CU_SHARED_BYTES = 4096,
    parameter integer BANK_COUNT = 32,
    parameter integer MAX_WORKGROUP_CONTEXTS = 8,
    parameter integer MAX_OUTSTANDING_TRANSACTIONS = 32,
    parameter integer WORKGROUP_ID_WIDTH = 16,
    parameter integer WAVE_ID_WIDTH = 4,
    parameter integer TRANSACTION_TAG_WIDTH = 32
) (
    input logic clk,
    input logic reset_n,

    input logic allocation_valid,
    output logic allocation_ready,
    input logic [WORKGROUP_ID_WIDTH-1:0] allocation_workgroup_id,
    input logic [31:0] allocation_byte_count,
    output logic allocation_result_valid,
    output logic allocation_accepted,
    output logic [2:0] allocation_failure,
    output logic [31:0] allocation_base_byte_address,

    input logic release_valid,
    input logic [WORKGROUP_ID_WIDTH-1:0] release_workgroup_id,
    output logic release_ready,
    output logic release_accepted,

    input logic request_valid,
    output logic request_ready,
    input logic [WORKGROUP_ID_WIDTH-1:0] request_workgroup_id,
    input logic [WAVE_ID_WIDTH-1:0] request_wave_id,
    input logic [TRANSACTION_TAG_WIDTH-1:0] request_transaction_tag,
    input logic request_write,
    input logic [31:0] request_lane_mask,
    input logic [1023:0] request_byte_addresses_flat,
    input logic [1023:0] request_store_data_flat,
    output logic request_accepted,

    output logic response_valid,
    input logic response_ready,
    output logic [WORKGROUP_ID_WIDTH-1:0] response_workgroup_id,
    output logic [WAVE_ID_WIDTH-1:0] response_wave_id,
    output logic [TRANSACTION_TAG_WIDTH-1:0] response_transaction_tag,
    output logic response_write,
    output logic [31:0] response_lane_mask,
    output logic [1023:0] response_lane_data_flat,
    output logic [1:0] response_fault_code,
    output logic [5:0] response_fault_lane,

    input logic cancel_valid,
    input logic [WORKGROUP_ID_WIDTH-1:0] cancel_workgroup_id,
    input logic [WAVE_ID_WIDTH-1:0] cancel_wave_id,
    output logic cancel_ready,
    output logic cancel_accepted,

    output logic [31:0] allocated_bytes_used,
    output logic [MAX_OUTSTANDING_TRANSACTIONS-1:0] outstanding_transaction_bitmap,
    output logic [(1 << WAVE_ID_WIDTH)-1:0] outstanding_wave_bitmap
);
    localparam integer CU_WORD_COUNT = (CU_SHARED_BYTES + 3) / 4;
    localparam integer GROUP_INDEX_WIDTH =
        (MAX_WORKGROUP_CONTEXTS <= 1) ? 1 : $clog2(MAX_WORKGROUP_CONTEXTS);
    localparam integer TRANSACTION_INDEX_WIDTH =
        (MAX_OUTSTANDING_TRANSACTIONS <= 1)
            ? 1 : $clog2(MAX_OUTSTANDING_TRANSACTIONS);
    localparam logic [1:0] TXN_FREE = 2'd0;
    localparam logic [1:0] TXN_SERVICE = 2'd1;
    localparam logic [1:0] TXN_RESPONSE = 2'd2;
    localparam logic [2:0] ALLOC_FAIL_NONE = 3'd0;
    localparam logic [2:0] ALLOC_FAIL_EXCEEDS_CU = 3'd1;
    localparam logic [2:0] ALLOC_FAIL_CAPACITY_BUSY = 3'd2;
    localparam logic [2:0] ALLOC_FAIL_FRAGMENTED = 3'd3;
    localparam logic [2:0] ALLOC_FAIL_CONTEXTS_FULL = 3'd4;
    localparam logic [2:0] ALLOC_FAIL_DUPLICATE_ID = 3'd5;
    localparam logic [1:0] MEM_FAULT_NONE = 2'd0;
    localparam logic [1:0] MEM_FAULT_UNKNOWN_WORKGROUP = 2'd1;
    localparam logic [1:0] MEM_FAULT_MISALIGNED = 2'd2;
    localparam logic [1:0] MEM_FAULT_OUT_OF_BOUNDS = 2'd3;

    logic [MAX_WORKGROUP_CONTEXTS-1:0] group_active_q;
    logic [WORKGROUP_ID_WIDTH-1:0] group_id_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [31:0] group_base_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [31:0] group_bytes_q [0:MAX_WORKGROUP_CONTEXTS-1];
    logic [31:0] used_bytes_q;
    logic [31:0] used_bytes_next;

    logic [1:0] txn_state_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic [GROUP_INDEX_WIDTH-1:0] txn_group_index_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic [WORKGROUP_ID_WIDTH-1:0] txn_workgroup_id_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic [WAVE_ID_WIDTH-1:0] txn_wave_id_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic [TRANSACTION_TAG_WIDTH-1:0] txn_tag_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic txn_write_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic [31:0] txn_lane_mask_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic [31:0] txn_remaining_mask_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic [31:0] txn_remaining_mask_next [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic [1023:0] txn_addresses_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic [1023:0] txn_store_data_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic [1023:0] txn_lane_data_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic [1023:0] txn_lane_data_next [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic [1:0] txn_fault_code_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic [5:0] txn_fault_lane_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic txn_cancelled_q [0:MAX_OUTSTANDING_TRANSACTIONS-1];
    logic response_hold_valid_q;
    logic [TRANSACTION_INDEX_WIDTH-1:0] response_hold_index_q;

    logic [31:0] memory_data_q [0:CU_WORD_COUNT-1];
    logic [CU_WORD_COUNT-1:0] memory_valid_q;
    logic [BANK_COUNT-1:0] bank_grant_valid;
    integer bank_grant_txn [0:BANK_COUNT-1];
    integer bank_grant_lane [0:BANK_COUNT-1];
    integer bank_rr_q [0:BANK_COUNT-1];

    logic allocation_scrub_active_q;
    logic [WORKGROUP_ID_WIDTH-1:0] allocation_pending_id_q;
    logic [31:0] allocation_pending_base_q;
    logic [31:0] allocation_pending_bytes_q;
    logic [GROUP_INDEX_WIDTH-1:0] allocation_pending_group_q;
    logic [31:0] allocation_scrub_word_q;
    logic [31:0] allocation_scrub_end_word_q;

    integer allocation_duplicate_group;
    integer allocation_free_group;
    integer allocation_plan_group;
    integer allocation_plan_base;
    logic [2:0] allocation_plan_failure;
    integer request_group_index;
    integer request_free_transaction;
    integer request_response_index;
    integer response_selected_index;
    integer cancel_transaction_index;
    logic request_wave_busy;
    logic request_tag_busy;
    logic [1:0] request_fault_code;
    logic [5:0] request_fault_lane;
    logic [31:0] request_remaining_lanes;
    integer release_group_index;
    logic release_has_transaction;
    integer state_index;
    integer lane_index;
    integer bank_index;
    integer service_index;
    integer service_lane;
    integer service_word;
    integer ff_transaction_index;
    integer ff_lane_index;
    integer ff_word_address;

    assign allocation_ready = !allocation_scrub_active_q;
    assign allocated_bytes_used = used_bytes_q;

    always_comb begin : allocation_decode
        integer context_index;
        integer scan_pass;
        integer cursor_byte;
        integer aligned_cursor;
        integer nearest_group;
        integer nearest_base;
        logic range_found;

        allocation_duplicate_group = -1;
        allocation_free_group = -1;
        allocation_plan_group = -1;
        allocation_plan_base = 0;
        allocation_plan_failure = ALLOC_FAIL_NONE;
        cursor_byte = 0;
        aligned_cursor = 0;
        nearest_group = -1;
        nearest_base = CU_SHARED_BYTES + 1;
        range_found = 1'b0;

        for (context_index = 0; context_index < MAX_WORKGROUP_CONTEXTS; context_index = context_index + 1) begin
            if (group_active_q[context_index]) begin
                if (group_id_q[context_index] == allocation_workgroup_id)
                    allocation_duplicate_group = context_index;
            end else if (allocation_free_group == -1) begin
                allocation_free_group = context_index;
            end
        end

        allocation_plan_group = allocation_free_group;
        if ($unsigned(allocation_byte_count) > CU_SHARED_BYTES)
            allocation_plan_failure = ALLOC_FAIL_EXCEEDS_CU;
        else if (allocation_duplicate_group != -1)
            allocation_plan_failure = ALLOC_FAIL_DUPLICATE_ID;
        else if (allocation_free_group == -1)
            allocation_plan_failure = ALLOC_FAIL_CONTEXTS_FULL;
        else if (({32'b0, used_bytes_q} + {32'b0, allocation_byte_count}) > 64'(CU_SHARED_BYTES))
            allocation_plan_failure = ALLOC_FAIL_CAPACITY_BUSY;
        else if (allocation_byte_count == 0) begin
            allocation_plan_base = 0;
            range_found = 1'b1;
        end else begin
            cursor_byte = 0;
            for (scan_pass = 0; scan_pass <= MAX_WORKGROUP_CONTEXTS; scan_pass = scan_pass + 1) begin
                if (!range_found && (cursor_byte <= CU_SHARED_BYTES)) begin
                    aligned_cursor = (cursor_byte + 3) & ~3;
                    nearest_group = -1;
                    nearest_base = CU_SHARED_BYTES + 1;
                    for (context_index = 0; context_index < MAX_WORKGROUP_CONTEXTS; context_index = context_index + 1) begin
                        if (group_active_q[context_index]
                            && (group_bytes_q[context_index] != 0)
                            && ($unsigned(group_base_q[context_index]) >= aligned_cursor)
                            && ($unsigned(group_base_q[context_index]) < nearest_base)) begin
                            nearest_group = context_index;
                            nearest_base = $unsigned(group_base_q[context_index]);
                        end
                    end
                    if ((nearest_group == -1)
                        && (({32'b0, aligned_cursor} + {32'b0, allocation_byte_count}) <= 64'(CU_SHARED_BYTES))) begin
                        allocation_plan_base = aligned_cursor;
                        range_found = 1'b1;
                    end else if ((nearest_group != -1)
                        && (({32'b0, aligned_cursor} + {32'b0, allocation_byte_count}) <= 64'($unsigned(nearest_base)))) begin
                        allocation_plan_base = aligned_cursor;
                        range_found = 1'b1;
                    end else if (nearest_group != -1) begin
                        cursor_byte = $unsigned(group_base_q[nearest_group])
                            + $unsigned(group_bytes_q[nearest_group]);
                    end else begin
                        cursor_byte = CU_SHARED_BYTES + 1;
                    end
                end
            end
            if (!range_found)
                allocation_plan_failure = ALLOC_FAIL_FRAGMENTED;
        end
    end

    always_comb begin : request_decode
        integer context_index;
        integer transaction_index;
        integer lane;
        logic [63:0] lane_address;
        lane_address = '0;
        request_group_index = -1;
        request_free_transaction = -1;
        request_wave_busy = 1'b0;
        request_tag_busy = 1'b0;
        request_fault_code = MEM_FAULT_NONE;
        request_fault_lane = 6'h3f;
        request_remaining_lanes = request_lane_mask;
        release_group_index = -1;
        release_has_transaction = 1'b0;
        cancel_transaction_index = -1;
        request_response_index = -1;

        for (context_index = 0; context_index < MAX_WORKGROUP_CONTEXTS; context_index = context_index + 1) begin
            if (group_active_q[context_index]
                && group_id_q[context_index] == request_workgroup_id)
                request_group_index = context_index;
            if (group_active_q[context_index]
                && group_id_q[context_index] == release_workgroup_id)
                release_group_index = context_index;
        end

        for (transaction_index = 0; transaction_index < MAX_OUTSTANDING_TRANSACTIONS; transaction_index = transaction_index + 1) begin
            if (txn_state_q[transaction_index] == TXN_FREE
                && request_free_transaction == -1)
                request_free_transaction = transaction_index;
            if (txn_state_q[transaction_index] != TXN_FREE) begin
                if (txn_workgroup_id_q[transaction_index] == request_workgroup_id
                    && txn_wave_id_q[transaction_index] == request_wave_id)
                    request_wave_busy = 1'b1;
                if (txn_tag_q[transaction_index] == request_transaction_tag)
                    request_tag_busy = 1'b1;
                if (txn_workgroup_id_q[transaction_index] == release_workgroup_id)
                    release_has_transaction = 1'b1;
                if (txn_workgroup_id_q[transaction_index] == cancel_workgroup_id
                    && txn_wave_id_q[transaction_index] == cancel_wave_id
                    && cancel_transaction_index == -1)
                    cancel_transaction_index = transaction_index;
                if ((txn_state_q[transaction_index] == TXN_RESPONSE)
                    && !txn_cancelled_q[transaction_index]
                    && request_response_index == -1)
                    request_response_index = transaction_index;
            end
        end

        if (request_group_index == -1) begin
            request_fault_code = MEM_FAULT_UNKNOWN_WORKGROUP;
            request_fault_lane = 6'h3f;
        end else begin
            for (lane = 0; lane < 32; lane = lane + 1) begin
                if (request_fault_code == MEM_FAULT_NONE
                    && request_lane_mask[lane]) begin
                    lane_address = {32'b0, request_byte_addresses_flat[(lane*32)+:32]};
                    if ((lane_address[1:0]) != 2'b00) begin
                        request_fault_code = MEM_FAULT_MISALIGNED;
                        request_fault_lane = lane[5:0];
                    end else if ((lane_address + 64'd4)
                        > {32'b0, group_bytes_q[request_group_index]}) begin
                        request_fault_code = MEM_FAULT_OUT_OF_BOUNDS;
                        request_fault_lane = lane[5:0];
                    end
                end
            end
        end

        request_ready = (request_free_transaction != -1)
            && !request_wave_busy && !request_tag_busy;
        request_accepted = request_valid && request_ready;
        release_ready = (release_group_index != -1) && !release_has_transaction;
        release_accepted = release_valid && release_ready;
        cancel_ready = cancel_transaction_index != -1;
        cancel_accepted = cancel_valid && cancel_ready;
    end

    always_comb begin : bank_arbitration
        integer bank;
        integer offset;
        integer candidate;
        integer lane;
        integer word_address;
        logic found;
        logic [31:0] remaining_next;
        logic [1023:0] lane_data_next;
        logic [63:0] physical_address;

        word_address = 0;
        physical_address = '0;
        service_index = 0;
        service_lane = 0;
        service_word = 0;
        bank_grant_valid = '0;
        for (bank = 0; bank < BANK_COUNT; bank = bank + 1) begin
            bank_grant_txn[bank] = -1;
            bank_grant_lane[bank] = -1;
        end
        for (state_index = 0; state_index < MAX_OUTSTANDING_TRANSACTIONS; state_index = state_index + 1) begin
            txn_remaining_mask_next[state_index] = txn_remaining_mask_q[state_index];
            txn_lane_data_next[state_index] = txn_lane_data_q[state_index];
        end

        for (bank = 0; bank < BANK_COUNT; bank = bank + 1) begin
            found = 1'b0;
            for (offset = 0; offset < MAX_OUTSTANDING_TRANSACTIONS; offset = offset + 1) begin
                candidate = bank_rr_q[bank] + offset;
                if (candidate >= MAX_OUTSTANDING_TRANSACTIONS)
                    candidate = candidate - MAX_OUTSTANDING_TRANSACTIONS;
                if (!found && txn_state_q[candidate] == TXN_SERVICE) begin
                    for (lane = 0; lane < 32; lane = lane + 1) begin
                        if (!found && txn_remaining_mask_q[candidate][lane]) begin
                            physical_address = {32'b0, group_base_q[txn_group_index_q[candidate]]}
                                + {32'b0, txn_addresses_q[candidate][(lane*32)+:32]};
                            word_address = int'(physical_address / 64'd4);
                            if ((word_address % BANK_COUNT) == bank) begin
                                bank_grant_valid[bank] = 1'b1;
                                bank_grant_txn[bank] = candidate;
                                bank_grant_lane[bank] = lane;
                                found = 1'b1;
                            end
                        end
                    end
                end
            end
        end

        for (bank = 0; bank < BANK_COUNT; bank = bank + 1) begin
            if (bank_grant_valid[bank]) begin
                service_index = bank_grant_txn[bank];
                service_lane = bank_grant_lane[bank];
                txn_remaining_mask_next[service_index][service_lane] = 1'b0;
                if (!txn_write_q[service_index]) begin
                    physical_address = {32'b0, group_base_q[txn_group_index_q[service_index]]}
                        + {32'b0, txn_addresses_q[service_index][(service_lane*32)+:32]};
                    service_word = int'(physical_address / 64'd4);
                    if (memory_valid_q[service_word])
                        txn_lane_data_next[service_index][(service_lane*32)+:32]
                            = memory_data_q[service_word];
                    else
                        txn_lane_data_next[service_index][(service_lane*32)+:32] = 32'b0;
                end
            end
        end
    end

    always_comb begin : response_decode
        logic cancel_same_response;
        response_valid = 1'b0;
        response_workgroup_id = '0;
        response_wave_id = '0;
        response_transaction_tag = '0;
        response_write = 1'b0;
        response_lane_mask = '0;
        response_lane_data_flat = '0;
        response_fault_code = MEM_FAULT_NONE;
        response_fault_lane = 6'h3f;
        response_selected_index = -1;
        cancel_same_response = 1'b0;
        if (response_hold_valid_q)
            response_selected_index = int'($unsigned(response_hold_index_q));
        else
            response_selected_index = request_response_index;
        if (response_selected_index != -1) begin
            cancel_same_response = cancel_valid
                && txn_workgroup_id_q[response_selected_index] == cancel_workgroup_id
                && txn_wave_id_q[response_selected_index] == cancel_wave_id;
            if (!cancel_same_response) begin
                response_valid = 1'b1;
                response_workgroup_id = txn_workgroup_id_q[response_selected_index];
                response_wave_id = txn_wave_id_q[response_selected_index];
                response_transaction_tag = txn_tag_q[response_selected_index];
                response_write = txn_write_q[response_selected_index];
                response_lane_mask = txn_lane_mask_q[response_selected_index];
                response_lane_data_flat = txn_lane_data_q[response_selected_index];
                response_fault_code = txn_fault_code_q[response_selected_index];
                response_fault_lane = txn_fault_lane_q[response_selected_index];
            end
        end
    end

    // Keep status decode independent from response and cancel handshakes. In
    // particular, the per-wave map feeds LSU cancellation selection.
    always_comb begin : outstanding_decode
        integer transaction_index;
        outstanding_transaction_bitmap = '0;
        outstanding_wave_bitmap = '0;
        for (transaction_index = 0; transaction_index < MAX_OUTSTANDING_TRANSACTIONS; transaction_index = transaction_index + 1)
            if (txn_state_q[transaction_index] != TXN_FREE) begin
                outstanding_transaction_bitmap[transaction_index] = 1'b1;
                outstanding_wave_bitmap[txn_wave_id_q[transaction_index]] = 1'b1;
            end
    end

    always_comb begin : used_capacity_next
        logic [63:0] next_used;
        logic allocation_commits;
        logic [31:0] allocation_commit_bytes;
        next_used = {32'b0, used_bytes_q};
        allocation_commits = 1'b0;
        allocation_commit_bytes = 32'b0;
        if (release_accepted)
            next_used = next_used - {32'b0, group_bytes_q[release_group_index]};
        if (allocation_scrub_active_q
            && (allocation_scrub_word_q + 1 >= allocation_scrub_end_word_q)) begin
            allocation_commits = 1'b1;
            allocation_commit_bytes = allocation_pending_bytes_q;
        end else if (allocation_valid && allocation_ready
            && allocation_plan_failure == ALLOC_FAIL_NONE
            && allocation_byte_count == 0) begin
            allocation_commits = 1'b1;
            allocation_commit_bytes = 0;
        end
        if (allocation_commits)
            next_used = next_used + {32'b0, allocation_commit_bytes};
        used_bytes_next = next_used[31:0];
    end

    integer reset_index;
    integer bank_reset_index;
    integer transaction_reset_index;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            group_active_q <= '0;
            used_bytes_q <= '0;
            allocation_result_valid <= 1'b0;
            allocation_accepted <= 1'b0;
            allocation_failure <= ALLOC_FAIL_NONE;
            allocation_base_byte_address <= '0;
            allocation_scrub_active_q <= 1'b0;
            allocation_pending_id_q <= '0;
            allocation_pending_base_q <= '0;
            allocation_pending_bytes_q <= '0;
            allocation_pending_group_q <= '0;
            allocation_scrub_word_q <= '0;
            allocation_scrub_end_word_q <= '0;
            response_hold_valid_q <= 1'b0;
            response_hold_index_q <= '0;
            for (reset_index = 0; reset_index < MAX_WORKGROUP_CONTEXTS; reset_index = reset_index + 1) begin
                group_id_q[reset_index] <= '0;
                group_base_q[reset_index] <= '0;
                group_bytes_q[reset_index] <= '0;
            end
            for (transaction_reset_index = 0; transaction_reset_index < MAX_OUTSTANDING_TRANSACTIONS; transaction_reset_index = transaction_reset_index + 1) begin
                txn_state_q[transaction_reset_index] <= TXN_FREE;
                txn_group_index_q[transaction_reset_index] <= '0;
                txn_workgroup_id_q[transaction_reset_index] <= '0;
                txn_wave_id_q[transaction_reset_index] <= '0;
                txn_tag_q[transaction_reset_index] <= '0;
                txn_write_q[transaction_reset_index] <= 1'b0;
                txn_lane_mask_q[transaction_reset_index] <= '0;
                txn_remaining_mask_q[transaction_reset_index] <= '0;
                txn_addresses_q[transaction_reset_index] <= '0;
                txn_store_data_q[transaction_reset_index] <= '0;
                txn_lane_data_q[transaction_reset_index] <= '0;
                txn_fault_code_q[transaction_reset_index] <= MEM_FAULT_NONE;
                txn_fault_lane_q[transaction_reset_index] <= 6'h3f;
                txn_cancelled_q[transaction_reset_index] <= 1'b0;
            end
            for (bank_reset_index = 0; bank_reset_index < BANK_COUNT; bank_reset_index = bank_reset_index + 1)
                bank_rr_q[bank_reset_index] <= 0;
            for (reset_index = 0; reset_index < CU_WORD_COUNT; reset_index = reset_index + 1)
                memory_valid_q[reset_index] <= 1'b0;
        end else begin
            allocation_result_valid <= 1'b0;
            allocation_accepted <= 1'b0;
            allocation_failure <= ALLOC_FAIL_NONE;
            used_bytes_q <= used_bytes_next;

            if (release_accepted) begin
                group_active_q[release_group_index] <= 1'b0;
            end

            if (allocation_valid && allocation_ready) begin
                if (allocation_plan_failure != ALLOC_FAIL_NONE) begin
                    allocation_result_valid <= 1'b1;
                    allocation_accepted <= 1'b0;
                    allocation_failure <= allocation_plan_failure;
                end else begin
                    allocation_pending_id_q <= allocation_workgroup_id;
                    allocation_pending_base_q <= allocation_plan_base;
                    allocation_pending_bytes_q <= allocation_byte_count;
                    allocation_pending_group_q <= GROUP_INDEX_WIDTH'(allocation_plan_group);
                    if (allocation_byte_count == 0) begin
                        group_active_q[allocation_plan_group] <= 1'b1;
                        group_id_q[allocation_plan_group] <= allocation_workgroup_id;
                        group_base_q[allocation_plan_group] <= allocation_plan_base;
                        group_bytes_q[allocation_plan_group] <= '0;
                        allocation_result_valid <= 1'b1;
                        allocation_accepted <= 1'b1;
                        allocation_failure <= ALLOC_FAIL_NONE;
                        allocation_base_byte_address <= allocation_plan_base;
                    end else begin
                        allocation_scrub_active_q <= 1'b1;
                        allocation_scrub_word_q <= allocation_plan_base / 4;
                        allocation_scrub_end_word_q
                            <= int'(({32'b0, allocation_plan_base}
                                + {32'b0, allocation_byte_count} + 64'd3) / 64'd4);
                    end
                end
            end

            if (allocation_scrub_active_q) begin
                memory_valid_q[allocation_scrub_word_q] <= 1'b0;
                if (allocation_scrub_word_q + 1 >= allocation_scrub_end_word_q) begin
                    allocation_scrub_active_q <= 1'b0;
                    group_active_q[allocation_pending_group_q] <= 1'b1;
                    group_id_q[allocation_pending_group_q] <= allocation_pending_id_q;
                    group_base_q[allocation_pending_group_q] <= allocation_pending_base_q;
                    group_bytes_q[allocation_pending_group_q] <= allocation_pending_bytes_q;
                    allocation_result_valid <= 1'b1;
                    allocation_accepted <= 1'b1;
                    allocation_failure <= ALLOC_FAIL_NONE;
                    allocation_base_byte_address <= allocation_pending_base_q;
                end else begin
                    allocation_scrub_word_q <= allocation_scrub_word_q + 1;
                end
            end

            for (transaction_reset_index = 0; transaction_reset_index < MAX_OUTSTANDING_TRANSACTIONS; transaction_reset_index = transaction_reset_index + 1) begin
                txn_remaining_mask_q[transaction_reset_index]
                    <= txn_remaining_mask_next[transaction_reset_index];
                txn_lane_data_q[transaction_reset_index]
                    <= txn_lane_data_next[transaction_reset_index];
                if (txn_state_q[transaction_reset_index] == TXN_SERVICE
                    && txn_remaining_mask_next[transaction_reset_index] == 0) begin
                    if (txn_cancelled_q[transaction_reset_index])
                        txn_state_q[transaction_reset_index] <= TXN_FREE;
                    else
                        txn_state_q[transaction_reset_index] <= TXN_RESPONSE;
                end
                if (txn_state_q[transaction_reset_index] == TXN_RESPONSE
                    && txn_cancelled_q[transaction_reset_index])
                    txn_state_q[transaction_reset_index] <= TXN_FREE;
            end

            for (bank_reset_index = 0; bank_reset_index < BANK_COUNT; bank_reset_index = bank_reset_index + 1) begin
                if (bank_grant_valid[bank_reset_index]) begin
                    ff_transaction_index = bank_grant_txn[bank_reset_index];
                    ff_lane_index = bank_grant_lane[bank_reset_index];
                    bank_rr_q[bank_reset_index] <= (ff_transaction_index + 1)
                        % MAX_OUTSTANDING_TRANSACTIONS;
                    if (txn_write_q[ff_transaction_index]) begin
                        ff_word_address = ($unsigned(group_base_q[txn_group_index_q[ff_transaction_index]])
                            + $unsigned(txn_addresses_q[ff_transaction_index][(ff_lane_index*32)+:32])) / 4;
                        memory_data_q[ff_word_address]
                            <= txn_store_data_q[ff_transaction_index][(ff_lane_index*32)+:32];
                        memory_valid_q[ff_word_address] <= 1'b1;
                    end
                end
            end

            if (response_valid && response_ready)
                txn_state_q[response_selected_index] <= TXN_FREE;

            if (response_hold_valid_q
                && cancel_accepted
                && cancel_transaction_index == int'($unsigned(response_hold_index_q))) begin
                response_hold_valid_q <= 1'b0;
            end else if (response_valid && response_ready) begin
                response_hold_valid_q <= 1'b0;
            end else if (!response_hold_valid_q && response_valid && !response_ready) begin
                response_hold_valid_q <= 1'b1;
                response_hold_index_q <= TRANSACTION_INDEX_WIDTH'(response_selected_index);
            end

            if (cancel_accepted) begin
                txn_cancelled_q[cancel_transaction_index] <= 1'b1;
                if (txn_state_q[cancel_transaction_index] == TXN_RESPONSE
                    || (txn_state_q[cancel_transaction_index] == TXN_SERVICE
                        && txn_remaining_mask_next[cancel_transaction_index] == 0))
                    txn_state_q[cancel_transaction_index] <= TXN_FREE;
            end

            if (request_accepted) begin
                txn_workgroup_id_q[request_free_transaction] <= request_workgroup_id;
                txn_wave_id_q[request_free_transaction] <= request_wave_id;
                txn_tag_q[request_free_transaction] <= request_transaction_tag;
                txn_write_q[request_free_transaction] <= request_write;
                txn_lane_mask_q[request_free_transaction] <= request_lane_mask;
                txn_remaining_mask_q[request_free_transaction] <= request_remaining_lanes;
                txn_addresses_q[request_free_transaction] <= request_byte_addresses_flat;
                txn_store_data_q[request_free_transaction] <= request_store_data_flat;
                txn_lane_data_q[request_free_transaction] <= '0;
                txn_fault_code_q[request_free_transaction] <= request_fault_code;
                txn_fault_lane_q[request_free_transaction] <= request_fault_lane;
                txn_cancelled_q[request_free_transaction] <= 1'b0;
                if (request_group_index == -1)
                    txn_group_index_q[request_free_transaction] <= '0;
                else
                    txn_group_index_q[request_free_transaction] <= GROUP_INDEX_WIDTH'(request_group_index);
                if ((request_fault_code != MEM_FAULT_NONE) || (request_lane_mask == 0))
                    txn_state_q[request_free_transaction] <= TXN_RESPONSE;
                else
                    txn_state_q[request_free_transaction] <= TXN_SERVICE;
            end
        end
    end

    initial begin
        if (CU_SHARED_BYTES < 4 || BANK_COUNT < 1
            || MAX_WORKGROUP_CONTEXTS < 1
            || MAX_OUTSTANDING_TRANSACTIONS < 1
            || CU_SHARED_BYTES > 2147483644)
            $fatal(1, "invalid CU shared/local memory parameters");
    end
endmodule
