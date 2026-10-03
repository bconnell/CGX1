# Authoritative Workgroup Residency Implementation Plan

**Goal:** Make the existing pooled VGPR allocator the single physical allocation authority for complete workgroups, and keep those reservations coherent with issue, barriers, quiescence, retirement, fault, kill, reset, and reuse.

**Architecture:** Refactor the C++ workgroup reference to compose `ResidentWaveVgprPool` and `PooledVgprStorage`; derive row allocation and slot availability from those objects. In RTL, the workgroup controller will reserve each wave through the allocator already inside `cgx1_compute_int8_vector_execution_frontend`, wait for allocator sanitization, activate the complete set, then commit the group to barrier state. A failed later reservation rolls back every earlier reserved wave before returning failure. The barrier block will own only group membership and barrier generations; both matrix and vector request masks will derive eligibility from committed live waves and barrier waits. Terminal waves stop issuing immediately, leave the barrier participant set, and retain allocator ownership until the real matrix/vector path is quiescent and release is accepted.

**Tech Stack:** C++20 executable reference, `ResidentWaveVgprPool`/`PooledVgprStorage`, SystemVerilog 2012, Icarus Verilog, CMake/CTest, repository PowerShell consistency and integrity gates.

**Spec:** User instruction “NEXT GOAL — MAKE WORKGROUP RESIDENCY AUTHORITATIVE” and the current [scheduling and preemption contract](../../SCHEDULING_PREEMPTION.md).

## Global Constraints

- Work only in the existing local checkout of the `bconnell/CGX1` repository on its active development branch.
- The pooled resident-wave VGPR allocator is the only authority for VGPR rows and allocation state.
- Admission is transactional: either every required wave allocation becomes active before group commit, or every partial reservation is released before failure is reported.
- The workgroup is not scheduler-visible before commit; barrier arrivals use its admitted, surviving wave set.
- Exact architectural VGPR counts remain bounded at 256 per wave; physical row rounding does not widen that namespace.
- Shared/local-memory bytes remain explicitly provisional accounting because no physical shared/local-memory subsystem is present.
- Preserve workgroup-boundary mandatory compute preemption; implement no wave swapping or wave-level save/restore.
- Tests may claim executable and RTL behavior only; make no synthesis, timing, area, power, memory-macro, or silicon claim.
- Keep the existing matrix/vector, pooled-VGPR, scheduler, and barrier tests green.
- The `d8be39e` hosted validation was explicitly dispatched; do not poll it or publish this dependent integration while that publication boundary is unresolved.

## Review Focus

- A late per-wave allocator refusal after earlier reservations must roll all rows and slots back before failure is visible. Pin with a fragmented-capacity integration test that compares allocator maps before and after.
- Different per-wave VGPR counts, including counts not divisible by eight, must reserve rounded physical rows while preserving each exact architectural bound. Pin with a `[9, 17]`-register workgroup and rejected register 17 access in the first wave.
- A fault or kill during vector or matrix execution must stop new issue immediately and keep its active allocation until the real execution busy signal clears. Pin both paths with wave-local busy and allocator-state assertions.
- Retirement of one participant before a later barrier must update only the surviving barrier mask; a stalled surviving wave remains required. Pin with a retired participant and an independently dependency-stalled live sibling.
- Reset during partial reservation, barrier wait, and active execution must clear allocator and controller ownership together. Pin each reset stage and immediately reuse the freed physical rows.

---

### Task 1: Make the executable scheduler use the pooled allocator

**Files:**
- Modify: `source/model/workgroup_scheduler.hpp`
- Modify: `source/model/workgroup_scheduler_tests.cpp`
- Modify: `source/matrix/cgx1_matrix_vgpr_pool.hpp` to add coordinated allocator/storage reset
- Modify: `source/matrix/vgpr_pool_tests.cpp`
- Modify: `source/model/CMakeLists.txt` only if the existing target needs new dependencies
- Reuse: `source/matrix/cgx1_matrix_vgpr_pool.hpp`

**Interfaces:**
- `WorkgroupDemand` keeps `waveCount` and gains `std::vector<std::uint32_t> vgprRegisterCountsByWave`; an empty vector means the existing uniform `vgprsPerWave` value applies to all waves.
- `ComputeUnitWorkgroupScheduler` owns one `cgx1::matrix::ResidentWaveVgprPool` and one `cgx1::matrix::PooledVgprStorage`; `OccupiedVgprRows()` and slot-free checks query the pool.
- Add `AllocationForSlot(slot)`, `AllocationForWave(workgroupId, waveIndex)`, `BeginWaveExecution(id, wave)`, `CompleteWaveExecution(id, wave)`, and `ReadVgpr(id, wave, register)` so tests can observe real allocation state, quiescence, and sanitized reuse.
- Add `Reset()` to the real reference pool and storage so CU recovery clears allocator ownership and initialization metadata together.
- Add a wave-terminal operation that removes the wave from issue/barrier participation immediately, but releases its pooled allocation only after its in-flight execution is complete.

- [x] **Step 1: Add failing tests for authoritative allocation and rollback**

Add `TestTransactionalPooledAdmission` with a two-wave demand of 9 and 17 VGPRs. Assert allocator states become `Active`, row counts round to 2 and 3, architectural counts remain 9 and 17, a register outside the 9-register namespace is rejected, and a failed later reservation leaves every slot allocation byte-for-byte unchanged.

```cpp
auto demand = Demand(50U, 2U, 16U);
demand.vgprRegisterCountsByWave = {9U, 17U};
CHECK(scheduler.Admit(demand) == AdmissionFailure::None);
CHECK(scheduler.AllocationForWave(50U, 0U).physicalRowCount == 2U);
CHECK(scheduler.AllocationForWave(50U, 0U).architecturalRegisterCount == 9U);
CHECK(scheduler.AllocationForWave(50U, 1U).physicalRowCount == 3U);
```

- [x] **Step 2: Run the focused CTest before implementation**

Run: `ctest --test-dir build --output-on-failure -R cgx1_workgroup_scheduler_checks`

Expected: the new assertions fail because the scheduler does not yet query `ResidentWaveVgprPool`.

- [x] **Step 3: Replace the scheduler's VGPR row bitmap with the actual pool**

For each candidate wave, choose a slot only when `pool.Allocation(slot).state == VgprAllocationState::Free`; call `Reserve(slot, exactRegisterCount)` for every wave; on any refusal call `Release` on every earlier reservation and classify the failure using total free rows versus contiguous placement. After every reservation succeeds, call `PooledVgprStorage::InvalidateReservedAllocation` and then `Activate` for each slot. Publish workgroup and wave-owner metadata only after every activation succeeds. Derive occupied rows and exact allocation snapshots from the pool.

- [x] **Step 4: Add quiescent retirement and run the focused CTest**

Cover terminal-before-barrier, faulted waiter, retirement while execution is busy, barrier release after the actual surviving set arrives, workgroup-local resource retention until all terminal waves release, and allocation reuse with uninitialized data after reassignment. Run: `cmake --build build --target cgx1_workgroup_scheduler_tests -j2 && ctest --test-dir build --output-on-failure -R cgx1_workgroup_scheduler_checks`.

- [x] **Step 5: Run all executable tests**

Run: `cmake --build build -j2 && ctest --test-dir build --output-on-failure`.

Expected: all current CTest targets pass, including the randomized scheduler sequence with allocator invariants checked after each transition.

### Task 2: Export actual allocator state and make RTL admission transactional

**Files:**
- Modify: `source/rtl/cgx1_pooled_vgpr_execution_subsystem.sv`
- Modify: `source/rtl/cgx1_compute_int8_vector_execution_frontend.sv`
- Create: `source/rtl/cgx1_compute_workgroup_execution_frontend.sv`
- Modify: `source/rtl/tests/cgx1_compute_int8_vector_execution_frontend_tb.sv` only to connect new read-only status outputs
- Create: `source/rtl/tests/cgx1_compute_workgroup_execution_frontend_tb.sv`

**Interfaces:**
- Export read-only `allocation_reserved_bitmap`, `allocation_active_bitmap`, `allocation_sanitized_bitmap`, `allocation_row_base_flat`, `allocation_register_count_flat`, and `vector_execution_busy_bitmap` through the existing pooled subsystem and mixed frontend. These are views of existing state, not new allocation counters.
- The new workgroup frontend accepts a dispatch descriptor containing workgroup id, wave count, one 9-bit architectural VGPR count per local wave, scalar-state demand, shared/local byte demand, and extra-state demand. `dispatch_valid && dispatch_ready` starts one internal transaction; `dispatch_result_valid` returns the eventual `dispatch_accepted` and failure code.
- During the transaction, the frontend drives the existing `reserve_*`, `activate_*`, and `release_*` interfaces. No barrier context or scheduler issue bit is committed until every selected slot is active in the real allocator.
- Matrix/vector request arrays retain their existing wave-slot encoding; requests are masked unless their mapped workgroup is committed, the wave is live, and the wave is not at a barrier or terminal-pending.

- [x] **Step 1: Add allocator-view assertions to the existing mixed-front-end test**

After reserve, sanitization, activation, and release, compare the newly exported views with the existing allocator outputs used by the pooled subsystem. Run the existing mixed-front-end RTL case and confirm the added view assertions fail before the export is wired.

- [x] **Step 2: Export the existing allocator bitmaps and maps without adding duplicate state**

Wire the current `alloc_reserved`, `alloc_active`, `alloc_sanitized`, `alloc_base_flat`, and `alloc_count_flat` signals through both module boundaries. Generate the vector busy bitmap from the pipeline's actual `vector_busy` and live wave tag. Run the existing mixed-front-end test.

- [x] **Step 3: Add transaction tests for complete reserve, activation, and rollback**

The new integration test shall fill allocator rows so a two-wave request can reserve its first wave but the second wave's larger contiguous request fails. Assert `dispatch_result_valid` reports failure only after rollback, all allocator views equal the pre-dispatch snapshot, and no scheduler-visible wave bit appeared. Also assert nonuniform register counts and actual row-base/count maps on successful complete admission.

- [x] **Step 4: Implement the admission transaction over the actual allocator**

Select only slots shown free by the allocator bitmap. Reserve one local wave at a time with its exact count; hold the transaction private while the allocator sanitizes reserved rows; activate each wave only after its actual sanitized bit is set. If a reserve is refused, release each previously reserved slot through the existing allocator and return failure after the reserved bitmap is clear. Commit the wave-to-slot map only after all allocations are active. Preserve provisional shared/local and scalar/extra-state accounting as part of the same commit/rollback transaction.

- [x] **Step 5: Run the focused RTL integration case**

Run: `bash scripts/validate_rtl.sh` after adding the new testbench to the gate. Confirm successful multi-wave reservations use actual allocator maps, fragmented failure leaves the pool unchanged, and no request is accepted before complete commit.

### Task 3: Make barrier, issue, busy, and lifecycle state follow actual allocations

**Files:**
- Refactor: `source/rtl/cgx1_workgroup_residency_barrier.sv` into barrier membership/context state only; remove its independent VGPR row allocator and resource-row counters
- Modify: `source/rtl/cgx1_compute_workgroup_execution_frontend.sv`
- Modify: `source/rtl/tests/cgx1_workgroup_residency_barrier_tb.sv`
- Modify: `source/rtl/tests/cgx1_compute_workgroup_execution_frontend_tb.sv`

**Interfaces:**
- Barrier admission receives the committed local-wave-to-actual-slot map and provisional workgroup resource demand. Barrier release reports the completed generation and the exact live slot mask.
- Wave retirement/fault updates barrier participation immediately. A separate allocator-release completion input clears ownership metadata only after the existing pooled allocator accepts release.
- Workgroup kill removes all waves from issue and barrier participation immediately, then retains its context and provisional local-memory accounting until every busy wave is quiescent and every real allocator release completes.
- Per-wave quiescence combines the mixed frontend's actual matrix and vector busy outputs; the pooled subsystem's own release guard continues to check RF traffic, restore, and split-read state.

- [x] **Step 1: Add failing integration checks for sibling issue and retained allocations at a barrier**

Admit a complete two-wave group, issue a matrix operation from one wave and ordinary vector work from the other, place one completed wave at a barrier, and assert its actual allocator state stays active while the sibling's vector operation completes and remains issuable.

- [x] **Step 2: Remove the barrier module's logical VGPR allocation ownership**

Keep only workgroup context, local-to-slot membership, live/arrived masks, generation, and provisional shared/extra state. Drive allocator state exclusively from the mixed frontend's existing pool. Verify the barrier module no longer contains physical VGPR row selection or row-used totals.

- [x] **Step 3: Gate matrix and vector issue from committed barrier membership**

Mask both request arrays with the committed live/nonwaiting slot mask. Preserve the mixed frontend's internal dependency scoreboard, matrix/vector same-edge exclusion, and service policy. Confirm nonarrived siblings and independent workgroups still reach their normal arbitration paths.

- [x] **Step 4: Add deferred terminal release for active execution**

On wave retire/fault or group kill, block new issue in the same cycle, remove terminal waves from the barrier's required participant set, and retain actual pooled allocations while either execution busy bit is set. Release only through the real allocator after quiescence. Keep a workgroup's provisional shared/local allocation until its final owned wave allocation has been released.

- [x] **Step 5: Verify terminal, kill, reset, and barrier-generation transitions**

Cover retire-before-barrier, fault before a barrier, fault while another wave waits, vector-in-flight fault, matrix-in-flight fault, workgroup kill while blocked, repeated generations, reset during active and partial-reservation ownership, and immediate slot/row reuse. Run the workgroup integration RTL test and existing scheduler, matrix/vector, and pooled-VGPR RTL cases.

### Task 4: Close randomized integration evidence and public status

**Files:**
- Modify: `source/model/workgroup_scheduler_tests.cpp`
- Modify: `source/rtl/tests/cgx1_compute_workgroup_execution_frontend_tb.sv`
- Modify: `scripts/validate_rtl.sh`
- Modify: `design/cgx1_architecture.json`
- Modify: `scripts/check_design_consistency.ps1`
- Modify: `scripts/test_design_consistency_windows.ps1`
- Modify: `docs/VALIDATION.md`, `docs/STATUS.md`, `docs/ROADMAP.md`, `docs/SCHEDULING_PREEMPTION.md`, and `source/rtl/README.md`

- [x] **Step 1: Add deterministic randomized lifecycle sequences**

Run a deterministic 100,000-transition C++ randomized lifecycle sequence and 5,100 seeded RTL barrier-arrival transactions across the supported arrival orders. The RTL integration cases also exercise dispatch, exact-size reserve, mixed execution/completion, barriers, retirement, fault, kill, active and partial reset, rollback, and allocator reuse. After each C++ step assert pool invariants, no partial admitted group, no issue for a waiter/terminal wave, and no persistent pool/controller ownership mismatch.

- [x] **Step 2: Add schema invariants and negative controls**

Require the workgroup integration record to claim allocator composition only when the RTL controller wires the actual pool, and reject claims of wave swapping or physical implementation. Add a negative control that flips `actual_pooled_vgpr_allocator_integrated` to false while integration is claimed.

- [x] **Step 3: Update architecture and validation documentation**

Document the transaction, allocator source of truth, rollback, issue mask, quiescent release point, per-wave architectural VGPR limits, provisional shared/local accounting, and open physical/hosted evidence. Keep `simulation_exercised` false until the published exact revision's CI completes.

- [x] **Step 4: Run the complete local gate**

Run `cmake --build build -j2`, `ctest --test-dir build --output-on-failure`, `bash scripts/validate_rtl.sh`, and the repository Windows hygiene, integrity, design-consistency, negative-control, and Markdown-link checks. Review `git diff --check`, the staged diff, and the final status before a local commit. Do not push this dependent integration while the `d8be39e` hosted validation is unresolved.

---

## Spec coverage check

- Real allocator authority, whole-group transaction, late-reserve rollback, exact per-wave sizes, physical row rounding, fragmentation, stale-data sanitization, and re-use: Tasks 1 and 2.
- Mixed vector and matrix execution, barrier eligibility, sibling/independent workgroup progress, per-wave busy/quiescence, terminal release, fault and kill while active or blocked: Task 3.
- Dispatch, retirement, fault, reset/recovery, random integrated lifecycles, docs/schema/gates, and proof-class boundaries: Tasks 2–4.
- Mandatory workgroup-boundary preemption and no wave swapping: Global Constraints and Task 4 schema checks.

## Plan self-review

- The five highest-risk input/failure classes each have an explicit test in Tasks 1–3.
- The C++ reference and RTL use the existing real allocation implementations; no parallel row map remains authoritative.
- Public scheduler visibility is delayed until complete activation and group commit.
- Failure rollback releases reserved allocations before its result is reported.
- No physical memory, timing, area, power, or silicon claim is introduced.
