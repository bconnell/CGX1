# Software Stack

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [Project status](STATUS.md) · [Validation](VALIDATION.md)

A usable GPU requires more than silicon. CGX 1 includes a software implementation plan so firmware, drivers, compilers, media support, diagnostics, and conformance can be developed alongside hardware.

Software-visible hardware behavior is defined by [ISA and Execution Model](ISA.md), [Virtual Memory](VIRTUAL_MEMORY.md), and [Scheduling and Preemption](SCHEDULING_PREEMPTION.md). Driver and compiler work must not invent incompatible behavior outside those contracts.

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

The exact binary command-packet format remains to be frozen with the first command-processor reference model.

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

## Media path

The architecture target includes four encode and four decode engines. Software work must expose only functions implemented by the finished media hardware and verified against the relevant codec and platform requirements.

## Local model workloads

CGX 1 is intended to support local model inference and development workloads through its large memory capacity and general compute path. No independent AI TOPS figure is frozen in the architecture, and no inference speed claim is made without implemented matrix hardware, compiler support, and measured software results.

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
