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
- Preserve the packet's 32-bit other-workgroup-state demand through parser, dispatcher, admission transaction, and barrier resource accounting.

## Review Focus

- Fragmented headers/payloads and stalls must neither lose accepted bytes nor use changed live metadata; test with sideband changes after the first accepted byte.
- Exercise deterministic inter-byte gaps while consuming accepted packet bytes.
- Framed malformed/unsupported commands must consume exactly the declared length and allow the next packet; test malformed flags and unknown opcode followed by a valid packet.
- Untrustworthy lengths must fault only the captured parser context and remain blocked until parser recovery; test bad magic, undersized, over-limit, and unaligned lengths. Parser recovery abandons partial framing only and leaves complete parser-output or dispatcher-owned descriptors intact.
- Reject entry PCs that exceed the configured virtual-address width after byte assembly; run the same parser bench at both the 57-bit architectural limit and a narrower 48-bit configuration.
- Workgroup wave counts above resident capacity must be terminally rejected after full record validation, with no truncated descriptor; test maximum-fit and over-capacity packets.
- Correlation must remain exact across dispatcher backpressure and completion; test duplicate tokens at distinct packet positions/incarnations.

---

### Task 1: Streaming RTL packet ingress and CU admission correlation

**Files:**
- Modify: `source/rtl/cgx1_compute_workgroup_dispatch_scheduler.sv`
- Modify: `source/rtl/cgx1_compute_workgroup_execution_frontend.sv`, `source/rtl/cgx1_workgroup_residency_barrier.sv`
- Create: `source/rtl/cgx1_compute_workgroup_command_packet_parser.sv`
- Create: `source/rtl/tests/cgx1_compute_workgroup_command_packet_parser_tb.sv`
- Create: `source/rtl/tests/cgx1_compute_workgroup_command_runtime_tb.sv`
- Modify: `source/rtl/tests/cgx1_compute_workgroup_dispatch_scheduler_tb.sv`
- Modify: `source/rtl/tests/cgx1_compute_workgroup_dispatch_integration_tb.sv`
- Modify: `source/rtl/tests/cgx1_compute_workgroup_execution_frontend_tb.sv`, `source/rtl/tests/cgx1_workgroup_residency_barrier_tb.sv`
- Modify: `scripts/validate_rtl.sh`
- Modify: `docs/SOFTWARE_STACK.md`, `docs/SCHEDULING_PREEMPTION.md`, `docs/STATUS.md`, `docs/VALIDATION.md`, `design/cgx1_completeness_matrix.json`

**Interfaces:**
- Parser consumes `command_valid/command_ready/command_data[7:0]`, `command_start`, and `command_queue_context_id[5:0]`, `command_process_id[63:0]`, `command_address_space_id[63:0]`, `command_priority[2:0]`, `command_queue_incarnation_id[63:0]`, and `command_packet_byte_position[63:0]` on the accepted first byte; `parser_recovery_valid/parser_recovery_context_id[5:0]` clears parser fault state and abandons a partial packet. It preserves complete descriptors already held by the parser or accepted by the CU dispatcher; it is not full runtime queue cancellation.
- Parser produces a stable `submit_valid/submit_ready` descriptor with `submit_queue_context_id[5:0]`, `submit_process_id[63:0]`, `submit_address_space_id[63:0]`, `submit_priority[2:0]`, `submit_workgroup_id[WORKGROUP_ID_WIDTH-1:0]`, `submit_submission_id[63:0]`, `submit_packet_byte_position[63:0]`, `submit_queue_incarnation_id[63:0]`, `submit_start_pc[VIRTUAL_ADDRESS_WIDTH-1:0]`, `submit_wave_count[WAVE_COUNT_WIDTH-1:0]`, `submit_initial_live_lane_mask_flat[RESIDENT_WAVE_SLOTS*32-1:0]`, `submit_vgpr_register_counts_flat[RESIDENT_WAVE_SLOTS*9-1:0]`, `submit_scalar_state_units_per_wave[15:0]`, `submit_shared_local_bytes[31:0]`, and `submit_other_workgroup_state_units[31:0]`. The 32-bit resource field stays full width through frontend admission and resident barrier accounting. `parser_completion_valid/parser_completion_ready` carries parser errors with context/process/address identity, optional token, packet position, incarnation, workgroup ID, 3-bit status, and 5-bit failure; `queue_faulted_mask[63:0]` reports queue faults.
- CU scheduler adds `submit_submission_id`, `submit_packet_byte_position`, and `submit_queue_incarnation_id`; each is stored in the pending entry, presented as `dispatch_submission_id/dispatch_packet_byte_position/dispatch_queue_incarnation_id`, and returned on `completion_submission_id/completion_packet_byte_position/completion_queue_incarnation_id` with the existing admission result.

- [x] **Step 1: Add failing parser and dispatcher identity testbenches.** Assert the golden little-endian bytes, fragmented ingress, metadata capture, valid descriptor output, malformed/unsupported framing behavior, parser recovery preserving completed descriptors, over-capacity rejection, stable output under backpressure, and identity retention through CU admission.
- [x] **Step 2: Add parser and scheduler tests to the RTL gate and run them red.** The parser test first failed to elaborate because the module was absent; the correlation and full-width resource tests also failed on their intended missing behavior.
- [x] **Step 3: Implement the bounded streaming parser.** Decode fields little-endian by byte position; keep only resident-slot wave records, validate every framed wave record, consume trusted frame boundaries, and hold dispatch/error outputs until handshake.
- [x] **Step 4: Extend CU dispatcher correlation and resource-width preservation.** Capture submission token, packet byte position, and queue-incarnation ID on accepted submit; expose stable selected dispatch metadata and copy it to the existing admission result. Preserve the packet's full 32-bit other-workgroup-state field through pending storage, frontend admission, and barrier accounting.
- [x] **Step 5: Run focused parser and integrated parser-to-dispatcher RTL tests.** Directed parser tests passed at 57-bit and 48-bit PC widths; parser-local recovery preserved the complete CU-dispatcher-owned descriptor, and identity/resource-width cases passed.
- [x] **Step 6: Run `bash scripts/validate_rtl.sh`.** The full Icarus 12.0 gate passed on the current source and testbench candidate, including both parser address widths.
- [x] **Step 7: Run the full WSL CMake/CTest suite, `scripts/validate_windows.ps1`, `git diff --check`, JSON validation, and matrix fingerprint verification.** CMake build and CTest passed 26/26; the Windows wrapper passed hygiene, integrity, design consistency, negative controls, and Markdown-link checks before stopping at CMake because `cmake.exe` is unavailable on Windows PATH. JSON and the exact-candidate matrix fingerprint were verified after the final documentation updates.
- [x] **Step 8: Update the SDD progress ledger and commit the slice locally.** Created local checkpoint `a52880a`; nothing was pushed and no hosted/physical evidence is claimed. Continue with the dependency-aware `rtl_command_queue_runtime` goal.
