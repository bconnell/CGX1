// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_vector_instruction_word_decoder_tb;
    localparam integer SLOTS = 4;
    localparam integer SLOT_WIDTH = 2;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    logic [SLOTS-1:0] instruction_valid;
    logic [(SLOTS*32)-1:0] instruction_word_flat;
    logic [(SLOTS*32)-1:0] instruction_lane_mask_flat;
    logic [SLOTS-1:0] instruction_ready;
    logic [SLOTS-1:0] vector_request_valid;
    logic [(SLOTS*4)-1:0] vector_request_opcode_flat;
    logic [(SLOTS*8)-1:0] vector_request_source0_flat;
    logic [(SLOTS*8)-1:0] vector_request_source1_flat;
    logic [(SLOTS*8)-1:0] vector_request_destination_flat;
    logic [(SLOTS*32)-1:0] vector_request_lane_mask_flat;
    logic [SLOTS-1:0] vector_request_accepted;
    logic [SLOTS-1:0] unhandled_instruction_valid;
    logic [SLOTS-1:0] unhandled_instruction_ready;
    logic [(SLOTS*4)-1:0] unhandled_instruction_class_flat;
    logic [(SLOTS*32)-1:0] unhandled_instruction_word_flat;
    logic [(SLOTS*4)-1:0] unhandled_instruction_opcode_flat;
    logic [(SLOTS*8)-1:0] unhandled_instruction_destination_flat;
    logic [(SLOTS*8)-1:0] unhandled_instruction_source0_flat;
    logic [(SLOTS*8)-1:0] unhandled_instruction_source1_flat;

    logic [SLOTS-1:0] dependency_ready;
    logic selected_valid;
    logic [SLOT_WIDTH-1:0] selected_wave_slot;
    logic [3:0] selected_opcode;
    logic [7:0] selected_source0;
    logic [7:0] selected_source1;
    logic [7:0] selected_destination;
    logic [31:0] selected_lane_mask;
    logic issue_ready;
    logic issue_accepted;

    logic read_valid;
    logic [SLOT_WIDTH-1:0] read_wave_slot;
    logic [7:0] read_source0;
    logic [7:0] read_source1;
    logic read_response_valid;
    logic read_address_fault;
    logic read_uninitialized;
    logic [1023:0] read_data0;
    logic [1023:0] read_data1;
    logic write_valid;
    logic [SLOT_WIDTH-1:0] write_wave_slot;
    logic [7:0] write_destination;
    logic [31:0] write_lane_mask;
    logic [1023:0] write_data;
    logic write_ready;
    logic write_address_fault;
    logic complete_valid;
    logic [SLOT_WIDTH-1:0] complete_wave_slot;
    logic illegal_opcode;
    logic address_fault;
    logic uninitialized_fault;
    logic busy;
    logic [SLOT_WIDTH-1:0] live_wave_slot;
    logic [7:0] live_source0;
    logic [7:0] live_source1;
    logic [7:0] live_destination;
    logic source_locks_live;
    logic destination_lock_live;
    logic [31:0] destination_wave0 [0:31];
    logic [31:0] destination_wave3 [0:31];
    integer completion_count = 0;
    integer lane;
    integer timeout;

    always #5 clk = ~clk;

    function automatic logic [31:0] encode_base(
        input logic [3:0] instruction_class,
        input logic [3:0] opcode,
        input logic [7:0] destination,
        input logic [7:0] source0,
        input logic [7:0] source1);
        encode_base = {instruction_class, opcode, destination, source0, source1};
    endfunction

    function automatic logic [31:0] read_register_lane(
        input logic [SLOT_WIDTH-1:0] read_slot,
        input logic [7:0] register_index,
        input integer read_lane);
        begin
            read_register_lane = 32'h0;
            if ((read_slot == 0) && (register_index == 1) && (read_lane == 0))
                read_register_lane = 32'd10;
            else if ((read_slot == 0) && (register_index == 1) && (read_lane == 2))
                read_register_lane = 32'd30;
            else if ((read_slot == 0) && (register_index == 2) && (read_lane == 0))
                read_register_lane = 32'd3;
            else if ((read_slot == 0) && (register_index == 2) && (read_lane == 2))
                read_register_lane = 32'd7;
            else if ((read_slot == 3) && (register_index == 4) && (read_lane == 0))
                read_register_lane = 32'd20;
            else if ((read_slot == 3) && (register_index == 4) && (read_lane == 2))
                read_register_lane = 32'd3;
            else if ((read_slot == 3) && (register_index == 5) && (read_lane == 0))
                read_register_lane = 32'd8;
            else if ((read_slot == 3) && (register_index == 5) && (read_lane == 2))
                read_register_lane = 32'd9;
        end
    endfunction

    cgx1_vector_instruction_word_decoder #(.RESIDENT_WAVE_SLOTS(SLOTS)) decoder (
        .instruction_valid(instruction_valid),
        .instruction_word_flat(instruction_word_flat),
        .instruction_lane_mask_flat(instruction_lane_mask_flat),
        .instruction_ready(instruction_ready),
        .vector_request_valid(vector_request_valid),
        .vector_request_opcode_flat(vector_request_opcode_flat),
        .vector_request_source0_flat(vector_request_source0_flat),
        .vector_request_source1_flat(vector_request_source1_flat),
        .vector_request_destination_flat(vector_request_destination_flat),
        .vector_request_lane_mask_flat(vector_request_lane_mask_flat),
        .vector_request_accepted(vector_request_accepted),
        .unhandled_instruction_valid(unhandled_instruction_valid),
        .unhandled_instruction_ready(unhandled_instruction_ready),
        .unhandled_instruction_class_flat(unhandled_instruction_class_flat),
        .unhandled_instruction_word_flat(unhandled_instruction_word_flat),
        .unhandled_instruction_opcode_flat(unhandled_instruction_opcode_flat),
        .unhandled_instruction_destination_flat(unhandled_instruction_destination_flat),
        .unhandled_instruction_source0_flat(unhandled_instruction_source0_flat),
        .unhandled_instruction_source1_flat(unhandled_instruction_source1_flat)
    );

    cgx1_resident_vector_execution_frontend #(
        .RESIDENT_WAVE_SLOTS(SLOTS),
        .WAVE_SLOT_WIDTH(SLOT_WIDTH)
    ) resident_vector_frontend (
        .clk(clk),
        .reset_n(reset_n),
        .request_valid(vector_request_valid),
        .dependency_ready(dependency_ready),
        .request_opcode(vector_request_opcode_flat),
        .request_source0(vector_request_source0_flat),
        .request_source1(vector_request_source1_flat),
        .request_destination(vector_request_destination_flat),
        .request_lane_mask(vector_request_lane_mask_flat),
        .request_accepted(vector_request_accepted),
        .selected_valid(selected_valid),
        .selected_wave_slot(selected_wave_slot),
        .selected_opcode(selected_opcode),
        .selected_source0(selected_source0),
        .selected_source1(selected_source1),
        .selected_destination(selected_destination),
        .selected_lane_mask(selected_lane_mask),
        .selected_ready(issue_ready)
    );

    cgx1_vector_int32_pipeline #(.WAVE_SLOT_WIDTH(SLOT_WIDTH)) vector_pipeline (
        .clk(clk),
        .reset_n(reset_n),
        .issue_valid(selected_valid),
        .issue_wave_slot(selected_wave_slot),
        .issue_opcode(selected_opcode),
        .issue_source0(selected_source0),
        .issue_source1(selected_source1),
        .issue_destination(selected_destination),
        .issue_lane_mask(selected_lane_mask),
        .issue_ready(issue_ready),
        .issue_accepted(issue_accepted),
        .read_valid(read_valid),
        .read_wave_slot(read_wave_slot),
        .read_source0(read_source0),
        .read_source1(read_source1),
        .read_response_valid(read_response_valid),
        .read_address_fault(read_address_fault),
        .read_uninitialized(read_uninitialized),
        .read_data0(read_data0),
        .read_data1(read_data1),
        .write_valid(write_valid),
        .write_wave_slot(write_wave_slot),
        .write_destination(write_destination),
        .write_lane_mask(write_lane_mask),
        .write_data(write_data),
        .write_ready(write_ready),
        .write_address_fault(write_address_fault),
        .complete_valid(complete_valid),
        .complete_wave_slot(complete_wave_slot),
        .illegal_opcode(illegal_opcode),
        .address_fault(address_fault),
        .uninitialized_fault(uninitialized_fault),
        .busy(busy),
        .live_wave_slot(live_wave_slot),
        .live_source0(live_source0),
        .live_source1(live_source1),
        .live_destination(live_destination),
        .source_locks_live(source_locks_live),
        .destination_lock_live(destination_lock_live)
    );

    always_comb begin
        read_response_valid = read_valid;
        read_address_fault = 1'b0;
        read_uninitialized = 1'b0;
        read_data0 = '0;
        read_data1 = '0;
        for (integer read_lane = 0; read_lane < 32; read_lane = read_lane + 1) begin
            read_data0[(read_lane*32)+:32]
                = read_register_lane(read_wave_slot, read_source0, read_lane);
            read_data1[(read_lane*32)+:32]
                = read_register_lane(read_wave_slot, read_source1, read_lane);
        end
        write_ready = 1'b1;
        write_address_fault = 1'b0;
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            completion_count <= 0;
        end else begin
            if (complete_valid)
                completion_count <= completion_count + 1;
            if (write_valid && write_ready) begin
                for (integer write_lane = 0; write_lane < 32; write_lane = write_lane + 1) begin
                    if (write_lane_mask[write_lane] && (write_wave_slot == 0)
                        && (write_destination == 8))
                        destination_wave0[write_lane] <= write_data[(write_lane*32)+:32];
                    if (write_lane_mask[write_lane] && (write_wave_slot == 3)
                        && (write_destination == 9))
                        destination_wave3[write_lane] <= write_data[(write_lane*32)+:32];
                end
            end
        end
    end

    task automatic accept_held_instructions;
        integer timeout;
        logic [SLOTS-1:0] accepted_now;
        begin
            timeout = 0;
            while ((instruction_valid != '0) && (timeout < 100)) begin
                #1;
                if (instruction_valid[3] && busy && !instruction_ready[3]
                    && (!vector_request_valid[3]
                        || vector_request_opcode_flat[(3*4)+:4] != 4'h1
                        || vector_request_destination_flat[(3*8)+:8] != 8'd9))
                    $fatal(1, "decoded wave request changed while held under execution backpressure");
                accepted_now = instruction_valid & instruction_ready;
                @(posedge clk);
                @(negedge clk);
                instruction_valid = instruction_valid & ~accepted_now;
                timeout = timeout + 1;
            end
            if (instruction_valid != '0)
                $fatal(1, "word decoder input did not make forward progress");
        end
    endtask

    initial begin
        instruction_valid = '0;
        instruction_word_flat = '0;
        instruction_lane_mask_flat = '0;
        unhandled_instruction_ready = '0;
        dependency_ready = '1;
        for (lane = 0; lane < 32; lane = lane + 1) begin
            destination_wave0[lane] = 32'h11111111;
            destination_wave3[lane] = 32'h22222222;
        end

        repeat (2) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;

        // Non-vector classes remain intact and use their own backpressure.
        instruction_word_flat[(2*32)+:32] = encode_base(4'h2, 4'h0, 8'h9, 8'h7, 8'h6);
        instruction_valid[2] = 1'b1;
        #1;
        if (vector_request_valid != '0 || unhandled_instruction_valid != 4'b0100
            || unhandled_instruction_class_flat[(2*4)+:4] != 4'h2
            || unhandled_instruction_word_flat[(2*32)+:32] != instruction_word_flat[(2*32)+:32]
            || unhandled_instruction_opcode_flat[(2*4)+:4] !== 4'h0
            || unhandled_instruction_destination_flat[(2*8)+:8] !== 8'h9
            || unhandled_instruction_source0_flat[(2*8)+:8] !== 8'h7
            || unhandled_instruction_source1_flat[(2*8)+:8] !== 8'h6
            || instruction_ready[2])
            $fatal(1, "non-vector base fields were not decoded or handler backpressure was ignored");
        @(negedge clk);
        unhandled_instruction_ready[2] = 1'b1;
        #1;
        if (!instruction_ready[2])
            $fatal(1, "non-vector word did not become consumable when its handler was ready");
        @(posedge clk);
        @(negedge clk);
        instruction_valid[2] = 1'b0;
        unhandled_instruction_ready[2] = 1'b0;

        // Two raw words decode to independent waves and survive execution backpressure.
        instruction_word_flat[(0*32)+:32] = encode_base(4'h1, 4'h0, 8'd8, 8'd1, 8'd2);
        instruction_word_flat[(3*32)+:32] = encode_base(4'h1, 4'h1, 8'd9, 8'd4, 8'd5);
        instruction_lane_mask_flat[(0*32)+:32] = 32'h00000005;
        instruction_lane_mask_flat[(3*32)+:32] = 32'h00000005;
        instruction_valid[0] = 1'b1;
        instruction_valid[3] = 1'b1;
        #1;
        if (vector_request_valid != 4'b1001
            || vector_request_opcode_flat[(0*4)+:4] != 4'h0
            || vector_request_destination_flat[(0*8)+:8] != 8'd8
            || vector_request_source0_flat[(3*8)+:8] != 8'd4
            || vector_request_source1_flat[(3*8)+:8] != 8'd5
            || vector_request_lane_mask_flat[(3*32)+:32] != 32'h00000005)
            $fatal(1, "base word fields or per-wave lane mask decoded incorrectly");
        accept_held_instructions();

        timeout = 0;
        while ((completion_count < 2) && (timeout < 100)) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (completion_count != 2)
            $fatal(1, "resident vector scheduler did not complete both decoded waves");
        if (destination_wave0[0] != 32'd13 || destination_wave0[2] != 32'd37
            || destination_wave0[1] != 32'h11111111
            || destination_wave3[0] != 32'd12 || destination_wave3[2] != 32'hfffffffa
            || destination_wave3[1] != 32'h22222222)
            $fatal(1, "decoded raw words did not execute with lane-local masked writeback");

        // Reserved vector opcodes still reach the existing pipeline fault path.
        instruction_word_flat[(1*32)+:32] = encode_base(4'h1, 4'h8, 8'd10, 8'd1, 8'd2);
        instruction_valid[1] = 1'b1;
        accept_held_instructions();
        #1;
        if (!complete_valid || !illegal_opcode || read_valid || write_valid)
            $fatal(1, "reserved vector opcode did not reach the existing illegal-opcode completion");

        $display("[pass] CGX 1 per-wave vector instruction word decode and execution checks passed.");
        $finish;
    end
endmodule
