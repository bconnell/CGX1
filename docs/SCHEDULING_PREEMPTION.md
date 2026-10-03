# Scheduling and Preemption

[Documentation index](README.md) · [ISA and execution model](ISA.md) · [Virtual memory](VIRTUAL_MEMORY.md) · [Chiplet fabric](CHIPLET_FABRIC.md) · [Power management](POWER_MANAGEMENT.md)

## Queue architecture

The central I/O die owns the global queue manager. Each compute tile has a local dispatch scheduler.

The first architecture target provides **64 resident hardware queue contexts** across graphics/compute execution and **8 priority levels**. Operating-system/runtime software may expose more logical queues by virtualizing them over resident contexts.

Queue identity includes its process/address-space identity, priority, engine class and fault state.

## Scheduling policy

The default policy is weighted fair scheduling with aging.

Priorities may favor latency-sensitive graphics, display-supporting work or system tasks, but a continuously runnable lower-priority queue must eventually receive service.

Work placement is power-aware. The global scheduler knows which tiles are powered and eligible in P0-P4 states and must not dispatch work to a gated tile.

## Compute-unit workgroup residency and barriers

Complete-workgroup residency is the baseline for compute execution. A CU admits a workgroup only after it can reserve the entire wave set and all declared CU-local state together. It must not make only a subset resident and wait for later batches to reach a workgroup barrier.

Admission accounts for resident-wave slots, pooled VGPR rows, per-wave scalar/predicate state, shared/local-memory capacity, one finite barrier context per workgroup, and additional declared workgroup-local state. In the executable reference, a real shared/local-memory region is reserved with the pooled VGPR state; fragmented byte capacity and late VGPR reservation failure both leave no partial admission. The RTL workgroup frontend still keeps provisional shared/local byte accounting. The allocator's per-slot bitmap and exact register-count map remain the sole authority for physical rows and slot availability; the controller keeps only workgroup-to-slot membership. Per-wave architectural counts are bounded at 256 and rounded to eight-register physical rows only by the allocator.

After commit, matrix and vector requests are masked by actual active allocations and the committed live, nonwaiting workgroup mask. Barrier arrival is tracked by workgroup-local wave index and generation. An arriving wave stops being issuable while its architectural and allocated state remains resident; nonarrived siblings remain eligible for the mixed frontend's dependency and execution arbitration. A generation releases only when every live, non-terminated participant has arrived. A single-wave barrier therefore releases on that wave's arrival. Reuse advances the generation and clears the arrival set.

Normal wave completion, wave fault, and wave kill retire that participant from issue and barrier membership immediately. An allocation remains active while its actual matrix or vector execution is busy; the wrapper requests release only after the corresponding busy bits clear, and the pooled subsystem's release guard also checks in-flight register traffic. A remaining set of barrier waiters is released when all surviving participants have arrived. Workgroup-local resource accounting remains reserved until the final pooled allocation release is accepted. A whole-workgroup kill/fault prevents new issue, retires every participant, and drains its allocations at quiescence. Reset clears the allocator and barrier state together. Baseline workgroup-boundary preemption remains unchanged; resident-wave save/restore and wave swapping are not prerequisites for barriers.

The executable reference composes `ComputeUnitWorkgroupScheduler` with `ResidentWaveVgprPool`, `PooledVgprStorage`, and the shared/local-memory component. Reference memory requests make only their wave non-issuable until response consumption; barriers reject that wave during memory wait, terminal cancellation drains accepted lanes, and the region remains owned until the whole workgroup is quiescent. The RTL `cgx1_compute_workgroup_execution_frontend` still composes the admission/barrier controller with the mixed matrix/vector frontend but does not yet own the standalone RTL memory component. Local tests cover variable per-wave register counts, maximum fit, aggregate VGPR rejection, shared-memory demand rejection and fragmentation, transactional rollback, memory wait and barrier interaction, sibling and independent-workgroup progress, reset/reuse, real matrix/vector operations, terminal drain, and randomized sequences. No vector LSU, RTL memory-wait mask, hardware queue/runtime integration, compiler/runtime dispatch or completion, or complete CU scheduler is present. Local C++ and Icarus evidence does not establish exact-revision CI, synthesis, timing, area, power, or silicon behavior.

## Preemption boundaries

Mandatory baseline boundaries are deliberately implementable:

- compute: workgroup boundary;
- graphics: draw/dispatch packet boundary;
- queue: command-packet boundary.

Finer wave-level preemption is a future target after register/state-save bandwidth and latency are characterized. It is not required by the first hardware implementation.

A page fault may stall/replay the affected work without waiting for the entire queue to complete.

## Context state

A preemptible context includes:

- queue read/write state;
- program/dispatch state;
- register and execution masks needed by the chosen preemption boundary;
- memory/translation identity;
- barrier and synchronization state that must survive the boundary;
- fault and watchdog state.

The implementation may keep context state on chip or spill it to protected memory.

## Watchdog and recovery

A stuck workload escalates through the smallest reset domain that can restore forward progress:

1. engine reset;
2. compute-tile reset;
3. full-device reset.

Firmware records the failing queue/context and reset level.

A graphics or compute hang should not immediately discard unrelated work if an engine- or tile-level recovery succeeds.

## Power-state behavior

P0-P4 define board power envelopes, not fixed active-tile counts. The power-management controller publishes an eligible-tile mask, and the scheduler must not dispatch to a tile outside that mask.

For an orderly reduction in available capacity, the scheduler stops new dispatch and drains or preempts work at an allowed boundary before the tile can enter retention/off. Dirty coherent state must be resolved before orderly power gating.

Emergency thermal/dock faults retain authority to drop immediately to the safe P0 behavior defined by the board safety controller. Emergency isolation may discard unfinished work when an orderly drain cannot complete.

See [Power Management](POWER_MANAGEMENT.md).
