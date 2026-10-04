# Instruction Fetch and CU PC Integration

[Documentation index](README.md) · [ISA and execution model](ISA.md) · [Decoded control flow](CONTROL_FLOW.md) · [Validation](VALIDATION.md)

## Boundary

`cgx1_compute_workgroup_execution_frontend` can enable a per-wave instruction fetch unit with an abstract ready/valid request/response boundary. The unit receives the current PC from `cgx1_wave_control_flow`, the committed resident-slot-to-workgroup mapping from the workgroup residency authority, and the current `memory_epoch`. The control-flow unit remains the only owner of architectural per-wave PCs.

Each request captures the workgroup ID, resident wave slot, epoch, a transaction tag, and the full 57-bit virtual PC. A round-robin request port holds all fields stable while `valid` is asserted and downstream `ready` is low. The unit permits one queued, outstanding, buffered, or fault-pending fetch per wave while different waves can wait concurrently.

Responses carry the same complete identity plus one 32-bit base word and a completion fault code. The response boundary accepts each response; a response with no exact outstanding match is discarded. A matching successful response is buffered for its wave until decode/consumer acceptance. A matching nonzero fault code becomes a terminal-wave fault with the captured identity. Responses may complete in a different order from requests.

## Wave lifecycle and release safety

Fetch-request and response-wait states block issue from that wave but do not alter its live wave or workgroup barrier membership. Sibling waves remain eligible. Buffered instructions are available to decode and issue; their local ownership still blocks wave-slot and workgroup-region release until the word is consumed. Fault state blocks issue until the normal terminal path accepts it.

A word buffered for a wave that is killed, terminated, or aborted is discarded. An instruction request already presented under ready/valid remains stable until accepted, even if its wave is killed while downstream is stalled. Once accepted, the request owner stays resident until a matching response is drained; data and faults for a no-longer-live wave are discarded. There is no fetch-cancel channel in this slice.

Reset clears the local fetch table and tags. The external epoch authority must advance the execution epoch, or guarantee that the downstream instruction service has drained/flushed old responses, before slots are reused after reset. Epoch values must not be reused while a pre-reset response can still arrive. A mismatched or stale response is consumed without changing a newly allocated wave's state.

## Decode and PC acceptance

When enabled, successful fetched base words feed the existing `cgx1_vector_instruction_word_decoder` and resident vector execution path. The current provisional Vector-class base-word format is 32 bits; a vector instruction advances its wave PC by four only when the existing vector request is accepted. Advancing from the final aligned 57-bit PC faults through the existing invalid-PC terminal path instead of wrapping to zero. Internal opcode assignments remain provisional.

Other instruction classes are exposed as the raw word/class plus the generic base fields (opcode, destination, source 0, and source 1) and captured workgroup, wave, epoch, tag, and PC. These fields follow the existing 32-bit base-word layout; their class-specific interpretation remains with the external handler. The handler holds its ready handshake low until it accepts the word and supplies the existing per-wave sequential-PC metadata; that accepted handshake advances the control-flow-owned PC. A decoded control event accepted for the same wave retains control-flow authority over the sequential update. This boundary does not assign control or memory opcodes, extension-word lengths, execution semantics, or a compiler contract. The standalone word decoder remains stateless; request/response ownership and PC authority belong to the workgroup frontend and this fetch unit.

The fetch interface carries GPU virtual PCs. It establishes neither execute-page permission enforcement nor address translation, caches, physical instruction memory, runtime dispatch, or an end-to-end shader execution environment. The current default frontend parameter leaves fetch disabled unless a consumer enables and connects the boundary.

## Validation

`cgx1_instruction_fetch_unit_tb.sv` covers captured request identity, downstream request backpressure, concurrent wave waits, out-of-order responses, mismatched/stale response rejection, buffered-word backpressure, fault retention, kill/drain, reset with an outstanding request using a new epoch, slot reuse, and fixed-seed lifecycle stress. The authoritative workgroup frontend bench composes dispatch PC and workgroup ownership, fetch request/response, the existing word decoder and vector execution path, accepted PC advance, sibling progress, fault retirement, and resource release held until an aborted request drains.

These benches establish only the simulated boundary and paths they exercise. They do not establish cache, MMU, physical-memory, timing, area, power, full ISA, top-level GPU, hosted-CI, synthesis, or silicon behavior.
