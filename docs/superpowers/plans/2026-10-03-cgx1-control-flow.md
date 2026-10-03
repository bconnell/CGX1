# CGX1 Decoded Control-Flow Implementation Plan

**Goal:** Add a decoded per-wave control-flow authority and integrate its live/active lane masks with the existing workgroup execution frontend.

**Architecture:** A project-native C++ reference defines branch, explicit-join, call/return, structured-loop, lane-termination, and bounded-stack behavior. A parameterized RTL unit keeps that state per resident wave, advances PCs only on accepted decoded work, and feeds active masks into vector/memory issue and reconvergence checks into matrix/barrier issue. Dispatch initializes the PC and live lanes; wave faults and termination use the existing workgroup terminal path.

**Tech Stack:** C++20, CMake/CTest, SystemVerilog, Icarus Verilog, existing PowerShell repository-integrity gates.

**Spec:** `docs/CONTROL_FLOW.md`

## Global Constraints

- The control boundary starts after decode; do not assign opcodes, infer instruction length, add fetch, or claim compiler lowering.
- PCs are 57-bit virtual addresses aligned to four bytes.
- Per-wave `active_mask` is always a subset of `live_mask`; terminated lanes are never reactivated.
- The combined LIFO control stack and the separate call stack are bounded fixed per-resident-wave state. The default control and call depths are both 8; overflow or malformed control state faults that wave.
- The workgroup remains completely resident through divergence and barriers; barrier arrival is allowed only after the wave has reconverged (`active_mask == live_mask`).
- Baseline compute preemption remains at workgroup boundaries. Do not add wave save/restore or wave swapping.
- Do not claim cache, MMU, HBM, timing, area, power, synthesis, or physical implementation evidence from software/RTL simulation.

## Review Focus

- Terminated lanes cannot be restored by a deferred branch, a loop exit, or a later join; assert exact live/active masks after nested termination.
- A path reaches a join only with branch-entry call/loop depths restored; malformed paths fault rather than corrupting another frame.
- Loop frames retain their call-depth checkpoint through empty-path unwind; loop tests/backedges and returns cannot escape an active control checkpoint.
- Barrier reconvergence uses workgroup-local-to-resident-slot mapping owned by the residency barrier; an unrelated workgroup's control mask cannot permit or block arrival.
- Invalid or unaligned PCs, masks outside the active set, and stack overflow/underflow terminate the affected wave through the normal barrier/resource lifecycle.
- A divergent wave cannot arrive at a workgroup barrier, while other resident waves continue to issue and memory-waiting waves remain live participants.
- The sequential PC changes only when the associated decoded instruction is accepted; downstream backpressure cannot advance the PC early.

---

### Task 1: Executable wave-control reference

**Files:**
- Create: `source/control/cgx1_wave_control.hpp`
- Create: `source/control/tests.cpp`
- Create: `source/control/CMakeLists.txt`
- Modify: root `CMakeLists.txt`

**Interfaces:**
- `WaveControlState` stores `pc`, `liveMask`, `activeMask`, terminal/fault status, one combined branch/loop control stack, and a separate call stack.
- `ApplyControlEvent(state, event, limits)` consumes one decoded event and returns an accepted transition, next state, or terminal fault. `AdvanceAcceptedInstruction(state, sequentialPc)` advances only after execution acceptance.
- Default RTL/reference capacities: control depth 8 and call depth 8; limits are configurable for boundary tests.

- [x] **Step 1: Write failing reference tests** named `TestUniformBranch`, `TestDivergentBranchJoin`, `TestNestedJoinAndTermination`, `TestCallReturn`, `TestStaggeredLoopExit`, `TestLoopUnwindRestoresCallDepth`, `TestMalformedOuterJoinAndProtectedReturns`, `TestInvalidControlFaults`, and `TestSeededTransitionInvariants`. Assert literal PCs and lane masks, including that lane termination never resurrects.
- [x] **Step 2: Run `cgx1_control_flow_tests` and confirm the new tests fail because the reference API is absent.**
- [x] **Step 3: Implement the minimal reference state and event transitions in `cgx1_wave_control.hpp`.** Use explicit join PCs, taken-first deterministic simulation, call-depth checkpoints at branch splits, and fault status for invalid PCs/masks or unbalanced stacks.
- [x] **Step 4: Run `cgx1_control_flow_tests`, then the complete CTest suite.**

### Task 2: Standalone RTL control state

**Files:**
- Create: `source/rtl/cgx1_wave_control_flow.sv`
- Create: `source/rtl/tests/cgx1_wave_control_flow_tb.sv`
- Modify: `source/rtl/tests/cgx1_workgroup_residency_barrier_tb.sv`
- Modify: `scripts/validate_rtl.sh`

**Interfaces:**
- Initialization supplies a per-slot 57-bit start PC and 32-bit live mask.
- Per-slot accepted sequential-PC updates accompany accepted normal instructions; a decoded control-event channel supplies branch masks/target/fallthrough/join PCs, call/return PCs, loop PCs/continue masks, or lane termination.
- Outputs include per-slot PC/live/active masks, event ready/accepted, per-wave terminal/fault pulses and fault code, plus `reconverged_mask`.

- [x] **Step 1: Add directed RTL checks** for uniform and nested valid joins, divergent taken/fallthrough execution, malformed outer joins hidden by inner branch/loop state, call/return checkpoint protection, loop call-depth unwind, staggered loop exits, lane termination, invalid PC/mask, call/control stack overflow and underflow, and reset with nonempty stacks.
- [x] **Step 2: Run the new testbench against a compile-only interface stub and confirm behavioral checks fail.**
- [x] **Step 3: Implement fixed per-wave stacks and the same transitions as the C++ reference.** Hold state stable when an event is not accepted.
- [x] **Step 4: Run the standalone testbench and compare directed expected states with the reference.** Add a fixed-seed randomized trace and invariant checks for `active ⊆ live`, aligned PC, bounded depths, and no terminated-lane resurrection. Fresh standalone RTL execution passed after the review fixes.

### Task 3: Workgroup frontend integration

**Files:**
- Modify: `source/rtl/cgx1_compute_workgroup_execution_frontend.sv`
- Modify: `source/rtl/cgx1_workgroup_residency_barrier.sv`
- Modify: `source/rtl/tests/cgx1_compute_workgroup_execution_frontend_tb.sv`
- Modify: `scripts/validate_rtl.sh`

**Interfaces:**
- Dispatch supplies one start PC and a live mask for each dispatch wave; accepted commit initializes the actual reserved slots.
- Existing matrix/vector/memory acceptance advances the associated wave PC from decoder-supplied sequential-PC input. Control events are serialized against same-wave execution and require a resident, issuable wave.
- Vector and LSU lane masks are intersected with control active/live masks. Matrix issue and workgroup barrier arrival require `active_mask == live_mask`; the barrier applies reconvergence through its committed local-wave-to-slot map.
- Control fault or empty-live termination enters the existing wave terminal path. Stacks clear only on reset or accepted resource release; memory/barrier residency remains owned by existing authorities.

- [x] **Step 1: Add failing integration cases** for nonzero dispatch PC/live masks, accepted PC updates and memory-wait backpressure, divergent vector destination writes and LSU masks, barrier rejection before reconvergence, sibling-wave progress, control fault retirement, workgroup abort, slot reuse, and two-workgroup nonzero-slot barrier mapping.
- [x] **Step 2: Confirm pre-fix failure evidence.** The reference regression failed at the stale loop call-stack depth before the fix; the read-only review traced the barrier false-allow/false-block to comparing local-wave bits with physical-slot bits. Both mapped-slot regressions pass after moving reconvergence eligibility into the barrier authority.
- [x] **Step 3: Connect initialization, accepted-PC updates, issue masks, barrier eligibility, and the control terminal path.** Use one control event at a time and the existing terminal/resource authorities.
- [x] **Step 4: Run the integrated frontend test and all focused control-flow tests.** Fresh CMake/CTest passed 24/24; the standalone control-flow and integrated frontend RTL benches passed directly with Icarus 12.0.

### Task 4: Contract, evidence, and checkpoint

**Files:**
- Modify: `docs/ISA.md`
- Create: `docs/CONTROL_FLOW.md`
- Modify: `docs/README.md`
- Modify: `docs/VALIDATION.md`
- Modify: `docs/STATUS.md`
- Modify: `source/rtl/README.md`
- Modify: `design/cgx1_completeness_matrix.json`

- [x] **Step 1: Document only implemented post-decode semantics and keep opcode/fetch/compiler/runtime and physical claims open.**
- [x] **Step 2: Set completeness evidence fields from actual fresh C++/RTL/integration results; keep CU/GPU/toolchain and physical states open.**
- [x] **Step 3: Run CMake build and CTest, full `scripts/validate_rtl.sh`, design consistency, repository integrity/hygiene, Markdown links, and the Windows negative controls.** The WSL CMake build and CTest passed 24/24; the full RTL script passed with Icarus 12.0 after allowing the resident-wave VGPR elaboration to finish. Windows public hygiene/integrity/design consistency and all negative controls, plus Markdown links, passed. The Windows wrapper stopped at native CMake discovery because `cmake.exe` is unavailable on PATH; native Windows CMake remains unverified.
- [x] **Step 4: Review the exact diff and `git diff --check`, stage only this control-flow slice, and create one coherent local checkpoint.** Remote publication is a separate boundary and is not part of this local continuation.

## Self-review

- Spec coverage: the C++ model and RTL cover decoded control semantics; the workgroup integration covers residency, issue masks, barriers, terminal retirement, and reuse; metadata remains evidence-calibrated.
- Step scan: every task starts with a behavioral regression, confirms the red state, implements one cohesive boundary, and reruns its focused gate.
- Type consistency: both models use 57-bit PCs, 32-bit masks, control-stack depth 8, call-stack depth 8, and per-slot flattened RTL buses.
- Review focus: nested joins and frame-depth violations fault in both reference and RTL tests; barrier reconvergence is tested across two workgroups mapped to nonzero physical slots.
- Proportion: no fetch, decoder, opcode, compiler, queue, runtime, wave swapping, or physical backend is included.

## Execution notes

- Ruling: keep work in the user-required canonical checkout rather than create a separate worktree — the repository instructions explicitly require the existing local checkout — cost if wrong: concurrent edits would lack checkout isolation; the full pre-existing dirty state was inspected and preserved.
- Ruling: make a local commit without pushing — the active continuation authorizes a local checkpoint, while remote publication is a distinct external action — cost if wrong: hosted CI will not run for this candidate until publication is authorized.
- Power evidence correction: the earlier P1/P2 fixed-count report is preserved in `docs/VALIDATION.md` as historical context, but current `cgx1_top.sv` connects the real per-tile manager and the top-level test verifies arbitrary subsets. Do not recreate or duplicate that manager; the full CU scheduler consumer and physical tile-control sequence remain open.
- Repository-hygiene correction: the Windows public-wording check rejected two phrases in the implementation-plan header. The header was removed; the complete text gates passed on rerun. The wrapper then stopped at `cmake.exe` discovery, and the WSL CMake/CTest and RTL gates supplied build and execution proof.
- Prior candidate validation (before reviewer remediation): `cmake --build build -j2`, CTest 24/24, and `bash scripts/validate_rtl.sh` passed under Ubuntu WSL with GCC and Icarus 12.0. Windows hygiene, integrity, design consistency, negative controls, and local Markdown links passed; the Windows wrapper could not start native CMake because `cmake.exe` is unavailable on PATH. Those results do not cover the reviewer fixes.
- Reviewer remediation: fixed the local-wave/resident-slot reconvergence mismatch inside the barrier authority; saved and restored loop call depth on termination unwind; checked loop backedges/tests and protected caller return depth; faulted on an outer join reached with an incompatible inner frame. Added valid/malformed nested joins, stack-boundary, randomized trace, accepted-PC, divergent-write, memory-wait, and nonzero-slot regressions. Fresh targeted RTL and all 24 CTest tests passed. Full `scripts/validate_rtl.sh` did not complete on this candidate; the exact interruption is recorded above and in `docs/VALIDATION.md`.
