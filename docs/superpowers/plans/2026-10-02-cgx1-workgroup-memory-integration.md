# CGX1 Workgroup Memory Integration Plan

## Outcome

Make the executable workgroup scheduler own the shared/local-memory region allocator and transaction lifecycle. A shared-byte demand must receive a real contiguous range as part of complete-workgroup admission. A wave that issues a local-memory request becomes non-issuable until its tagged response is consumed. Barriers, wave termination, workgroup abort, and reset must account for memory wait and accepted service without releasing state early.

This is a C++ scheduler integration slice. The RTL memory component remains standalone during this phase. Vector load/store opcodes, LSU datapath integration, RTL dispatch coupling, and hardware wait-mask integration remain subsequent work. No wave swapping is introduced.

## Current state

- The standalone C++ memory model and parameterized RTL component are committed in `33a5241`.
- The scheduler now owns real shared-memory regions at admission and couples accepted requests, tagged response consumption, barrier exclusion, terminal cancellation/drain, and reset to wave eligibility and resource lifetime.
- The focused scheduler executable and focused CTest passed; strict GCC with `-Wconversion -Wsign-conversion -Werror` passed; the complete CTest suite passed 23/23.
- Public hygiene, repository integrity, design consistency, their negative controls, and Markdown link checks passed. The Windows validation runner then stopped because `cmake.exe` is unavailable on Windows PATH; the WSL CMake build and CTest suite passed.
- The recorded hosted successes are for earlier baseline `d8be39e`; the exact hosted lookup for `33a5241` returned no check runs, so no hosted success is claimed for either that commit or the current uncommitted candidate.

## Contract

- Complete-workgroup admission transactionally reserves both pooled VGPR state and one shared/local-memory region. A failed region or VGPR reservation leaves neither resource allocated.
- Shared-memory capacity fragmentation is reported distinctly from aggregate capacity exhaustion.
- Only an admitted, issuable wave may submit a local-memory request. Acceptance adds a memory wait separate from barrier arrival and execution-busy state.
- A wave remains non-issuable until its response is consumed. A barrier arrival attempted during that wait is rejected; other waves and workgroups remain issuable.
- Terminal waves cancel response delivery but retain VGPR and workgroup-local memory ownership until accepted service drains. Workgroup-local memory is released only after all waves' execution and memory operations are quiescent.
- Reset destroys all memory allocations, transactions, responses, and scheduler wait state.

## Implementation and validation sequence

1. [x] Add failing scheduler tests for real region admission, fragmented rollback, memory-wait issue blocking, barrier interaction, response consumption, terminal drain, and reset.
2. [x] Integrate the memory object with transactional admission and workgroup resource release.
3. [x] Add scheduler memory-request, service, and response-consumption APIs; represent memory waiting separately from barrier waiting and execution busy.
4. [x] Extend invariants and deterministic mixed scheduler/memory sequences to catch leaked ownership and blocked waves.
5. [x] Run focused tests, strict GCC, all CTest targets, the full RTL gate, and the affected documentation/design gates; review the coherent checkpoint. The Windows wrapper's missing `cmake.exe` is an environment limitation, with equivalent WSL build/CTest evidence recorded above.
6. Next dependency: connect shared/local-memory allocation and wait state to RTL workgroup admission, then add LSU integration as a separate vertical slice.

## Evidence boundary

Passing C++ tests establish this executable scheduler/reference behavior only. They do not establish RTL scheduler/LSU integration, exact hosted checks, synthesis, timing, area, power, or physical behavior.
