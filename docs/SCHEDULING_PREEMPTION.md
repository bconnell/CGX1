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

Admission accounts for resident-wave slots, pooled VGPR rows for every wave, per-wave scalar/predicate state, shared/local-memory capacity, one finite barrier context per workgroup, and additional declared workgroup-local state. VGPR demand is rounded to the physical eight-register row granularity for capacity, while the exact architectural register count remains authoritative. If enough rows exist in total but first-fit row ranges cannot be placed for all waves, admission reports fragmentation and makes no partial reservation. Per-workgroup capacities and slot counts remain parameters; the tested values do not freeze occupancy.

Every admitted live wave has a resident slot and its VGPR row reservation. Barrier arrival is tracked by workgroup-local wave index and generation. An arriving wave stops being issuable while its architectural and allocated state remains resident; not-yet-arrived waves remain eligible for issue. A generation releases only when every live, non-terminated participant has arrived. A single-wave barrier therefore releases on that wave's arrival. Reuse advances the generation and clears the arrival set.

Normal wave completion, wave fault, and wave kill retire that participant, free its wave-local resources, and remove any pending arrival. If the remaining live waves were all waiting at the barrier, the barrier advances for them. A whole-workgroup fault or kill destroys that workgroup's barrier context and releases its resources. Reset clears all group, wave, barrier, and resource ownership. Baseline workgroup-boundary preemption remains unchanged; resident-wave save/restore and wave swapping are not prerequisites for barriers.

The current executable reference and parameterized RTL boundary validate these rules, including the output mask consumed by the existing resident-wave issue arbiter. The RTL candidate still owns a separate logical VGPR-row reservation map: it is not yet composed with the pooled VGPR execution subsystem, the mixed matrix/vector frontend, shared/local-memory access logic, memory waits, queue dispatch, fault reporting, or retirement. This is a workgroup admission/barrier foundation, not a complete CU scheduler or working shared-memory datapath. Those integration layers remain open.

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
