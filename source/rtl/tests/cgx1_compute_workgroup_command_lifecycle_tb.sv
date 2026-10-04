`timescale 1ns/1ps
module cgx1_compute_workgroup_command_lifecycle_tb;
    localparam integer CONTEXTS = 4;
    localparam integer WG_WIDTH = 8;

    logic clk = 1'b0;
    logic reset_n = 1'b0;
    always #5 clk = ~clk;

    logic submit_valid = 1'b0;
    logic submit_capacity_ready;
    logic submit_accepted;
    logic [5:0] submit_context = '0;
    logic [63:0] submit_process = '0;
    logic [63:0] submit_address_space = '0;
    logic [WG_WIDTH-1:0] submit_workgroup = '0;
    logic [63:0] submit_submission = '0;
    logic [63:0] submit_position = '0;
    logic [63:0] submit_incarnation = '0;

    logic admission_valid = 1'b0;
    logic admission_ready;
    logic [5:0] admission_context = '0;
    logic [63:0] admission_process = '0;
    logic [63:0] admission_address_space = '0;
    logic [WG_WIDTH-1:0] admission_workgroup = '0;
    logic [63:0] admission_submission = '0;
    logic [63:0] admission_position = '0;
    logic [63:0] admission_incarnation = '0;
    logic [2:0] admission_status = '0;
    logic [4:0] admission_failure = '0;

    logic [CONTEXTS-1:0] cancelled_queue_mask = '0;
    logic retire_valid = 1'b0;
    logic retire_ready;
    logic [WG_WIDTH-1:0] retire_workgroup = '0;
    logic abort_valid;
    logic abort_ready = 1'b0;
    logic [WG_WIDTH-1:0] abort_workgroup;

    logic completion_valid;
    logic completion_ready = 1'b0;
    logic [5:0] completion_context;
    logic [63:0] completion_process;
    logic [63:0] completion_address_space;
    logic [WG_WIDTH-1:0] completion_workgroup;
    logic [63:0] completion_submission;
    logic [63:0] completion_position;
    logic [63:0] completion_incarnation;
    logic [2:0] completion_status;
    logic [4:0] completion_failure;
    logic [CONTEXTS-1:0] queue_drained_mask;
    logic [4:0] tracked_count;

    assign submit_accepted = submit_valid && submit_capacity_ready;

    cgx1_compute_workgroup_command_lifecycle #(
        .QUEUE_CONTEXT_COUNT(CONTEXTS),
        .COMMAND_SLOTS(16),
        .WORKGROUP_ID_WIDTH(WG_WIDTH)
    ) dut (
        .clk(clk), .reset_n(reset_n),
        .submit_accepted_valid(submit_accepted),
        .submit_capacity_ready(submit_capacity_ready),
        .submit_queue_context_id(submit_context),
        .submit_process_id(submit_process),
        .submit_address_space_id(submit_address_space),
        .submit_workgroup_id(submit_workgroup),
        .submit_submission_id(submit_submission),
        .submit_packet_byte_position(submit_position),
        .submit_queue_incarnation_id(submit_incarnation),
        .admission_valid(admission_valid), .admission_ready(admission_ready),
        .admission_queue_context_id(admission_context),
        .admission_process_id(admission_process),
        .admission_address_space_id(admission_address_space),
        .admission_workgroup_id(admission_workgroup),
        .admission_submission_id(admission_submission),
        .admission_packet_byte_position(admission_position),
        .admission_queue_incarnation_id(admission_incarnation),
        .admission_status(admission_status), .admission_failure(admission_failure),
        .cancelled_queue_mask(cancelled_queue_mask),
        .workgroup_retire_valid(retire_valid), .workgroup_retire_ready(retire_ready),
        .workgroup_retire_id(retire_workgroup),
        .workgroup_abort_valid(abort_valid), .workgroup_abort_ready(abort_ready),
        .workgroup_abort_id(abort_workgroup),
        .completion_valid(completion_valid), .completion_ready(completion_ready),
        .completion_queue_context_id(completion_context),
        .completion_process_id(completion_process),
        .completion_address_space_id(completion_address_space),
        .completion_workgroup_id(completion_workgroup),
        .completion_submission_id(completion_submission),
        .completion_packet_byte_position(completion_position),
        .completion_queue_incarnation_id(completion_incarnation),
        .completion_status(completion_status), .completion_failure(completion_failure),
        .queue_drained_mask(queue_drained_mask), .tracked_count(tracked_count)
    );

    task automatic submit_command(
        input logic [5:0] context_id,
        input logic [WG_WIDTH-1:0] workgroup_id,
        input logic [63:0] submission_id,
        input logic [63:0] packet_position,
        input logic [63:0] incarnation_id);
        integer guard;
        begin
            @(negedge clk);
            submit_context = context_id;
            submit_workgroup = workgroup_id;
            submit_submission = submission_id;
            submit_position = packet_position;
            submit_incarnation = incarnation_id;
            submit_process = 64'h1000000000000000 | context_id;
            submit_address_space = 64'h2000000000000000 | context_id;
            submit_valid = 1'b1;
            guard = 0;
            while (!submit_capacity_ready && guard < 20) begin
                @(negedge clk); guard = guard + 1;
            end
            if (guard >= 20) $fatal(1, "lifecycle command table failed to provide capacity");
            @(posedge clk); #1;
            @(negedge clk); submit_valid = 1'b0;
        end
    endtask

    task automatic send_admission(
        input logic [5:0] context_id,
        input logic [WG_WIDTH-1:0] workgroup_id,
        input logic [63:0] submission_id,
        input logic [63:0] packet_position,
        input logic [63:0] incarnation_id,
        input logic [2:0] status,
        input logic [4:0] failure_code);
        begin
            @(negedge clk);
            admission_context = context_id;
            admission_workgroup = workgroup_id;
            admission_submission = submission_id;
            admission_position = packet_position;
            admission_incarnation = incarnation_id;
            admission_process = 64'h1000000000000000 | context_id;
            admission_address_space = 64'h2000000000000000 | context_id;
            admission_status = status;
            admission_failure = failure_code;
            admission_valid = 1'b1;
            #1;
            if (!admission_ready) $fatal(1, "lifecycle admission result was not consumed");
            @(posedge clk); #1;
            @(negedge clk); admission_valid = 1'b0;
        end
    endtask

    task automatic send_retirement(input logic [WG_WIDTH-1:0] workgroup_id);
        begin
            @(negedge clk); retire_workgroup = workgroup_id; retire_valid = 1'b1;
            #1;
            if (!retire_ready) $fatal(1, "lifecycle retirement was not consumed");
            @(posedge clk); #1;
            @(negedge clk); retire_valid = 1'b0;
        end
    endtask

    task automatic expect_completion(
        input logic [5:0] context_id,
        input logic [WG_WIDTH-1:0] workgroup_id,
        input logic [63:0] submission_id,
        input logic [63:0] packet_position,
        input logic [63:0] incarnation_id,
        input logic [2:0] status,
        input logic [4:0] failure_code);
        integer guard;
        begin
            guard = 0;
            while (!completion_valid && guard < 40) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            if (!completion_valid || completion_context !== context_id
                || completion_process !== (64'h1000000000000000 | context_id)
                || completion_address_space !== (64'h2000000000000000 | context_id)
                || completion_workgroup !== workgroup_id
                || completion_submission !== submission_id
                || completion_position !== packet_position
                || completion_incarnation !== incarnation_id
                || completion_status !== status || completion_failure !== failure_code)
                $fatal(1, "final command completion identity/status mismatch: valid=%b context=%0d workgroup=%0d status=%0d failure=%0d",
                    completion_valid, completion_context, completion_workgroup,
                    completion_status, completion_failure);
            repeat (2) begin
                @(posedge clk); #1;
                if (!completion_valid || completion_context !== context_id
                    || completion_workgroup !== workgroup_id
                    || completion_submission !== submission_id
                    || completion_position !== packet_position
                    || completion_incarnation !== incarnation_id
                    || completion_status !== status || completion_failure !== failure_code)
                    $fatal(1, "final command completion changed under backpressure");
            end
            if (queue_drained_mask[context_id])
                $fatal(1, "queue reported drained while its final completion was backpressured");
        end
    endtask

    task automatic acknowledge_completion(input logic [5:0] context_id);
        begin
            @(negedge clk); completion_ready = 1'b1;
            @(posedge clk); #1;
            @(negedge clk); completion_ready = 1'b0; #1;
            if (!queue_drained_mask[context_id])
                $fatal(1, "queue did not drain after final completion acknowledgement");
        end
    endtask

    initial begin : run_test
        reset_n = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk); reset_n = 1'b1;

        // Admission is only an intermediate state. A matched final-wave
        // retirement emits completion, and an unrelated stale ID cannot do so.
        submit_command(6'd1, 8'd1, 64'd101, 64'd0, 64'd11);
        send_admission(6'd1, 8'd1, 64'd101, 64'd0, 64'd11, 3'd0, 5'd0);
        repeat (2) @(posedge clk);
        if (completion_valid || queue_drained_mask[1])
            $fatal(1, "admitted command completed before workgroup retirement");
        send_retirement(8'hfe);
        if (completion_valid)
            $fatal(1, "unmatched retirement completed an unrelated command");
        send_retirement(8'd1);
        expect_completion(6'd1, 8'd1, 64'd101, 64'd0, 64'd11, 3'd0, 5'd0);
        acknowledge_completion(6'd1);

        // Permanent admission errors are terminal command outcomes.
        submit_command(6'd2, 8'd8, 64'd202, 64'd52, 64'd12);
        send_admission(6'd2, 8'd8, 64'd202, 64'd52, 64'd12, 3'd1, 5'd6);
        expect_completion(6'd2, 8'd8, 64'd202, 64'd52, 64'd12, 3'd1, 5'd6);
        acknowledge_completion(6'd2);

        // A queue reset cancels a pending descriptor without pretending it was admitted.
        submit_command(6'd3, 8'd9, 64'd303, 64'd104, 64'd13);
        cancelled_queue_mask[3] = 1'b1;
        send_admission(6'd3, 8'd9, 64'd303, 64'd104, 64'd13, 3'd4, 5'd0);
        expect_completion(6'd3, 8'd9, 64'd303, 64'd104, 64'd13, 3'd4, 5'd0);
        acknowledge_completion(6'd3);
        cancelled_queue_mask[3] = 1'b0;

        // A command admitted just as reset arrives is aborted, but its final
        // cancellation waits for the actual resource-retirement event.
        submit_command(6'd0, 8'd10, 64'd404, 64'd208, 64'd14);
        cancelled_queue_mask[0] = 1'b1;
        send_admission(6'd0, 8'd10, 64'd404, 64'd208, 64'd14, 3'd0, 5'd0);
        if (!abort_valid || abort_workgroup !== 8'd10)
            $fatal(1, "resident queue cancellation did not request workgroup abort");
        repeat (2) begin
            @(posedge clk); #1;
            if (!abort_valid || abort_workgroup !== 8'd10)
                $fatal(1, "workgroup abort request changed under backpressure");
        end
        @(negedge clk); abort_ready = 1'b1;
        @(posedge clk); #1;
        @(negedge clk); abort_ready = 1'b0;
        if (completion_valid)
            $fatal(1, "resident cancellation completed before quiescent workgroup retirement");
        send_retirement(8'd10);
        expect_completion(6'd0, 8'd10, 64'd404, 64'd208, 64'd14, 3'd4, 5'd0);
        acknowledge_completion(6'd0);
        cancelled_queue_mask[0] = 1'b0;

        // Fault and unsupported-command outcomes keep their scheduler meaning.
        submit_command(6'd1, 8'd11, 64'd105, 64'd260, 64'd15);
        send_admission(6'd1, 8'd11, 64'd105, 64'd260, 64'd15, 3'd2, 5'd0);
        expect_completion(6'd1, 8'd11, 64'd105, 64'd260, 64'd15, 3'd2, 5'd0);
        acknowledge_completion(6'd1);
        submit_command(6'd2, 8'd12, 64'd206, 64'd312, 64'd16);
        send_admission(6'd2, 8'd12, 64'd206, 64'd312, 64'd16, 3'd3, 5'd0);
        expect_completion(6'd2, 8'd12, 64'd206, 64'd312, 64'd16, 3'd3, 5'd0);
        acknowledge_completion(6'd2);

        if (tracked_count != 0 || queue_drained_mask != {CONTEXTS{1'b1}})
            $fatal(1, "lifecycle manager leaked command state after all acknowledgements");
        $display("[pass] RTL command lifecycle retirement, cancellation, identity, drain, and backpressure passed.");
        $finish;
    end
endmodule
