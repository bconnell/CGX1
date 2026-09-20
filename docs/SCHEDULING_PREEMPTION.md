# Scheduling and Preemption

[Documentation index](README.md) · [ISA and execution model](ISA.md) · [Virtual memory](VIRTUAL_MEMORY.md) · [Chiplet fabric](CHIPLET_FABRIC.md)

## Queue architecture

The central I/O die owns the global queue manager. Each compute tile has a local dispatch scheduler.

The first architecture target provides **64 resident hardware queue contexts** across graphics/compute execution and **8 priority levels**. Operating-system/runtime software may expose more logical queues by virtualizing them over resident contexts.

Queue identity includes its process/address-space identity, priority, engine class and fault state.

## Scheduling policy

The default policy is weighted fair scheduling with aging.

Priorities may favor latency-sensitive graphics, display-supporting work or system tasks, but a continuously runnable lower-priority queue must eventually receive service.

Work placement is power-aware. The global scheduler knows which tiles are powered and eligible in P0-P4 states and must not dispatch work to a gated tile.

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

P0-P2 may expose fewer active compute tiles or lower residency limits than docked modes. The scheduler discovers the eligible resources from firmware rather than assuming all four tiles are always active.

Transition into a lower-power state drains or preempts work from a tile before that tile is power-gated.

Emergency thermal/dock faults retain authority to drop immediately to the safe P0 behavior defined by the power controller.
