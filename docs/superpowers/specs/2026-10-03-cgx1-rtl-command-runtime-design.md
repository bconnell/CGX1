# CGX1 RTL Command Packet Ingress Design

## Goal and boundaries

Add a synthesizable RTL byte-stream parser for the provisional little-endian v1 workgroup-dispatch packet already implemented by `source/model/command_queue_runtime.hpp`. The parser holds complete descriptors under downstream ready/valid backpressure and feeds the existing CU dispatch scheduler. The packet remains a reference candidate; this work does not freeze a public queue ABI.

This slice does not add per-context hardware rings, the I/O-die global queue manager, graphics packets, compiler/runtime submission, or command tracking through final workgroup retirement. The existing CU scheduler's completion remains an admission result. Parser-level malformed/unsupported/fault completions and scheduler admission results remain separately signaled; a later runtime layer must arbitrate them and connect final retirement.

The parser parameters are `RESIDENT_WAVE_SLOTS=8`, `WORKGROUP_ID_WIDTH=64`, `MAX_PACKET_BYTES=4096`, `VIRTUAL_ADDRESS_WIDTH=57`, and a derived wave-count width sufficient to represent `RESIDENT_WAVE_SLOTS`. The workgroup-ID counter starts at the top bit of the configured width and increments monotonically without wrap. A test-only `INITIAL_WORKGROUP_ID` parameter may set the initial ID near exhaustion.

## Packet and stream contract

The parser accepts one byte per ready/valid transfer through `command_valid`, `command_ready`, and `command_data[7:0]`. `command_start` identifies the first byte of a packet; `command_queue_context_id[5:0]`, `command_process_id[63:0]`, `command_address_space_id[63:0]`, `command_priority[2:0]`, `command_queue_incarnation_id[63:0]`, and `command_packet_byte_position[63:0]` are sampled only on that accepted first byte. The parser never depends on sideband or byte inputs remaining stable after acceptance. `queue_reset_valid` with `queue_reset_context_id[5:0]` clears that queue's parser fault state and abandons a partial packet from that context.

The provisional packet layout is unchanged:

- 12-byte header: `CGX1` magic, u16 opcode, u8 version, zero u8 flags, and u32 total byte length.
- 32-byte fixed payload prefix: u64 submission token, u64 entry PC, u16 wave count, u16 scalar/predicate units per wave, u32 shared/local bytes, u32 other workgroup state units, and a zero u32 reserved word.
- One 8-byte record per wave: nonzero u32 live-lane mask, u16 VGPR count in 1..256, and a zero u16 reserved word.
- Exact packet size: `44 + 8 * wave_count`; all numeric fields are little-endian.

The default maximum packet is the C++ reference's default 4,096-byte ring capacity. The parser streams and validates records rather than buffering an arbitrary packet. It stores at most `RESIDENT_WAVE_SLOTS` wave records for dispatch, while still consuming and validating all records in an otherwise well-framed oversized workgroup packet.

## Decode and identity behavior

- A bad magic, impossible/over-limit/unaligned length, or exhausted internal workgroup-ID sequence faults the captured queue context. The input source must stop that context and use queue reset to discard or replace the unframed bytes.
- A nonzero flags byte, unsupported opcode/version, or malformed payload with a trustworthy complete length is consumed through the declared packet boundary and reported without faulting the queue. Following packets remain available.
- A structurally valid workgroup that exceeds the configured resident-wave capacity reports terminal `WorkgroupExceedsResidentWaveCapacity` admission failure; it is never truncated or partially dispatched.
- A valid descriptor is held stable until the existing scheduler accepts it. Internal workgroup IDs use the high-half sequence that the C++ reference uses, and sequence exhaustion does not wrap or reuse an ID.
- The parser carries queue context, process/address-space identity, priority, submission token, packet byte position, and queue-incarnation ID with each dispatch record. The existing scheduler stores and returns the submission token, position, and incarnation with its admission result.
- Parser-error completions preserve the captured queue identity, packet position, and incarnation. They follow the C++ decoder's token behavior: malformed envelope and unsupported opcode/version packets carry no token; reserved-flag packets carry a token when the complete declared length is at least 20 bytes; malformed v1 payloads carry the token read from the fixed prefix. Parser errors do not masquerade as scheduler admission or final workgroup-completion events.

The parser's descriptor interface is `submit_valid/submit_ready` with `submit_queue_context_id`, `submit_process_id`, `submit_address_space_id`, `submit_priority`, `submit_workgroup_id`, `submit_submission_id`, `submit_packet_byte_position`, `submit_queue_incarnation_id`, `submit_start_pc`, `submit_wave_count`, `submit_initial_live_lane_mask_flat`, `submit_vgpr_register_counts_flat`, `submit_scalar_state_units_per_wave`, `submit_shared_local_bytes`, and `submit_other_workgroup_state_units`. Its separate `parser_completion_valid/parser_completion_ready` interface carries `parser_completion_queue_context_id`, `parser_completion_process_id`, `parser_completion_address_space_id`, `parser_completion_submission_id_valid`, `parser_completion_submission_id`, `parser_completion_packet_byte_position`, `parser_completion_queue_incarnation_id`, `parser_completion_workgroup_id`, `parser_completion_status`, and `parser_completion_failure`. Parser completion status values are `0 AdmissionRejected`, `1 UnsupportedCommand`, `2 MalformedPacket`, and `3 QueueFaulted`; non-admission parser errors use failure code zero. `queue_faulted_mask[63:0]` reports parser-owned queue faults. The existing CU scheduler's new `submit_submission_id`, `submit_packet_byte_position`, and `submit_queue_incarnation_id` inputs are stored and returned through corresponding `dispatch_*` and `completion_*` outputs.

## Verification

Icarus tests cover golden packet bytes, fragmented ingress, metadata changes after first-byte acceptance, descriptor field extraction, valid descriptor hold under scheduler backpressure, malformed framing and queue reset, complete framed malformed/unsupported packets followed by valid commands, oversized workgroups, invalid wave records, packet-bound bounds, ID exhaustion, parser completion backpressure, and deterministic mixed packets/stalls. An integration test connects the parser to the existing CU dispatcher and checks queue identity and packet correlation through its admission result. The existing workgroup dispatcher/frontend integration remains the evidence for downstream complete-workgroup admission; it does not turn admission into final queue completion.
