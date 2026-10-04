# CGX1 RTL Command Queue Rings — First Integration Slice

## Goal and boundary

Add bounded per-context byte rings in front of the existing RTL command packet parser and one-CU workgroup dispatcher. Preserve registered queue identity and byte positions while accepting streamed command bytes, skip incomplete packets from other contexts without head-of-line blocking, and consume ring bytes only after the parser/dispatcher has accepted the complete command outcome.

This is the first RTL ring/feeder integration. It does not add multi-CU placement, global tile arbitration, queue-context reuse/unregistration, full queue cancellation, final workgroup-retirement completion, or a frozen command ABI. A ring recovery operation clears parser fault state and discards unread ingress bytes; it does not cancel a descriptor already held by the parser or accepted by the CU dispatcher.

## Source contracts

- The queue-context namespace is 64 IDs. This RTL registration boundary captures process ID, address-space ID, priority, and incarnation; parser fault state is tracked separately. Engine-class/graphics routing is outside this slice.
- The C++ reference uses 4,096 bytes per context by default, caps a context at 65,536 bytes, and caps aggregate ring storage at 4 MiB. The RTL mirrors these as parameter defaults and bounds, not as a frozen hardware ABI or SRAM implementation claim.
- The v1 packet remains provisional. Its 12-byte envelope and little-endian workgroup descriptor are defined by `source/model/command_queue_runtime.hpp` and the existing RTL parser.
- CU admission and parser-error completions remain separate interfaces. CU admission is not final workgroup completion.

## RTL contract

`cgx1_compute_workgroup_command_queue_frontend.sv` owns a parameterized set of byte rings and registered context metadata, and feeds one existing `cgx1_compute_workgroup_command_packet_parser.sv` instance. Its command ingress accepts one byte per ready/valid transfer with a 6-bit context ID. Writes are accepted only for registered, nonfaulted contexts with ring space and producer-position capacity. The ring reports registration state, parser fault state, unread byte counts, and monotonically increasing producer/consumer byte positions.

Context registration captures process ID, address-space ID, and priority and assigns a monotonically increasing 64-bit queue-incarnation ID. A context ID can be registered once per device reset in this slice; safe unregister/reuse requires tracking accepted workgroups through final quiescent retirement and remains open.

The feeder chooses complete or untrustworthy frames in round-robin context order. A structurally valid envelope is not fed until its full declared packet is resident, so an incomplete command in one context cannot prevent another complete context from progressing. Untrustworthy envelopes are offered once enough header bytes are present so the parser can fault the captured context. The ring consumer pointer remains pinned during parser input and downstream backpressure. A valid packet advances the consumer only when the CUDS accepts its decoded descriptor. A trustworthy malformed/unsupported/rejected packet advances by the declared length only when its parser completion is accepted. An untrustworthy packet does not advance the consumer.

`ingress_recovery_valid/context_id` is accepted only when that context is not the active parser transaction and has no parser output still held for it. Recovery advances that ring's consumer to its producer and pulses the existing parser-local recovery input. Scheduler-owned descriptors remain unaffected. This is not the C++ reference's queue reset/cancellation operation.

The frontend's decoded-submit interface connects to one CU-local dispatch scheduler in the integration bench. That scheduler remains the authority for tile eligibility, weighted dispatch, and whole-workgroup admission. This slice does not wire the ring frontend into `cgx1_top`, and it makes no timing, area, SRAM, power, or physical-memory claim.

## Acceptance

- Register distinct contexts and verify process/address/priority/incarnation capture and duplicate rejection.
- Stream bytes into independent rings with gaps and changing live sidebands; only registered identities may enter descriptors.
- Prove a partial packet in one context does not block a complete packet in another.
- Prove round-robin progress among ready contexts and preserve per-context packet order.
- Exercise ring-full backpressure, physical wrap, long producer/consumer positions, and consumer commit only after parser/dispatcher handshake.
- Consume complete unsupported and malformed frames; pin unread bytes and fault only the captured context for an untrustworthy envelope.
- Recover parser/ring ingress while preserving descriptors already owned by the CU dispatcher.
- Hold decoded descriptor output under dispatcher backpressure and preserve metadata until accepted.
- Verify reset while unread ring bytes and dispatcher-owned descriptors exist.
- Run deterministic seeded byte gaps, parser stalls, multiple contexts, recovery, and repeated wrap; check occupancy and position invariants.
- Run the full Icarus RTL gate, C++/CTest regression, repository integrity/design checks, Windows wrapper, JSON validation, and exact-candidate fingerprinting.
