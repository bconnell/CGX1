// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
`timescale 1ns/1ps

module cgx1_instruction_fetch_unit_tb;
    localparam integer SLOTS = 4;
    localparam integer WG_WIDTH = 8;
    localparam integer SLOT_WIDTH = 2;
    localparam integer EPOCH_WIDTH = 8;
    localparam integer TAG_WIDTH = 16;
    localparam integer PC_WIDTH = 57;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    always #5 clk = ~clk;

    logic [EPOCH_WIDTH-1:0] execution_epoch = '0;
    logic [SLOTS-1:0] wave_live_mask = '0;
    logic [SLOTS-1:0] fetch_eligible_mask = '0;
    logic [(SLOTS*WG_WIDTH)-1:0] wave_workgroup_id_flat = '0;
    logic [(SLOTS*PC_WIDTH)-1:0] wave_pc_flat = '0;
    logic [SLOTS-1:0] issue_block_mask;
    logic [SLOTS-1:0] quiescence_busy_mask;
    logic [SLOTS-1:0] instruction_valid;
    logic [(SLOTS*32)-1:0] instruction_word_flat;
    logic [(SLOTS*WG_WIDTH)-1:0] instruction_workgroup_id_flat;
    logic [(SLOTS*PC_WIDTH)-1:0] instruction_pc_flat;
    logic [(SLOTS*EPOCH_WIDTH)-1:0] instruction_epoch_flat;
    logic [(SLOTS*TAG_WIDTH)-1:0] instruction_transaction_tag_flat;
    logic [SLOTS-1:0] instruction_ready = '0;

    logic request_valid;
    logic request_ready = 1'b0;
    logic [WG_WIDTH-1:0] request_workgroup_id;
    logic [SLOT_WIDTH-1:0] request_wave_slot;
    logic [EPOCH_WIDTH-1:0] request_epoch;
    logic [TAG_WIDTH-1:0] request_transaction_tag;
    logic [PC_WIDTH-1:0] request_pc;

    logic response_valid = 1'b0;
    logic response_ready;
    logic [WG_WIDTH-1:0] response_workgroup_id = '0;
    logic [SLOT_WIDTH-1:0] response_wave_slot = '0;
    logic [EPOCH_WIDTH-1:0] response_epoch = '0;
    logic [TAG_WIDTH-1:0] response_transaction_tag = '0;
    logic [PC_WIDTH-1:0] response_pc = '0;
    logic [31:0] response_word = '0;
    logic [2:0] response_fault_code = '0;

    logic [SLOTS-1:0] fault_valid_mask;
    logic [(SLOTS*WG_WIDTH)-1:0] fault_workgroup_id_flat;
    logic [(SLOTS*EPOCH_WIDTH)-1:0] fault_epoch_flat;
    logic [(SLOTS*TAG_WIDTH)-1:0] fault_transaction_tag_flat;
    logic [(SLOTS*PC_WIDTH)-1:0] fault_pc_flat;
    logic [(SLOTS*3)-1:0] fault_code_flat;
    logic [SLOTS-1:0] fault_ready_mask = '0;

    cgx1_instruction_fetch_unit #(
        .RESIDENT_WAVE_SLOTS(SLOTS), .WORKGROUP_ID_WIDTH(WG_WIDTH),
        .WAVE_SLOT_WIDTH(SLOT_WIDTH), .MEMORY_EPOCH_WIDTH(EPOCH_WIDTH),
        .TRANSACTION_TAG_WIDTH(TAG_WIDTH), .VIRTUAL_ADDRESS_WIDTH(PC_WIDTH)
    ) dut (
        .clk(clk), .reset_n(reset_n), .execution_epoch(execution_epoch),
        .wave_live_mask(wave_live_mask), .fetch_eligible_mask(fetch_eligible_mask),
        .wave_workgroup_id_flat(wave_workgroup_id_flat), .wave_pc_flat(wave_pc_flat),
        .issue_block_mask(issue_block_mask), .quiescence_busy_mask(quiescence_busy_mask),
        .instruction_valid(instruction_valid), .instruction_word_flat(instruction_word_flat),
        .instruction_workgroup_id_flat(instruction_workgroup_id_flat),
        .instruction_pc_flat(instruction_pc_flat), .instruction_epoch_flat(instruction_epoch_flat),
        .instruction_transaction_tag_flat(instruction_transaction_tag_flat),
        .instruction_ready(instruction_ready),
        .request_valid(request_valid), .request_ready(request_ready),
        .request_workgroup_id(request_workgroup_id), .request_wave_slot(request_wave_slot),
        .request_epoch(request_epoch), .request_transaction_tag(request_transaction_tag),
        .request_pc(request_pc), .response_valid(response_valid),
        .response_ready(response_ready), .response_workgroup_id(response_workgroup_id),
        .response_wave_slot(response_wave_slot), .response_epoch(response_epoch),
        .response_transaction_tag(response_transaction_tag), .response_pc(response_pc),
        .response_word(response_word), .response_fault_code(response_fault_code),
        .fault_valid_mask(fault_valid_mask),
        .fault_workgroup_id_flat(fault_workgroup_id_flat), .fault_epoch_flat(fault_epoch_flat),
        .fault_transaction_tag_flat(fault_transaction_tag_flat), .fault_pc_flat(fault_pc_flat),
        .fault_code_flat(fault_code_flat), .fault_ready_mask(fault_ready_mask)
    );

    task automatic tick;
        begin @(posedge clk); #1; end
    endtask

    task automatic configure_wave(input integer slot, input logic [7:0] group_id,
        input logic [PC_WIDTH-1:0] pc);
        begin
            wave_live_mask[slot] = 1'b1;
            wave_workgroup_id_flat[(slot*WG_WIDTH)+:WG_WIDTH] = group_id;
            wave_pc_flat[(slot*PC_WIDTH)+:PC_WIDTH] = pc;
            fetch_eligible_mask[slot] = 1'b1;
        end
    endtask

    task automatic accept_request(input integer slot, input logic [7:0] expected_group,
        input logic [PC_WIDTH-1:0] expected_pc,
        output logic [TAG_WIDTH-1:0] accepted_tag);
        begin
            #1;
            if (!request_valid || request_wave_slot != slot[SLOT_WIDTH-1:0]
                || request_workgroup_id != expected_group || request_pc != expected_pc
                || request_epoch != execution_epoch || request_transaction_tag == 0)
                $fatal(1, "fetch request identity mismatch for slot %0d", slot);
            accepted_tag = request_transaction_tag;
            request_ready = 1'b1;
            tick();
            request_ready = 1'b0;
            fetch_eligible_mask[slot] = 1'b0;
        end
    endtask

    task automatic respond(input integer slot, input logic [7:0] group_id,
        input logic [EPOCH_WIDTH-1:0] epoch, input logic [TAG_WIDTH-1:0] tag,
        input logic [PC_WIDTH-1:0] pc, input logic [31:0] word,
        input logic [2:0] fault_code);
        begin
            response_workgroup_id = group_id;
            response_wave_slot = slot[SLOT_WIDTH-1:0];
            response_epoch = epoch;
            response_transaction_tag = tag;
            response_pc = pc;
            response_word = word;
            response_fault_code = fault_code;
            response_valid = 1'b1;
            #1;
            if (!response_ready) $fatal(1, "fetch response backpressured");
            tick();
            response_valid = 1'b0;
            response_fault_code = '0;
        end
    endtask

    logic [TAG_WIDTH-1:0] tag0, tag1, tag2;
    logic [7:0] old_group;
    logic [EPOCH_WIDTH-1:0] old_epoch;
    logic [PC_WIDTH-1:0] old_pc;
    logic [31:0] random_state;
    integer random_slot;
    logic random_kill;
    logic [2:0] random_fault;
    logic [7:0] random_group;
    logic [PC_WIDTH-1:0] random_pc;
    logic [TAG_WIDTH-1:0] random_tag;
    integer cycle;
    initial begin
        repeat (2) tick();
        reset_n = 1'b1;
        execution_epoch = 8'h21;

        // Two waves may be outstanding concurrently. The second response may
        // arrive first, and each completed word remains buffered independently.
        configure_wave(0, 8'h11, 57'h100);
        configure_wave(2, 8'h22, 57'h200);
        tick();
        fetch_eligible_mask[0] = 1'b0;
        accept_request(0, 8'h11, 57'h100, tag0);
        configure_wave(2, 8'h22, 57'h200);
        tick();
        fetch_eligible_mask[2] = 1'b0;
        if (!request_valid) $fatal(1, "independent wave fetch was not issued");
        accept_request(2, 8'h22, 57'h200, tag1);
        if (issue_block_mask[0] !== 1'b1 || issue_block_mask[2] !== 1'b1
            || quiescence_busy_mask[0] !== 1'b1 || quiescence_busy_mask[2] !== 1'b1)
            $fatal(1, "outstanding fetches did not block issue and release");

        respond(2, 8'h22, execution_epoch, tag1, 57'h200, 32'h1000_0001, 3'b0);
        respond(0, 8'h11, execution_epoch, tag0, 57'h100, 32'h1000_0002, 3'b0);
        if (instruction_valid !== 4'b0101
            || instruction_word_flat[64+:32] != 32'h1000_0001
            || instruction_word_flat[0+:32] != 32'h1000_0002
            || instruction_pc_flat[2*PC_WIDTH+:PC_WIDTH] != 57'h200
            || instruction_workgroup_id_flat[(2*WG_WIDTH)+:WG_WIDTH] != 8'h22)
            $fatal(1, "out-of-order fetch responses were not buffered by wave identity");
        if (issue_block_mask[0] || issue_block_mask[2]
            || !quiescence_busy_mask[0] || !quiescence_busy_mask[2])
            $fatal(1, "buffered instructions must issue but remain release-active");
        instruction_ready = 4'b0101;
        tick();
        instruction_ready = '0;
        wave_live_mask = '0;
        if (quiescence_busy_mask != '0) $fatal(1, "consumed words retained fetch state");

        // A mismatched response is drained and ignored without releasing the
        // outstanding owner or corrupting a reused wave slot.
        configure_wave(1, 8'h31, 57'h304);
        tick();
        fetch_eligible_mask[1] = 1'b0;
        accept_request(1, 8'h31, 57'h304, tag2);
        respond(1, 8'h31, execution_epoch, tag2 + 1'b1, 57'h304, 32'hdead_beef, 3'b0);
        if (instruction_valid[1] || !quiescence_busy_mask[1])
            $fatal(1, "mismatched response modified or released fetch state");
        respond(1, 8'h31, execution_epoch, tag2, 57'h304, 32'h2000_0003, 3'b0);
        if (!instruction_valid[1] || instruction_word_flat[32+:32] != 32'h2000_0003)
            $fatal(1, "matching fetch response was not delivered");
        instruction_ready[1] = 1'b1;
        tick();
        instruction_ready[1] = 1'b0;

        // Response faults remain stable until accepted and never become words.
        configure_wave(3, 8'h44, 57'h408);
        tick();
        fetch_eligible_mask[3] = 1'b0;
        accept_request(3, 8'h44, 57'h408, tag2);
        respond(3, 8'h44, execution_epoch, tag2, 57'h408, 32'hbad0_bad0, 3'd5);
        if (!fault_valid_mask[3] || fault_code_flat[(3*3)+:3] != 3'd5 || instruction_valid[3])
            $fatal(1, "fetch fault was not retained as a terminal event");
        tick();
        if (!fault_valid_mask[3]) $fatal(1, "backpressured fetch fault did not remain stable");
        fault_ready_mask[3] = 1'b1;
        tick();
        fault_ready_mask[3] = 1'b0;
        wave_live_mask[3] = 1'b0;
        if (fault_valid_mask[3] || quiescence_busy_mask[3])
            $fatal(1, "accepted fetch fault leaked the wave's fetch state");

        // Kill while a ready/valid request is presented but unaccepted. The
        // request stays stable, then its eventual response is discarded.
        configure_wave(0, 8'h51, 57'h500);
        tick();
        fetch_eligible_mask[0] = 1'b0;
        #1;
        if (!request_valid) $fatal(1, "kill test request was not presented");
        old_group = request_workgroup_id;
        old_epoch = request_epoch;
        old_pc = request_pc;
        tag0 = request_transaction_tag;
        wave_live_mask[0] = 1'b0;
        tick();
        if (!request_valid || request_workgroup_id != old_group || request_epoch != old_epoch
            || request_pc != old_pc || request_transaction_tag != tag0)
            $fatal(1, "presented request changed after wave kill");
        accept_request(0, old_group, old_pc, tag0);
        respond(0, old_group, old_epoch, tag0, old_pc, 32'h1234_5678, 3'b0);
        if (instruction_valid[0] || quiescence_busy_mask[0])
            $fatal(1, "killed wave did not drain and discard its fetch response");

        // Reset recovery uses a new external epoch; a response from the prior
        // reset epoch cannot match the next request even after slot reuse.
        wave_live_mask[1] = 1'b1;
        wave_workgroup_id_flat[WG_WIDTH+:WG_WIDTH] = 8'h61;
        wave_pc_flat[PC_WIDTH+:PC_WIDTH] = 57'h604;
        fetch_eligible_mask[1] = 1'b1;
        tick();
        fetch_eligible_mask[1] = 1'b0;
        old_group = 8'h61;
        old_epoch = execution_epoch;
        old_pc = 57'h604;
        accept_request(1, 8'h61, 57'h604, tag0);
        reset_n = 1'b0;
        tick();
        if (quiescence_busy_mask != '0) $fatal(1, "reset did not clear fetch state");
        reset_n = 1'b1;
        execution_epoch = old_epoch + 1'b1;
        wave_live_mask = '0;
        respond(1, old_group, old_epoch, tag0, old_pc, 32'hface_cafe, 3'b0);
        if (instruction_valid != '0) $fatal(1, "pre-reset stale response became an instruction");
        configure_wave(1, old_group, old_pc);
        tick();
        fetch_eligible_mask[1] = 1'b0;
        accept_request(1, old_group, old_pc, tag1);
        respond(1, old_group, old_epoch, tag0, old_pc, 32'hface_cafe, 3'b0);
        if (instruction_valid[1] || !quiescence_busy_mask[1])
            $fatal(1, "old-epoch response matched a post-reset request");
        respond(1, old_group, execution_epoch, tag1, old_pc, 32'h6000_0000, 3'b0);
        if (!instruction_valid[1] || instruction_word_flat[32+:32] != 32'h6000_0000)
            $fatal(1, "post-reset response failed after stale response drain");
        instruction_ready[1] = 1'b1;
        tick();
        instruction_ready[1] = 1'b0;
        wave_live_mask = '0;

        // An unaligned fetch PC faults locally without presenting a memory
        // request and remains owned until terminal delivery.
        configure_wave(0, 8'h69, 57'h701);
        tick();
        fetch_eligible_mask[0] = 1'b0;
        if (request_valid || !fault_valid_mask[0]
            || fault_code_flat[0+:3] != 3'd1 || !quiescence_busy_mask[0])
            $fatal(1, "unaligned instruction PC did not become a terminal fetch fault");
        fault_ready_mask[0] = 1'b1;
        tick();
        fault_ready_mask[0] = 1'b0;
        wave_live_mask[0] = 1'b0;
        if (fault_valid_mask[0] || quiescence_busy_mask[0])
            $fatal(1, "accepted invalid-PC fault leaked fetch ownership");

        // A fixed-seed lifecycle pressure loop checks ready/valid stability,
        // independent wave ownership, kill drain, fault retirement, and reuse.
        random_state = 32'h6c73_7531;
        for (cycle = 0; cycle < 200; cycle = cycle + 1) begin
            random_state = (random_state * 32'd1664525) + 32'd1013904223;
            random_slot = random_state[6:5];
            random_group = 8'h70 + random_slot;
            random_pc = 57'h800 + (cycle * 4);
            random_kill = random_state[7];
            random_fault = (random_state[10:8] == 3'd0) ? 3'd3 : 3'd0;
            wave_live_mask = '0;
            configure_wave(random_slot, random_group, random_pc);
            tick();
            fetch_eligible_mask[random_slot] = 1'b0;
            request_ready = 1'b0;
            #1;
            if (!request_valid || request_wave_slot != random_slot[SLOT_WIDTH-1:0]
                || request_workgroup_id != random_group || request_pc != random_pc)
                $fatal(1, "random request capture failed at cycle %0d", cycle);
            random_tag = request_transaction_tag;
            repeat (random_state[12:11]) begin
                tick();
                if (!request_valid || request_wave_slot != random_slot[SLOT_WIDTH-1:0]
                    || request_transaction_tag != random_tag || request_pc != random_pc)
                    $fatal(1, "random request changed under backpressure at cycle %0d", cycle);
            end
            request_ready = 1'b1;
            tick();
            request_ready = 1'b0;
            repeat (random_state[14:13]) tick();
            if (random_kill) wave_live_mask[random_slot] = 1'b0;
            respond(random_slot, random_group, execution_epoch, random_tag, random_pc,
                32'h9000_0000 + cycle, random_fault);
            if (random_kill) begin
                if (instruction_valid[random_slot] || fault_valid_mask[random_slot]
                    || quiescence_busy_mask[random_slot])
                    $fatal(1, "random killed fetch failed to drain at cycle %0d", cycle);
            end else if (random_fault != 0) begin
                if (!fault_valid_mask[random_slot]
                    || fault_code_flat[(random_slot*3)+:3] != random_fault)
                    $fatal(1, "random fetch fault missing at cycle %0d", cycle);
                fault_ready_mask[random_slot] = 1'b1;
                tick();
                fault_ready_mask[random_slot] = 1'b0;
            end else begin
                if (!instruction_valid[random_slot]
                    || instruction_word_flat[(random_slot*32)+:32] != (32'h9000_0000 + cycle))
                    $fatal(1, "random instruction response missing at cycle %0d", cycle);
                instruction_ready[random_slot] = 1'b1;
                tick();
                instruction_ready[random_slot] = 1'b0;
            end
            wave_live_mask[random_slot] = 1'b0;
            fetch_eligible_mask[random_slot] = 1'b0;
            if (quiescence_busy_mask[random_slot])
                $fatal(1, "random transaction leaked fetch ownership at cycle %0d", cycle);
            tick();
        end
        request_ready = 1'b0;
        instruction_ready = '0;
        response_valid = 1'b0;
        wave_live_mask = '0;
        fetch_eligible_mask = '0;
        repeat (2) tick();

        $display("[pass] CGX 1 identity-safe instruction fetch checks passed.");
        $finish;
    end
endmodule
