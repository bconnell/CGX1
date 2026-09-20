# Virtual Memory and Address Translation

[Documentation index](README.md) · [ISA and execution model](ISA.md) · [Chiplet fabric](CHIPLET_FABRIC.md) · [Software stack](SOFTWARE_STACK.md)

## Address spaces

CGX 1 targets **57-bit GPU virtual addresses** and a **52-bit physical-address implementation target**.

Every user process receives a protected GPU address space. Firmware and kernel mappings use separate privileged protection domains.

Basic CGX operation does **not** depend on PCIe ATS, PRI or PASID support from the host.

## Page sizes

Supported architecture page sizes:

- 4 KiB;
- 64 KiB;
- 2 MiB.

64 KiB is the preferred normal VRAM mapping size and the sparse-resource granularity target. Smaller pages remain available where allocation shape or host integration requires them.

## Translation hierarchy

The architecture provides:

- per-CU near translation caching;
- tile-level translation caching;
- a shared I/O-die translation/fault service;
- invalidation broadcasts to affected tile translation caches;
- permission checks for read, write, execute and privileged access.

Exact TLB entry counts and associativity remain physical-design parameters.

## Page faults

Replayable faults are required for normal demand-paged resources.

A replayable fault records enough context to identify:

- process/address-space ID;
- queue;
- wave/workgroup or command;
- virtual address;
- access type;
- protection/fault reason.

The scheduler may park the affected work while independent queues continue.

A protection violation is not replayed as a demand page. It faults the responsible context.

## Host address translation

PCIe PASID, ATS and PRI are optional accelerators for platforms that support them.

PCI-SIG defines PASID as a 20-bit process address-space identifier associated with a requester and defines its use with address translation. CGX reserves support for the full 20-bit PASID field when that path is enabled.

When ATS/PASID/PRI are absent, the CGX driver maintains device page tables and explicit mappings through the normal PCIe aperture.

## Residency and oversubscription

The memory manager may migrate or evict resources between HBM and host memory.

The architecture must support:

- pinned non-evictable allocations;
- pageable allocations;
- sparse resources;
- read-only replicated mappings;
- queue-safe eviction;
- fault replay after residency is restored.

Oversubscription is a capability, not a performance claim. HBM-resident data remains the preferred path.

## Isolation

A process must not be able to access another process's GPU virtual mappings by selecting a raw physical address.

Queue/context identity is carried through translation and fault reporting so one process fault can be contained without resetting unrelated contexts whenever hardware state permits.
