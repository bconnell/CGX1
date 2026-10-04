# CGX1 Command Queue Reference Model Plan

## Baseline and scope

Baseline: clean `cgx1-completeness` checkout at `3ed83bf0d628801a8fc1bb39c60f3b86ce6d257a`, remote `bconnell/CGX1`.

Build the first executable command-processor reference boundary after the existing LSU and CU-local decoded workgroup dispatcher. A bounded per-context byte ring accepts versioned workgroup-dispatch packets, validates and decodes one packet at a time, and feeds the existing `ComputeUnitDispatchScheduler`. Preserve decoded entry PC, initial lane masks, and per-wave resource demand through admission and terminal completion. Queue process/address-space identity, priority, engine class, and fault state remain owned by the registered dispatcher context.

This is a candidate reference format, not a frozen driver ABI. It does not implement RTL command processing, global I/O-die queue management, a kernel/object loader, grid or argument ABI, graphics packets, base-ISA memory opcode decode, compiler lowering, or multi-CU placement.

## Candidate packet format

Version 1 uses little-endian fields and a fixed 12-byte envelope:

| Offset | Width | Field |
|---:|---:|---|
| 0 | 4 | ASCII `CGX1` magic |
| 4 | 2 | packet opcode |
| 6 | 1 | packet version |
| 7 | 1 | flags, required zero |
| 8 | 4 | total packet bytes, including header |

The workgroup-dispatch payload has a 32-byte fixed prefix followed by one 8-byte record per wave. The prefix carries a queue-local submission token, 57-bit aligned entry PC in a 64-bit field, wave count, scalar/predicate state units per wave, shared/local byte demand, other workgroup state units, and a zero reserved word. Each wave record carries a nonzero 32-bit initial lane mask, a 1-256 architectural VGPR count, and a zero reserved word. The exact packet size is `44 + 8 * wave_count` bytes. Process and address-space identity are never packet-controlled.

The format is explicitly provisional. Reserved fields must be zero. An unknown opcode/version in a structurally valid envelope is consumed and reported as unsupported. A malformed but well-framed known packet is consumed and reported as rejected. An invalid envelope whose next boundary cannot be trusted faults that queue and pins its consumer position until explicit queue reset.

## Ownership and lifecycle

- The reference command processor borrows one `ComputeUnitDispatchScheduler`; it does not create a second workgroup admission, fairness, tile-eligibility, or resource-ownership authority.
- Each registered queue has a bounded byte ring. Writes are all-or-nothing, may arrive in fragments across calls, support physical wrap, and never overwrite unread bytes. Packet parsing does not consume an incomplete packet or a valid packet that cannot yet enter the dispatcher's bounded FIFO.
- A valid packet receives a processor-generated CU-local workgroup identity. The exact decoded descriptor is retained under that identity until admission and physical retirement. Completion carries the registered context ID, packet-ring byte position, submission token, and terminal result.
- Queue reset discards undecoded ring bytes with an explicit canceled byte-range record, removes pending dispatches, and requests whole-workgroup kill for resident dispatches. Resident cancellation completion waits until the authoritative workgroup owner reports quiescent retirement.
- Ring storage, packet size, and retained descriptor count have explicit limits. This single-threaded executable model does not claim host-thread atomicity or hardware ring synchronization.

## Implementation sequence

1. Add C++ tests first for wire bytes, exact-size parsing, wrap, incomplete packets, full-ring atomicity, malformed/unsupported packets, validation limits, and queue identity.
2. Add integration tests for multiple contexts, pending FIFO backpressure, transient resource retry, permanent admission rejection, decoded-descriptor retention, terminal retirement, queue fault/reset, cancellation drain, and deterministic randomized queue/request/reuse sequences.
3. Implement the smallest codec, bounded byte ring, and command processor that passes the tests. Add queue-scoped cancellation to the existing dispatcher only if needed to preserve unrelated contexts and actual workgroup quiescence.
4. Register the focused CTest target. Run it red before implementation, then the complete C++ build/CTest, repository integrity/design/negative-control/Markdown checks, and applicable RTL regression gate because the dispatcher integration contract is shared.
5. Update software-stack, scheduling, status, roadmap, validation, RTL scope notes if needed, and the completeness matrix. Keep the candidate format and all deferred boundaries explicit.
6. Review ownership, arithmetic, bounds, reset/fault handling, exact diff, and evidence. Commit one coherent locally green checkpoint and continue to the next dependency-aware goal.

## Acceptance and evidence limits

The executable reference must prove byte-level packet semantics, bounded storage/backpressure, parser recovery, registered-context identity, scheduler admission, resource-failure classification, completion correlation, and queue reset without leaking or prematurely releasing active workgroups. Directed tests need malformed length, unsupported type/version, partial writes, physical ring wrap, queue full, duplicate/reused submission tokens, delayed resource availability, active workgroup kill, and multiple independent contexts. A fixed-seed randomized sequence must check invariants and eventual drain under continued service.

This batch can establish only reference-model and local executable integration behavior. It cannot establish a frozen public ABI, RTL behavior, hosted CI, synthesis, timing, area, power, physical implementation, or silicon behavior.

## Task 1: Finish and checkpoint the command-queue reference

The preceding baseline, packet-format, ownership, implementation, and acceptance sections define this task. Complete the test-first hardening for serialized wave-count bounds and queue-context reuse, verify fragmented and wrapped byte-stream behavior and completion-capacity backpressure, update project status and the completeness matrix, run the full local C++ and RTL gates plus applicable Windows checks, perform a whole-change review, and create one coherent local checkpoint. Keep the packet format provisional and preserve the documented P1/P2 tile-eligibility history. Do not claim a frozen ABI, hardware command processor, hosted CI, or physical evidence.
