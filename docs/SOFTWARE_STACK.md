# Software Stack

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [Project status](STATUS.md) · [Validation](VALIDATION.md)

A usable GPU requires more than silicon. CGX 1 includes a software implementation plan so firmware, drivers, compilers, media support, diagnostics, and conformance can be developed alongside hardware.

Software-visible hardware behavior is defined by [ISA and Execution Model](ISA.md), [Matrix Engine Architecture](MATRIX_ENGINE.md), [Virtual Memory](VIRTUAL_MEMORY.md), and [Scheduling and Preemption](SCHEDULING_PREEMPTION.md). Driver and compiler work must not invent incompatible behavior outside those contracts.

## Firmware

Initial firmware responsibilities:

- board identity and revision;
- reset and clock sequencing;
- PCIe negotiation;
- external dock detection;
- power state control;
- thermal and flow monitoring;
- fault logging;
- firmware update and recovery;
- diagnostic mailbox exposed to the host.

## Linux path

The initial Linux driver path should establish:

1. PCIe enumeration;
2. BAR/resource mapping;
3. interrupt handling;
4. memory allocation and mapping;
5. device reset and recovery;
6. firmware mailbox and telemetry;
7. basic display initialization;
8. Vulkan compute;
9. basic Vulkan graphics;
10. shader compiler expansion and conformance;
11. media integration;
12. ray tracing and advanced graphics.

The architecture does not require Resizable BAR for basic operation. A bounded aperture and command/memory paging path remains part of the host compatibility target.

## Windows path

The Windows path follows stable firmware and basic Linux hardware bring up.

Target work includes:

- WDDM device management;
- memory manager integration;
- reset/recovery behavior;
- display miniport work;
- Direct3D 12 user mode driver;
- Vulkan user mode support;
- media encode/decode interfaces;
- shader compiler integration;
- diagnostics and crash collection.

## Graphics and compute APIs

Initial targets:

- Vulkan;
- Direct3D 12;
- OpenCL or another open compute interface where practical;
- platform media APIs for AV1, HEVC, and H.264;
- development diagnostics and profiling interfaces.

CUDA compatibility is not claimed.

## Command and queue ABI

The driver/runtime queue ABI maps logical queues onto the 64 resident hardware queue contexts described in [Scheduling and Preemption](SCHEDULING_PREEMPTION.md). Queue state carries process/address-space identity, priority, engine class, fault state and command-ring position.

`source/model/command_queue_runtime.hpp` now implements a bounded executable reference boundary with a provisional little-endian v1 workgroup-dispatch packet. Its 12-byte envelope contains the `CGX1` magic, u16 opcode, u8 version, u8 zero flags, and u32 total length. The fixed 32-byte payload prefix contains a u64 queue-local submission token, u64 entry PC, u16 wave count, u16 scalar/predicate units per wave, u32 shared/local-memory bytes, u32 other workgroup state units, and a u32 zero reserved word. Each 8-byte wave record contains a nonzero u32 lane mask, u16 VGPR count in 1..256, and a u16 zero reserved word. The exact packet size is `44 + 8 * wave_count`; entry PCs are 4-byte aligned and below `2^57`.

The reference validates packet framing and payloads, retains incomplete byte streams, applies per-context ring backpressure, and feeds the existing CU dispatch scheduler while preserving registered queue identity and terminal completion correlation. Each queue registration receives a monotonic incarnation ID carried through dispatch and completion, so unregister/re-register cannot alias an earlier completion key. Its default byte ring is 4,096 bytes per context, capped at 65,536 bytes per context and 4 MiB total ring storage; retained tracked workgroups default to 512 and are capped at 1,024. These are reference-model policies, not a hardware ring contract. The packet format is a testable candidate only, not a frozen driver/runtime ABI.

`source/rtl/cgx1_compute_workgroup_command_packet_parser.sv` decodes that provisional workgroup packet from a bounded ready/valid byte stream. It captures context/process/address/priority/incarnation/position metadata only with the accepted first byte, consumes trustworthy framed malformed or unsupported packets through their declared boundary, and faults only the captured queue when framing is untrustworthy. Valid descriptors are held until the existing CU dispatcher accepts them; parser errors use a separate completion interface, and dispatcher completion remains the CU admission result. `source/rtl/cgx1_compute_workgroup_command_lifecycle.sv` separately retains accepted command identity through final quiescent workgroup retirement and reports terminal admission, cancellation, or completion status. The RTL queue frontend now provides reset, cancellation, drain, unregister, and incarnation-safe re-registration; it finishes an already-owned parser frame, waits for resident resource and memory-request drain, reports the old incarnation and discarded byte interval, and holds the reset response until acknowledged. `parser_recovery_*` remains ingress-only and does not cancel complete descriptors owned downstream. The packet's 32-bit other-workgroup-state field remains 32 bits through pending storage, frontend admission, and barrier resource accounting. The ring/parser/lifecycle path is simulated through one real workgroup frontend but is not connected to `cgx1_top`; the I/O-die global queue manager, frozen public ABI, graphics packets, kernel/object loader, grid/argument ABI, compiler lowering, and runtime API integration remain open.

## Compiler work

The compiler targets the native wave32 ISA in [ISA and Execution Model](ISA.md) and must eventually cover:

- shader front ends and intermediate representation;
- instruction selection for the CGX execution model;
- register allocation;
- scheduling;
- memory operations and synchronization;
- wave/workgroup lowering;
- graphics stage lowering;
- ray tracing operations;
- matrix operations;
- debug information;
- reproducible conformance failures.

Matrix lowering must consume advertised component types, scope, dimensions or granularities, layouts, and modifiers from the device capability contract. Software must not assume one universal physical matrix tile shape.

## Media path

The architecture target includes four encode and four decode engines. Software work must expose only functions implemented by the finished media hardware and verified against the relevant codec and platform requirements.

## Local model workloads

CGX 1 is intended to support local model inference and development workloads through its large memory capacity and general compute path. The architecture now defines theoretical dense matrix arithmetic targets, but it still does not publish an independent AI TOPS benchmark figure. No inference speed claim is made without implemented matrix hardware, compiler support, and measured software results.

## Conformance and compatibility

A shipping implementation requires:

- Vulkan conformance;
- Direct3D/WDDM qualification appropriate to the final Windows driver;
- display link compliance;
- media codec validation;
- reset and recovery testing;
- game and application compatibility;
- long duration workload testing.

See [Validation](VALIDATION.md) for the evidence expected at each hardware stage.
