# CGX1 Instruction Fetch and CU PC Integration Plan

## Outcome

Add an abstract ready/valid instruction-memory boundary to the authoritative compute workgroup frontend. Fetch requests capture the resident wave slot, workgroup ID, external execution epoch, unique transaction tag, and current 57-bit control-flow PC. Different waves may wait concurrently; each wave has at most one outstanding fetch. Responses may return out of order and are accepted only for the complete matching identity. Fetched base words feed the existing vector-word decoder and resident vector path. Non-vector classes remain raw decoded-word handoffs because their opcode formats and semantics are not assigned.

The workgroup control-flow unit remains the sole PC authority. Fetched instruction data is held until its corresponding existing execution/control handshake accepts it. A memory-waiting/fetch-waiting wave stays resident and non-issuable, while siblings remain schedulable. Fetch transaction state gates wave/resource release until accepted requests drain or buffered words/faults are retired.

This slice does not freeze ISA opcodes or extension lengths, add branch/memory decoding, translation, instruction caches, MMU, fabric, physical instruction memory, compiler/runtime support, or physical implementation evidence.

## Current state

- `cgx1_wave_control_flow` owns one 57-bit PC and bounded control state per resident slot. The compute workgroup frontend initializes its PC from dispatch and advances it only after accepted execution/control events.
- `cgx1_vector_instruction_word_decoder` maps 32-bit Vector-class base words into the existing vector request path and passes all other classes as raw words. It currently receives words externally and does not own fetch requests, responses, tags, or PC state.
- The workgroup frontend already exports the committed slot-to-workgroup mapping, live/resident masks, issue eligibility, fault retirement, and quiescent VGPR/shared-region release arbitration.
- The global memory LSU establishes the nearby protocol precedent: capture identity and operands, retain a presented ready/valid request through backpressure, drain stale responses, and gate release on outstanding lifecycle state. Its external epoch authority must advance when reset can leave old responses in flight.
- The matrix identified `instruction_fetch_request_response_and_cu_pc_integration` as this slice. A fresh full RTL gate now passes under Ubuntu WSL. Review also caught and fixed a raw-class acceptance path that cleared the buffered word without advancing the authoritative PC; the integrated frontend regression demonstrated the defect before the fix and passes after it.

## Contract for this slice

- Fetch requests carry workgroup ID, physical wave slot, epoch, transaction tag, and captured PC. Request fields stay stable while `valid && !ready`.
- One wave may have one queued, outstanding, buffered, or fault-pending fetch at a time. Different resident waves may have independent outstanding fetches.
- A response carries the full request identity, one 32-bit base word, and a zero/nonzero completion fault code. Responses with no exact outstanding match are consumed and discarded. Successful words are held until the decoder/consumer accepts them.
- Kill, termination, and workgroup abort discard buffered words and reject late responses. A request already presented remains stable until accepted; accepted requests remain quiescence-active until a matching response drains. Reset clears local state; the external epoch source must not reuse an epoch while pre-reset responses can still arrive.
- Fetch wait and pending-fault state block same-wave issue. Buffered instructions are eligible for decode/issue, but remain release-active until consumed. Other waves remain eligible.
- A fetched Vector-class base word enters the existing decoder and execution frontend. For this currently fixed 32-bit base-word subset, accepted vector work advances the authoritative PC by four. The last aligned 57-bit address produces the existing invalid-PC terminal path instead of wrapping to zero.
- Other classes expose captured raw word and identity. The external decoder/handler supplies the existing acceptance and sequential-PC metadata; no opcode or extension-word policy is invented here.
- Fetch faults use the normal workgroup terminal-wave path and retire barrier membership/resources only after the fault is accepted and all fetch activity is quiescent.

## Implementation and validation sequence

1. [x] Add a focused fetch RTL bench first, covering request capture/stability, independent outstanding waves, out-of-order and stale responses, buffered-word backpressure, fault delivery, kill/abort drain, epoch-separated reset recovery, slot reuse, unaligned-PC faults, and deterministic randomized lifecycle pressure.
2. [x] Implement the per-wave fetch transaction table, request arbitration, response identity checks, instruction holding, fault events, and quiescence masks.
3. [x] Integrate fetch state with compute workgroup issue/fault/release control and connect fetched words to the existing vector decoder and vector request path behind an elaboration-time enable so current direct-decoded users remain supported.
4. [x] Add an integrated frontend regression proving dispatch PC -> request -> delayed response -> decode -> accepted vector execution and pooled-VGPR writeback -> authoritative PC advance, sibling-wave progress, raw-class handoff and handler-supplied sequential-PC acceptance, fetch-fault retirement, and final release blocked while an instruction fetch is outstanding.
5. [x] Update ISA, control-flow, status, roadmap, validation, provenance, and completeness-matrix claims with the exact boundary and remaining limits.
6. [x] Run the focused integrated frontend regression, C++ build and CTest, repository consistency/integrity/hygiene/Markdown checks, and the full RTL script. `cmake --build build -j2`, CTest (26/26), and `bash scripts/validate_rtl.sh` pass under Ubuntu WSL. The Windows wrapper passes hygiene, integrity, consistency, all included negative controls, and Markdown links, then stops at C/C++ configure because `cmake.exe` is unavailable from Windows PATH. Hosted CI was not run. Commit the reviewed local checkpoint; do not push unless separately authorized.

## Evidence boundary

RTL simulation proves only the exercised request/response, identity, state-retention, decoder, PC, and lifecycle behavior in this RTL candidate. The global instruction-memory boundary is abstract ready/valid. No claim is made about executable-page permissions in hardware, page translation, caches, physical memory, timing, area, power, throughput, hosted CI, or silicon.
