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

At each CU, `ComputeUnitDispatchScheduler` and `cgx1_compute_workgroup_dispatch_scheduler.sv` provide a local decoded-compute ingress. Descriptors carry one of the 64 queue-context IDs plus process/address-space identity, priority, engine class, and workgroup demand. Per-context FIFO order is preserved; transient resource pressure retains the descriptor for retry, while permanent admission failures and unsupported engine classes complete explicitly. Tile eligibility and queue fault state gate dispatch. The CU dispatcher delegates complete resource admission and lifecycle to the existing workgroup owner.

The reference defaults to numeric priority 0 as lowest, 7 as highest, weights 1 through 128, 64-cycle aging, and eight pending workgroups per context. The RTL defaults to the same priority weights and aging interval with a configurable bounded descriptor queue. These are implementation/test policy values, not calibrated performance targets or a frozen queue ABI.

`CommandQueueRuntime` provides the first executable command-packet boundary above the CU dispatcher. Each registered hardware queue context owns a bounded byte ring; packet writes are all-or-nothing, incomplete packets remain buffered, and parsing preserves the registered process/address-space identity. Valid workgroup descriptors enter the existing per-context dispatcher FIFO, where resource admission and whole-workgroup lifetime remain authoritative. Queue reset reports discarded byte ranges, cancels pending work, and waits for resident workgroup quiescent retirement before reporting completion. The candidate packet format and storage policy are reference-model choices, not a frozen public ABI or a hardware ring contract. RTL command parsing, global I/O-die queue management, and compiler/runtime submission remain open.

## Compute-unit workgroup residency and barriers

Complete-workgroup residency is the baseline for compute execution. A CU admits a workgroup only after it can reserve the entire wave set and all declared CU-local state together. It must not make only a subset resident and wait for later batches to reach a workgroup barrier.

Admission accounts for resident-wave slots, pooled VGPR rows, per-wave scalar/predicate state, shared/local-memory capacity, one finite barrier context per workgroup, and additional declared workgroup-local state. Both the executable reference and RTL workgroup frontend reserve a real shared/local-memory region with the pooled VGPR state; fragmented byte capacity and late VGPR reservation failure leave no partial admission. The allocator's per-slot bitmap and exact register-count map remain the sole authority for physical rows and slot availability; the controller keeps only workgroup-to-slot membership. Per-wave architectural counts are bounded at 256 and rounded to eight-register physical rows only by the allocator.

After commit, matrix, vector, and decoded memory requests are masked by actual active allocations and the committed live, nonwaiting workgroup mask. The LSU permits one outstanding memory instruction per wave and multiple wave waiters per CU. Load destinations join the ordinary vector dependency scoreboard until successful VGPR writeback; dependent vector work stalls while independent vector work and sibling waves can continue. Matrix requests from a wave with outstanding memory are conservatively held because the current matrix issue path has no external memory-destination scoreboard input. Barrier arrival is tracked by workgroup-local wave index and generation. A wave with its own unfinished memory operation cannot arrive, but it remains a live barrier participant; a sibling that has arrived waits until every surviving participant reaches the barrier. A generation releases only when every live, non-terminated participant has arrived. Reuse advances the generation and clears the arrival set.

Normal wave completion, wave fault, and wave kill retire that participant from issue and barrier membership immediately. An allocation remains active while its actual matrix or vector execution is busy; the wrapper requests release only after the corresponding busy bits clear, and the pooled subsystem's release guard also checks in-flight register traffic. A remaining set of barrier waiters is released when all surviving participants have arrived. Workgroup-local resource accounting remains reserved until the final pooled allocation release is accepted. A whole-workgroup kill/fault prevents new issue, retires every participant, and drains its allocations at quiescence. Reset clears the allocator and barrier state together. Baseline workgroup-boundary preemption remains unchanged; resident-wave save/restore and wave swapping are not prerequisites for barriers.

The executable reference composes `ComputeUnitWorkgroupScheduler` with `ResidentWaveVgprPool`, `PooledVgprStorage`, and the shared/local-memory component. RTL composes the authoritative workgroup frontend, pooled VGPR path, shared/local region allocator, LSU, vector dependency scoreboard, and barrier tracker. Both retain memory-waiting waves as live participants and drain accepted terminal traffic before releasing shared or VGPR state. Local tests cover variable per-wave register counts, maximum fit, aggregate VGPR rejection, shared-memory demand rejection and fragmentation, transactional rollback, local/global requests, memory-wait and barrier interaction, sibling and independent-workgroup progress, reset and stale-response rejection, load writeback dependencies, same-wave issue ordering, terminal drain, local-region reuse, and deterministic randomized memory/barrier lifecycles. The CU-local decoded workgroup dispatcher adds bounded queue contexts, weighted aging, tile eligibility, queue-fault handling, retryable versus terminal admission results, and an RTL integration test against the authoritative frontend. ISA decode/opcode assignment, the I/O-die global queue manager, command ABI, graphics dispatch, multi-CU placement, compiler/runtime submission, and full GPU integration remain open. Local C++ and Icarus evidence does not establish hosted CI, synthesis, timing, area, power, or silicon behavior.

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
