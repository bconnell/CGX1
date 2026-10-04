# CGX1 RTL Command Packet Ingress Implementation Plan

> **Implementation note:** Follow the checkable steps in order; use the RTL simulation gate after each interface change.

**Goal:** Parse the provisional workgroup-dispatch byte packet in RTL and preserve its queue identity through the existing CU dispatcher admission result.

**Architecture:** A single streaming parser captures queue metadata at packet start, validates the bounded little-endian packet without buffering arbitrary payloads, then either holds a decoded descriptor for the dispatcher or emits a parser error completion. The CU dispatcher stores submission token, packet byte position, and queue incarnation alongside each descriptor and returns them with its existing admission result.

**Tech Stack:** SystemVerilog, Icarus Verilog, `scripts/validate_rtl.sh`, CMake/CTest for unchanged executable reference behavior.

**Spec:** [2026-10-03-cgx1-rtl-command-runtime-design.md](../specs/2026-10-03-cgx1-rtl-command-runtime-design.md)

## Global Constraints

- Preserve the exact provisional v1 packet layout in the design spec; do not freeze it as a public ABI.
- Use ready/valid handshakes and capture command metadata only on the accepted first byte.
- Respect complete-workgroup dispatch: never truncate a packet's wave list to fit resident slots.
- Keep parser errors, CU admission results, and final workgroup completion semantically distinct.
- Bound parser packet length; the default is 4,096 bytes.
- Do not implement the I/O-die queue manager, hardware per-context rings, graphics packets, compiler/runtime submission, or final-retirement command tracking in this slice.

## Review Focus

- Fragmented headers/payloads and stalls must neither lose accepted bytes nor use changed live metadata; test with sideband changes after the first accepted byte.
- Framed malformed/unsupported commands must consume exactly the declared length and allow the next packet; test malformed flags and unknown opcode followed by a valid packet.
- Untrustworthy lengths must fault only the captured queue and remain blocked until its reset; test bad magic, undersized, over-limit, and unaligned lengths.
- Workgroup wave counts above resident capacity must be terminally rejected after full record validation, with no truncated descriptor; test maximum-fit and over-capacity packets.
- Correlation must remain exact across dispatcher backpressure and completion; test duplicate tokens at distinct packet positions/incarnations.

---

### Task 1: Streaming RTL packet ingress and CU admission correlation

**Files:**
- Modify: `source/rtl/cgx1_compute_workgroup_dispatch_scheduler.sv`
- Create: `source/rtl/cgx1_compute_workgroup_command_packet_parser.sv`
- Create: `source/rtl/tests/cgx1_compute_workgroup_command_packet_parser_tb.sv`
- Create: `source/rtl/tests/cgx1_compute_workgroup_command_runtime_tb.sv`
- Modify: `source/rtl/tests/cgx1_compute_workgroup_dispatch_scheduler_tb.sv`
- Modify: `source/rtl/tests/cgx1_compute_workgroup_dispatch_integration_tb.sv`
- Modify: `scripts/validate_rtl.sh`
- Modify: `docs/SOFTWARE_STACK.md`, `docs/SCHEDULING_PREEMPTION.md`, `docs/STATUS.md`, `docs/VALIDATION.md`, `design/cgx1_completeness_matrix.json`

**Interfaces:**
- Parser consumes `command_valid/command_ready/command_data[7:0]`, `command_start`, and `command_queue_context_id[5:0]`, `command_process_id[63:0]`, `command_address_space_id[63:0]`, `command_priority[2:0]`, `command_queue_incarnation_id[63:0]`, and `command_packet_byte_position[63:0]` on the accepted first byte; `queue_reset_valid/queue_reset_context_id[5:0]` clears one queue's parser fault and partial packet.
- Parser produces a stable `submit_valid/submit_ready` descriptor with `submit_queue_context_id[5:0]`, `submit_process_id[63:0]`, `submit_address_space_id[63:0]`, `submit_priority[2:0]`, `submit_workgroup_id[WORKGROUP_ID_WIDTH-1:0]`, `submit_submission_id[63:0]`, `submit_packet_byte_position[63:0]`, `submit_queue_incarnation_id[63:0]`, `submit_start_pc[VIRTUAL_ADDRESS_WIDTH-1:0]`, `submit_wave_count[WAVE_COUNT_WIDTH-1:0]`, `submit_initial_live_lane_mask_flat[RESIDENT_WAVE_SLOTS*32-1:0]`, `submit_vgpr_register_counts_flat[RESIDENT_WAVE_SLOTS*9-1:0]`, `submit_scalar_state_units_per_wave[15:0]`, `submit_shared_local_bytes[31:0]`, and `submit_other_workgroup_state_units[15:0]`. `parser_completion_valid/parser_completion_ready` carries parser errors with context/process/address identity, optional token, packet position, incarnation, workgroup ID, 3-bit status, and 5-bit failure; `queue_faulted_mask[63:0]` reports queue faults.
- CU scheduler adds `submit_submission_id`, `submit_packet_byte_position`, and `submit_queue_incarnation_id`; each is stored in the pending entry, presented as `dispatch_submission_id/dispatch_packet_byte_position/dispatch_queue_incarnation_id`, and returned on `completion_submission_id/completion_packet_byte_position/completion_queue_incarnation_id` with the existing admission result.

- [ ] **Step 1: Add failing parser and dispatcher identity testbenches.** Assert the golden little-endian bytes, fragmented acceptance, metadata capture, valid descriptor output, malformed/unsupported framing behavior, queue reset, over-capacity rejection, stable output under backpressure, and identity retention through CU admission.
- [ ] **Step 2: Add parser and scheduler tests to the RTL gate and run them red.** Compile the parser bench with `iverilog -g2012 -Wall -s cgx1_compute_workgroup_command_packet_parser_tb -o build/rtl/cgx1_compute_workgroup_command_packet_parser_tb.vvp source/rtl/cgx1_compute_workgroup_command_packet_parser.sv source/rtl/tests/cgx1_compute_workgroup_command_packet_parser_tb.sv`, then run `vvp build/rtl/cgx1_compute_workgroup_command_packet_parser_tb.vvp`. Compile the integrated bench with `iverilog -g2012 -Wall -s cgx1_compute_workgroup_command_runtime_tb -o build/rtl/cgx1_compute_workgroup_command_runtime_tb.vvp source/rtl/cgx1_compute_workgroup_command_packet_parser.sv source/rtl/cgx1_compute_workgroup_dispatch_scheduler.sv source/rtl/tests/cgx1_compute_workgroup_command_runtime_tb.sv`, then run `vvp build/rtl/cgx1_compute_workgroup_command_runtime_tb.vvp`. New interface/identity assertions must fail before implementation.
- [ ] **Step 3: Implement the bounded streaming parser.** Decode fields little-endian by byte position; keep only resident-slot wave records, validate every framed wave record, consume trusted frame boundaries, and hold dispatch/error outputs until handshake.
- [ ] **Step 4: Extend CU dispatcher correlation.** Capture submission token, packet byte position, and queue-incarnation ID on accepted submit; expose stable selected dispatch metadata and copy it to the existing admission result.
- [ ] **Step 5: Run focused parser and integrated parser-to-dispatcher RTL tests.** Expected: all directed parser, backpressure, reset, and correlation cases pass.
- [ ] **Step 6: Run `bash scripts/validate_rtl.sh`.** Expected: all existing and new Icarus simulations pass.
- [ ] **Step 7: Run the full WSL CMake/CTest suite, `scripts/validate_windows.ps1`, `git diff --check`, JSON validation, and matrix fingerprint verification.** Record the Windows CMake PATH limitation if it persists.
- [ ] **Step 8: Update the SDD progress ledger and commit the slice locally.** Do not push or claim hosted/physical evidence.
