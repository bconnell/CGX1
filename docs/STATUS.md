# Project Status

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [Validation](VALIDATION.md) · [Roadmap](ROADMAP.md)

CGX 1 is an engineering architecture and prototype program. No custom CGX 1 ASIC has been fabricated.

## Current repository contents

| Area | Current state | Evidence in this repository |
|---|---|---|
| Architecture | Defined target | [Engineering Specification](ENGINEERING_SPEC.md), [machine readable design file](../design/cgx1_architecture.json), and [subsystem completeness matrix](../design/cgx1_completeness_matrix.json) |
| ISA/execution model | Defined architecture + executable base encoder/decoder | [ISA](ISA.md) and [source/isa](../source/isa/) |
| Matrix engine architecture | Defined numeric + physical execution contract with executable numeric, fragment, register-interface schedule, and bank-conflict references | [Matrix Engine Architecture](MATRIX_ENGINE.md) and [source/matrix](../source/matrix/) |
| Graphics pipeline | Defined architecture target | [Graphics Pipeline](GRAPHICS_PIPELINE.md) |
| Texture/compression | Defined architecture target | [Texture and Compression](TEXTURE_COMPRESSION.md) |
| Chiplet fabric/coherence | Defined architecture target; physical lane map not frozen | [Chiplet Fabric](CHIPLET_FABRIC.md) |
| Virtual memory | Defined architecture target | [Virtual Memory](VIRTUAL_MEMORY.md) |
| Scheduling/preemption | Defined workgroup-boundary baseline; authoritative workgroup admission and CU-local decoded dispatch are executable and RTL-integrated; a bounded command-queue reference feeds the existing dispatcher | [Scheduling and Preemption](SCHEDULING_PREEMPTION.md), [Validation](VALIDATION.md) |
| Mechanical envelope | Defined target | OpenSCAD card/dock sources, SVG blueprint, STL envelope models, [Mechanical Design](MECHANICAL_DESIGN.md) |
| Analytical model | Executable | FP32 arithmetic, coolant rise, junction estimate, power efficiency, fit calculations |
| Power state controller | Executable reference | C implementation and fault state tests |
| Per-tile power management | Defined architecture, executable policy model, and RTL scheduler-eligibility/emergency-mask authority; physical tile-state sequencing remains open | [Power Management](POWER_MANAGEMENT.md), [source/power](../source/power/), and `source/rtl/cgx1_tile_power_manager.sv` |
| Shared/local memory | Executable scheduler reference plus integrated RTL workgroup region access and decoded per-wave LSU; memory hierarchy remains abstract | [CU Shared/Local Memory](SHARED_LOCAL_MEMORY.md), `source/memory`, `source/rtl/cgx1_cu_shared_local_memory.sv`, and `source/rtl/cgx1_compute_workgroup_lsu.sv` |
| RTL | Limited control/storage/arithmetic and scheduling RTL | P0-P4 top-level fallback with per-tile eligibility/emergency-isolation authority, matrix control/staging, signed INT8 arithmetic/path, resident-wave arbitration/dependencies, pooled VGPR path, mixed matrix/vector frontend, decoded per-wave control flow, authoritative workgroup admission/barrier, decoded per-wave LSU, and CU-local decoded workgroup dispatch; RTL packet processing, global queue/runtime integration, tile-state sequencing, FP16/BF16/FP8 arithmetic, and physical implementation remain open |
| P0 electrothermal prototype | Planned build | [Prototype Build](PROTOTYPE_BUILD.md), [Procurement](PROTOTYPE_PROCUREMENT.md), [Test Record Template](TEST_RECORD_TEMPLATE.md) |
| P1 programmable surrogate | Planned bench work | AMD Alveo U50 class HBM accelerator reference |
| Custom PCB schematic/layout | Not implemented | Board constraints exist; schematic, layout, and manufacturing files remain open work |
| Custom ASIC | Not implemented | Production RTL, verification, physical design, package implementation, and tapeout remain open work |
| Graphics driver | Not implemented | [Software Stack](SOFTWARE_STACK.md) defines the planned implementation order |
| Measured CGX performance | None | No fabricated CGX silicon exists |

## Numeric target interpretation

**143.36 TFLOPS** is an arithmetic peak target derived from 25,600 FP32 lanes, two floating point operations per FMA, and a 2.80 GHz peak clock target.

**6.6 TB/s** is a memory architecture target based on two HBM4 stacks at up to 3.3 TB/s each. It is not a sustained application bandwidth measurement.

Thermal temperatures in this repository are analytical estimates until measured on P0 hardware.

Application performance, frame rate, renderer throughput, media speed, and local model inference performance require hardware and reproducible benchmark data. They are not derived from the analytical model.

Matrix tile shapes, fragment mapping, opcode assignments, per-engine issue interval, and theoretical dense arithmetic targets are frozen as architecture targets. The current peak-clock targets are 1,146.88 TFLOPS for FP16/BF16 and 2,293.76 TFLOPS/TOPS for FP8/INT8. These are not measured silicon results. The matrix register-interface schedule, modulo-8 bank-class conflict rules, pending-destination interlocks, capture-to-active operand staging, output-result staging, and per-wave ordinary VGPR hazard checks are executable and simulated where applicable. Signed INT8 functional arithmetic has passed the standalone RTL simulation gate. Capture/execute/result/writeback integration has also passed the repository RTL simulation gate, while FP16/BF16/FP8 arithmetic remains open. Resident-wave identity, wave-local matrix dependencies, round-robin request selection, per-wave scoreboard routing, and ordinary issue admission are implemented in the resident-engine RTL boundary and have passed the repository RTL simulation gate. The pooled-VGPR implementation now also has an ordinary-vector path: exact-count ordinary reads/writes, serialized distinct same-bank source reads, a shared matrix/vector/restore port arbiter, release safety across both execution classes, a wave32 INT32 ADD/SUB/AND/OR/XOR/SHL/LSR/ASR pipeline with illegal-opcode completion before VGPR reads, resident-wave round-robin vector selection with non-power-of-two slot coverage and invalid-width rejection, and matrix/vector hazard and issue guards. An earlier local working-tree candidate passed `scripts/validate_rtl.sh` with Icarus 12.0 in Ubuntu WSL and all 23 Release CTest targets with GCC in WSL. The Windows validation wrapper's CMake step may remain unavailable because `cmake.exe` is not on Windows PATH; the available WSL toolchain completed the CMake/CTest build. These are local software/simulation results, not published CI or physical implementation evidence. The internal vector opcode encoding and mixed-workload admission policy are not frozen ISA commitments. Foundry storage-macro selection, memory and full hardware queue/runtime integration, physical arithmetic organization, timing closure, area, and power remain unvalidated. No independent AI TOPS benchmark value or structured-sparsity multiplier is claimed.

A mixed resident execution frontend composes the signed INT8 matrix engine and resident INT32 vector pipeline over the same unified pooled-VGPR authority. The workgroup layer now connects a decoded per-wave LSU boundary to that frontend and the owned shared/local region. It captures all request identity and operands, supports multiple simultaneous wave waits, arbitrates local/global requests with ready/valid backpressure, writes load lanes through the pooled VGPR path, tracks load destinations in vector dependency hazards, and retains store and fault lifecycles. Workgroup fault/kill/abort and reset paths suppress stale writeback; resource and region release wait for memory quiescence. The global boundary is abstract and carries tags plus an externally advanced reset epoch. This slice does not define memory opcode/operand encoding, caches, translation, hardware queues, runtime dispatch, or physical memory.

The tile power-policy mismatch at `cgx1_top.sv` has been resolved at the eligibility boundary: `cgx1_tile_power_manager.sv` now derives the scheduler mask from active/requested P-state limits and per-tile operating/readiness status, with immediate emergency isolation requests. No fixed P1/P2 count mapping remains. A tile-state sequencer, physical gate control, hysteresis timing, and calibrated power budget remain open.

A new executable CU workgroup reference owns the actual `ResidentWaveVgprPool`, `PooledVgprStorage`, and shared/local-memory region allocator. Admission rolls back both VGPR and memory resources when a later reservation fails. The reference and RTL retain surviving memory waiters in barrier membership and drain terminal operations before release. The integrated LSU regression additionally covers local-region reuse, vector dependency stalls and independent progress, barrier interaction with a delayed global response, pre/post-service kill, abort, fault completion, reset epochs, stale responses, and deterministic randomized reuse. The global interface remains a functional protocol model only.

The pushed checkpoint `56dde4cd92c261063d62c7019d81f6d8b4c8cc01` completed hosted RTL CI run `37091104373` and Windows CI run `37091104769` successfully on that exact SHA. This validates the committed C++ memory-scheduler integration and RTL region-allocation coupling. Later local changes, if any, require their own exact-revision runs. No synthesis, timing, area, power, physical implementation, or silicon evidence is claimed.

## Evidence labels used in this repository

| Label | Meaning | Example |
|---|---|---|
| **Target** | Intended design value | 360 W P4 board limit |
| **Analytical** | Result of equations or an executable analytical model | 3.45 °C coolant rise at the stated assumptions |
| **Prototype measured** | Instrumented P0 or P1 result | Future coolant inlet/outlet measurements |
| **Surrogate measured** | Result from non CGX programmable hardware | Future Alveo bench result |
| **Silicon measured** | Result from fabricated CGX hardware | Not available yet |

## Decoded per-wave control flow

The C++ reference and `cgx1_wave_control_flow.sv` implement 57-bit aligned PCs, live/active lane masks, branch joins, calls/returns, structured loops, lane termination, and bounded-stack faults after decode. The workgroup frontend advances PCs only after accepted operations, applies active/live masks to vector and memory requests, and resolves barrier reconvergence through the residency barrier's local-wave-to-slot mapping. Focused tests cover nested valid and malformed joins, loop call-depth unwind, protected caller returns, stack limits, accepted-PC timing, divergent vector writes, memory-wait gating, nonzero resident-slot barrier mapping, and deterministic randomized control transitions. This scope does not include fetch, opcode encoding, scalar execution, compiler lowering, runtime submission, or physical implementation. On the current local candidate, the WSL CMake build passed, CTest passed 25/25, and the full `scripts/validate_rtl.sh` gate passed with Icarus 12.0. Hosted CI and physical implementation remain unverified.

## CU-local decoded workgroup dispatch

`ComputeUnitDispatchScheduler` provides an executable reference for bounded per-context workgroup queues, process/address-space identity, eight configurable priority levels, weighted service with aging, tile-eligibility gating, and queue fault handling. It delegates all residency, resource reservation, retryable admission pressure, and workgroup retirement to `ComputeUnitWorkgroupScheduler`. The RTL `cgx1_compute_workgroup_dispatch_scheduler.sv` accepts already-decoded descriptors and preserves context identity through terminal completion; `cgx1_compute_workgroup_dispatch_integration_tb.sv` connects it to the actual workgroup frontend and verifies residency, duplicate rejection, transient resource retry, quiescent local-region release, and successful retry.

At the preceding CU-local dispatcher checkpoint (base `054c1e93bd88983e09026254c81d7dba280d6b12`), all 25 CTest targets and the full RTL script passed. Policy weights, queue depths, and aging interval are implementation defaults rather than calibrated throughput guarantees. That checkpoint established one CU's decoded compute dispatch boundary; global queue processing, command-packet ABI, graphics dispatch, multi-CU/tile placement, runtime/compiler submission and completion, and hardware performance remained open. The Windows wrapper passed hygiene, integrity, design consistency, negative-control, and Markdown-link checks, then stopped at CMake because `cmake.exe` was unavailable on Windows PATH. Hosted CI, synthesis, timing, area, power, physical implementation, and silicon evidence were not claimed.

## Bounded command-queue reference

`CommandQueueRuntime` adds a C++ reference processor for a provisional v1 workgroup-dispatch packet. It owns bounded per-context byte rings, validates and decodes complete packets, preserves identity and descriptors through admission and completion, and uses queue-scoped dispatcher cancellation for reset. Tests cover packet encoding and rejection, fragmented writes and physical wrap, byte-ring and completion-capacity backpressure, unsupported and malformed packets, queue identity reuse, resource retry, queue-scoped cancellation, quiescent completion, and deterministic randomized scheduling/reuse. The candidate has no RTL packet parser, global queue manager, public ABI freeze, loader, compiler, host runtime API, graphics packet path, multi-CU placement, hosted CI, or physical implementation evidence.

For this local candidate, the WSL CMake build and CTest passed 26/26, and `scripts/validate_rtl.sh` passed under Icarus Verilog 12.0. The Windows wrapper passed hygiene, integrity, design consistency, all negative controls, and Markdown-link checks, then stopped at CMake configuration because `cmake.exe` is unavailable on Windows PATH. Hosted CI, synthesis, timing, area, power, physical implementation, and silicon evidence are not claimed.
