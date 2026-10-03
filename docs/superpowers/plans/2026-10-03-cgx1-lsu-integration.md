# CGX1 LSU and Memory-Wait Integration Plan

## Outcome

Connect decoded wave32 load/store requests to the existing workgroup-owned shared/local-memory region and to a decoupled global-memory request/response boundary. Keep at most one outstanding memory instruction per resident wave while allowing different resident waves to wait concurrently. Memory identity and activity remain live through result writeback, store completion, fault reporting, or terminal drain.

This slice does not assign a new base-ISA memory encoding. The ISA document defines a Memory instruction class but does not define its operand encoding or opcode assignments. The LSU boundary therefore receives an already-decoded operation with lane byte addresses and captured store words. Translation, caches, atomics, fences, subword accesses, compiler/runtime dispatch, and physical memory are outside this slice.

## Current state

- `CuSharedLocalMemory` and `ComputeUnitWorkgroupScheduler` already provide an executable reference for workgroup-private memory, tagged responses, one request per wave, issue blocking, barrier membership, cancellation drain, and quiescent release.
- The RTL workgroup frontend owns the real contiguous local-memory region, but ties the allocator's request/response/cancel ports off.
- The vector execution frontend implements integer arithmetic only. Its 4-bit vector opcode values above 7 fault as illegal; memory encodings are not defined there.
- The pooled VGPR subsystem has one ordinary write path. LSU load writeback must share that path with vector results and keep response data stable under backpressure.
- The workgroup barrier tracker exports the physical-slot-to-workgroup mapping and retains surviving waves in barrier membership while other waves wait.

## Contract for this slice

- Accept one decoded memory operation per resident wave at a time. Capture workgroup ID, physical wave slot, operation kind, global/local space, active mask, all lane byte addresses, all store words, and load destination at the acceptance edge.
- Local byte addresses are offsets into that wave's current workgroup allocation. Route them through the existing `cgx1_cu_shared_local_memory`; preserve its whole-request alignment/range validation and cancellation-drain behavior.
- Global addresses are opaque byte addresses at a ready/valid downstream boundary. Requests carry workgroup ID, physical wave slot, reset epoch, 64-bit transaction tag, access kind, active mask, addresses, and store data. Responses return the same identity, lane data, and a fault code. No cache, MMU, HBM, timing, area, power, or physical-memory behavior is asserted.
- The LSU permits only one active memory operation per wave. A memory request cannot overtake an earlier same-wave vector or matrix operation. While a load waits, its destination register remains in the vector dependency scoreboard; dependent vector operations stall while independent vector operations and unrelated waves can continue. Matrix requests from a memory-waiting wave remain conservatively blocked because the current matrix path has no memory-destination scoreboard input. The LSU retains a load destination until successful VGPR writeback and keeps captured store data and wave ownership until response and completion.
- A load response writes its active lanes through the pooled VGPR ordinary-write port. Response consumption follows that port's ready signal. A fault response never writes the destination and is reported with workgroup, wave, tag, code, and lane identity before the wave is terminated as faulted. Every wave with a pending terminal fault remains non-issuable while fault delivery is backpressured.
- Local requests are cancelled on wave termination or group abort, with the wave held until the local allocator reports that its accepted transaction drained. An unpresented global request is dropped on termination. Once global `valid` has been presented while `ready` is low, the captured request remains stable through handshake; its killed wave stays allocated until the matching response drains. Killed waves discard returned data and faults.
- Responses are consumed only when identity matches the outstanding record. The external reset authority advances `global_memory_epoch` whenever LSU reset can leave older global responses in flight. A late response from an older epoch is consumed and discarded. Epoch values are not reused while such responses can still arrive.
- LSU wait/busy state participates in issue masking, barrier arrival quiescence, final VGPR release, and final shared/local-region release. A memory-waiting wave remains live barrier membership until normal completion or terminal fault/kill.

## Implementation and validation sequence

1. [x] Add a focused RTL LSU regression for captured request state, local/global routing, backpressure, per-wave waits, writeback, store completion, faults, cancellation, reset epochs, stale responses, and deterministic lifecycle stress.
2. [x] Implement the LSU transaction table and local-memory request/response/cancel handshake.
3. [x] Add the global ready/valid request/response interface, reset epoch and tags, and reject unmatched/stale responses.
4. [x] Integrate LSU writeback with the pooled VGPR ordinary-write port and LSU state with issue, dependency scoring, barriers, faults, abort, and quiescent release.
5. [x] Add integrated workgroup-frontend tests for region reuse, same-wave ordering, sibling progress, barriers, kill/abort, faults, and memory-gated release.
6. [x] Run focused LSU and workgroup tests, full `scripts/validate_rtl.sh`, all CTest targets, Windows repository hygiene/consistency/link checks, and negative controls. The Windows wrapper stopped at its unavailable local `cmake.exe`; WSL CMake/CTest passed. Commit and exact-revision hosted RTL/Windows CI both passed.
7. [x] Keep the fixed P1/P2 tile mapping versus power-policy mismatch recorded; defer RTL power-manager work until this LSU slice is integrated and validated.

## Local evidence

- Focused Icarus LSU and authoritative workgroup frontend regressions passed after the final RTL changes.
- Full `scripts/validate_rtl.sh` passed, including the LSU and shared/local-memory benches.
- WSL CMake build completed and CTest passed all 23 targets.
- The Windows validation wrapper passed hygiene, repository integrity, design consistency, negative-control, and Markdown-link checks; it could not configure CMake because `cmake.exe` is not on Windows PATH.
- Commit `2de4a188e9d925d4fd74b45308d6b719c2980c79` passed [RTL CI run 37142609707](https://github.com/bconnell/CGX1/actions/runs/37142609707) and [Windows CI run 37142609735](https://github.com/bconnell/CGX1/actions/runs/37142609735).

## Evidence boundary

Local executable and RTL tests establish only the behaviors they exercise in the reference model and simulated RTL. The global boundary is an abstract ready/valid transaction interface. This slice provides no evidence about translation, caches, HBM, system ordering, latency, throughput, physical implementation, timing, area, power, or silicon.
