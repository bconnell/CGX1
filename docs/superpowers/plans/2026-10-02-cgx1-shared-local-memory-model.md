# CGX1 Shared/Local Memory Model Plan

## Active outcome

Add executable C++ and standalone RTL references for the first CU-local memory capability: workgroup-isolated, byte-addressed 32-bit loads and stores issued as wave32 requests over a finite banked shared-memory pool. Requests validate every active lane before acceptance, remain outstanding through bank service, and return tagged responses. Shared/local byte demand is allocated from the finite CU capacity and retained until the workgroup releases it.

This is a first implementation slice in the long-running GPU goal. The RTL block is standalone and is not yet integrated with workgroup admission, vector LSU issue, or memory-wait scheduling. This slice does not claim a frozen bank count/latency, global memory, virtual translation, subword accesses, atomics, or end-to-end ISA dispatch.

## Current evidence and constraints

- The implementation started from commit `13a188b1128f6b626d5e4bfd063b66a39893803a` in the existing `bconnell/CGX1` checkout; `origin` resolves to `https://github.com/bconnell/CGX1.git`.
- The remote completeness branch remains at `d8be39e44999bde5877c9e938c928f9040c9c4e1`. Its exact GitHub `validate` and `simulate` check runs completed successfully; no workflow run remains pending for that revision. The shared/local-memory checkpoint is local and has not been hosted-validated.
- Existing workgroup admission still keeps provisional shared/local byte accounting and is not connected to the memory array or load/store access path.
- Workgroup barriers and pooled VGPR allocation are authoritative and must remain unchanged by this model-only slice.
- Repository-local instructions require preserving existing work, executable behavior, bounded claims, exact reviewed commits, and continuation through safe coherent batches.

## Contract for this slice

- A CU has a finite byte capacity and configurable bank count; the reference default is 32 banks for wave32, but it is an implementation parameter, not a frozen architecture value.
- Each admitted workgroup owns a byte range. Ranges are isolated, released only when no transaction is still owned, and zeroed on allocation/reuse.
- Requests contain a workgroup ID, wave ID, caller transaction tag, a 32-bit active-lane mask, 32 byte addresses, and 32 store words. Inactive lanes do not access memory.
- The initial supported operation is naturally aligned 32-bit load or store. Every active lane is prevalidated for alignment and range before the request is accepted; a failing lane causes a deterministic request fault and no side effects.
- Each bank services at most one lane per cycle. A bank conflict serializes colliding lanes over later cycles. Arbitration rotates so continuously pending requesters cannot monopolize a bank.
- A wave may own at most one outstanding transaction in this model. The wave remains memory-waiting through service and until its tagged response is consumed. Reset clears allocations, transactions, responses, and wait state.
- Loads return per-lane data; stores return completion acknowledgements. Cancelled/terminal wave transactions must drain accepted service before range release; response delivery can be suppressed after terminal state.

## Implementation sequence

- [x] Add directed C++ tests for allocation/release, isolation, all-or-nothing invalid requests, mask behavior, load/store, bank conflicts, independent banks, response tags, in-flight release blocking, terminal drain, and reset/reuse.
- [x] Implement the C++ reference API in `source/memory/` and register its focused CTest target.
- [x] Add deterministic randomized request/service/reuse coverage with recorded seed `0xC0FFEE`.
- [x] Add a standalone RTL implementation and testbench, including stalled-response stability, terminal drain, allocation scrub, and full-fit capacity cases.
- [x] Run the full CMake build and 23 CTest targets, repository RTL suite, strict-warning GCC model build, Windows hygiene and consistency checks, negative controls, Markdown links, and `git diff --check`.
- [x] Update architecture/status/validation/roadmap claims to distinguish local evidence from hosted and physical evidence.
- [ ] Continue with a separately scoped integration slice that makes workgroup allocation and memory waits authoritative in the execution frontend/LSU path.

## Likely failure modes to attack

- Two workgroups aliasing or reading stale bytes after region reuse.
- An invalid lane allowing partial stores from otherwise-valid lanes.
- Masked-off invalid addresses causing false faults or side effects.
- Same-bank requests completing in one cycle, or different banks being serialized unnecessarily.
- Lost, mis-tagged, duplicated, or early responses.
- Region release while requests remain in service or responses remain unconsumed.
- Fault, cancellation, and reset paths leaking wave waits, request slots, or capacity.
- Arithmetic overflow in capacity, range, byte-address, and bank calculations.

## Validation and claim boundary

The C++ suite establishes behavior of the executable reference, and the Icarus test establishes behavior of the standalone RTL component. Together they do not establish RTL equivalence, ISA decode/instruction issue integration, synthesis, timing, area, power, cache/global-memory behavior, physical implementation, or silicon behavior. Keep hosted and physical evidence fields truthful until their exact gates run on the candidate that claims them.
