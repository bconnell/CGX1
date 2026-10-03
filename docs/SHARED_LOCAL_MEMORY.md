# CU Shared/Local Memory

[Documentation index](README.md) · [ISA and execution model](ISA.md) · [Scheduling and preemption](SCHEDULING_PREEMPTION.md) · [Validation](VALIDATION.md)

## Current implementation

The repository now contains an executable C++ reference and a standalone SystemVerilog CU shared/local-memory component. They exercise a finite workgroup-scoped byte pool and wave32 32-bit loads and stores. The RTL component is parameterized; its default 32-bank organization is a model choice and is not a frozen architecture requirement.

The existing workgroup admission frontend still treats `shared_local_bytes` as provisional resource accounting. It does not allocate regions through this memory component, and the vector execution frontend has no load/store opcodes or LSU connection yet. Do not describe shared/local memory execution as integrated into the current scheduler.

## Reference contract

- A workgroup receives a private contiguous region from the CU byte pool. Allocation uses a four-byte-aligned first-fit base; an allocation can report fragmentation when enough bytes are free in aggregate but no contiguous range fits.
- Region storage is initialized before it is made available to the workgroup. Reused regions cannot expose another workgroup's old data.
- Requests carry workgroup ID, wave ID, caller transaction tag, a 32-bit active-lane mask, 32 byte offsets, and 32 store words. Inactive lanes do not access memory.
- The implemented operation is a naturally aligned 32-bit load or store. The entire active-lane request is checked before any lane is serviced. A misaligned or out-of-range active lane produces a tagged fault completion without partial stores.
- Physical dword bank selection is `(region base + byte offset) / 4 modulo bank count`. Each bank services at most one lane per cycle. Colliding lanes take later cycles; distinct banks can work in parallel. Per-bank arbitration rotates among outstanding transactions.
- One wave can own one outstanding transaction. It remains waiting until its tagged response is consumed. Loads return one word per active lane; stores return an acknowledgement.
- Cancellation suppresses the response but drains already accepted lane service. Accepted stores are not rolled back. Region release waits until service drains and any response is consumed or cancelled.
- Reset drops allocation, request, response, and wait ownership. RTL valid metadata is reset; a newly allocated region is scrubbed before activation.

## Validation and open work

`cgx1_shared_local_memory_checks` covers region capacity, fragmentation, isolation, reuse, wave waits, response tags, mask behavior, fault atomicity, bank conflicts, fairness, cancellation, reset, and seeded randomized service. `cgx1_cu_shared_local_memory_tb.sv` checks the RTL contract, including a non-power-of-two bank count, all 32 lanes, response stability under backpressure, faulting requests, drain, and reset/reuse.

This component does not implement ISA decode or load/store issue, workgroup-frontend admission coupling, memory-wait issue masking, scalar or vector LSU integration, subword operations, global memory, caches, translation, atomics, fences, ordering scopes, or compiler/runtime dispatch. Bank count and timing remain parameters. Local model and RTL simulation do not establish synthesis, memory-macro selection, timing, area, power, physical implementation, or silicon behavior.
