# Chiplet Fabric

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [Virtual memory](VIRTUAL_MEMORY.md) · [Scheduling and preemption](SCHEDULING_PREEMPTION.md)

## Topology

CGX 1 uses a central I/O/cache die with four coherent compute-tile links.

The package fabric connects:

- four compute tiles;
- package-level cache and coherence directory;
- HBM controllers;
- PCIe;
- display/media;
- firmware/security/control blocks.

The fabric does not expose the four compute tiles as separate PCIe functions or separate GPUs.

## Physical-link reference

**UCIe 3.0 is the preferred reference for the die-to-die physical and management layer.** UCIe 3.0 defines 48 GT/s and 64 GT/s operation plus priority sideband packets, fast throttle/emergency shutdown and expanded manageability.

CGX 1 does not currently claim UCIe compliance. Final lane counts, PHY instances, bump maps and package routing are not frozen. The CGX coherence/traffic protocol above the physical link remains a separate architecture.

## Bandwidth budget

The fabric is sized so the compute-tile read path does not undercut the 6.6 TB/s HBM4 peak target before cache effects are considered.

Targets:

| Direction | Target |
|---|---:|
| I/O/cache die to each compute tile | 1.8 TB/s payload read capacity |
| Aggregate read payload to four tiles | 7.2 TB/s |
| Aggregate compute-tile write payload | 3.6 TB/s |

These are architecture bandwidth budgets, not measured UCIe throughput claims. Physical mapping must demonstrate the required payload after protocol overhead before it is accepted.

## Coherence

- coherence granule: 64 bytes;
- tile L2: write-back;
- package cache: directory tracks ownership/sharers;
- no broadcast snoop for normal coherent traffic;
- dirty ownership is transferred through explicit coherence messages;
- host-visible mappings follow the virtual-memory/system-scope ordering rules.

The package cache need not be inclusive of every tile L2 line, but its directory must be sufficient to locate dirty or shared copies.

## Traffic classes

Separate logical traffic classes are provided for:

- request;
- response;
- data;
- snoop/coherence;
- management.

The implementation must prevent a saturated data path from blocking fault, throttle or emergency-management traffic.

## Reliability

Each link requires:

- CRC detection;
- link-level retry for retryable transfer errors;
- poison propagation for uncorrectable data;
- timeout detection;
- per-link error counters;
- degraded/reset reporting to firmware;
- priority management events;
- fast throttle and emergency shutdown notification.

A single failed tile link must be isolatable so firmware can enter a safe state or boot a reduced configuration during engineering validation.

## Deadlock and QoS

Protocol virtual-channel ordering must be proven deadlock-free before RTL completion.

The fabric scheduler must support traffic priority sufficient to protect:

- display scanout deadlines;
- page-table/fault traffic;
- firmware/control messages;
- latency-sensitive graphics work

without permanently starving bulk compute or memory transfers.
