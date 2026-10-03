# CGX1 Workgroup Memory Integration Plan

## Outcome

Make shared/local-memory region ownership authoritative across complete-workgroup admission and retirement in both the executable scheduler reference and the RTL workgroup frontend. Preserve complete workgroup residency and workgroup-boundary preemption. The current RTL slice integrates region allocation only; vector load/store issue and scheduler memory-wait handling remain separate work.

## Current state

- The C++ `ComputeUnitWorkgroupScheduler` owns actual pooled VGPR allocations and shared/local-memory regions. It gates memory-waiting waves, rejects barrier arrival during a memory wait, drains terminal operations, and releases a region after whole-workgroup quiescence.
- The current RTL workgroup frontend composes `cgx1_cu_shared_local_memory` as its real region allocator. Admission allocates and scrubs the region before reserving/activating VGPR waves. A late VGPR failure rolls back both resources. Final shared-memory and VGPR release handshake in the same cycle only after execution, restore, and allocator guards are quiescent; a held restore request proves the region remains reserved during release backpressure.
- The RTL allocator's load/store request, response, and cancellation interfaces are tied off in this slice. Vector memory instructions, RTL memory-wait issue gating, hardware queue/runtime dispatch and completion, and physical implementation remain open.
- The last pushed candidate is `56dde4cd92c261063d62c7019d81f6d8b4c8cc01`. RTL CI run `37091104373` and Windows CI run `37091104769` both completed successfully for that exact SHA.
- The focused workgroup frontend test and the full `scripts/validate_rtl.sh` gate pass on the pushed candidate, including shared-region preservation when later VGPR admission fails and final-release backpressure while same-wave restore traffic is active. The 23-target Release CTest suite passed. The local Windows wrapper passed public hygiene, repository integrity, design consistency and negative controls, and Markdown links, then stopped at CMake because `cmake.exe` is not on Windows PATH; hosted Windows CI for the exact pushed SHA passed.

## Contract

- Reserve a real contiguous shared/local-memory range as part of complete-workgroup admission, before any wave is made resident or issuable.
- Do not publish a partially admitted group. If subsequent per-wave VGPR allocation fails, release all reserved VGPR state and the provisional shared-memory range before reporting dispatch failure.
- Report shared-memory fragmentation separately from aggregate capacity exhaustion.
- Keep the range owned while any wave of the admitted workgroup remains resident. On terminal release, wait for execution quiescence and release the region with the final wave's allocator entry.
- Reset clears both allocator state and barrier/workgroup membership.
- Keep RTL memory request/response/cancel tied off until the vector LSU and memory-wait issue-mask lifecycle are implemented together.

## Implementation and validation sequence

1. [x] Integrate shared-memory regions and memory waits in the C++ workgroup reference, including rollback, drain, and reset behavior.
2. [x] Instantiate the actual shared-memory allocator inside the RTL workgroup frontend and expose its allocated-byte count as the authoritative usage.
3. [x] Couple dispatch allocation, scrub completion, late VGPR-failure rollback, and last-quiescent-wave release to the shared-memory allocator.
4. [x] Add RTL regressions for maximum-fit allocation, fragmented-region rejection, hole reuse, and VGPR-fragmentation rollback across both allocators.
5. [x] Run the final RTL gate, focused frontend/barrier/memory coverage, repository consistency and negative-control gates, Markdown links, and CTest. RTL and CTest passed; Windows text gates passed before the documented missing-CMake environment stop.
6. [x] Inspect the exact hosted workflow results for `56dde4c`: both RTL CI and Windows CI completed successfully on the exact SHA.
7. Next slice: connect vector load/store decode and tagged memory responses to per-wave memory-wait issue gating, terminal cancellation/drain, and workgroup resource release.

## Evidence boundary

Local Icarus simulation establishes the tested RTL region-allocation and lifecycle behavior for the exact local candidate. It does not establish hosted CI for that candidate, memory-instruction/LSU integration, synthesis, timing, area, power, physical implementation, or silicon behavior.
