# Project Status

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [Validation](VALIDATION.md) · [Roadmap](ROADMAP.md)

CGX 1 is an engineering architecture and prototype program. No custom CGX 1 ASIC has been fabricated.

## Current repository contents

| Area | Current state | Evidence in this repository |
|---|---|---|
| Architecture | Defined target | [Engineering Specification](ENGINEERING_SPEC.md) and [machine readable design file](../design/cgx1_architecture.json) |
| ISA/execution model | Defined architecture + executable base encoder/decoder | [ISA](ISA.md) and [source/isa](../source/isa/) |
| Matrix engine architecture | Defined numeric + physical execution contract with executable numeric, fragment, register-interface schedule, and bank-conflict references | [Matrix Engine Architecture](MATRIX_ENGINE.md) and [source/matrix](../source/matrix/) |
| Graphics pipeline | Defined architecture target | [Graphics Pipeline](GRAPHICS_PIPELINE.md) |
| Texture/compression | Defined architecture target | [Texture and Compression](TEXTURE_COMPRESSION.md) |
| Chiplet fabric/coherence | Defined architecture target; physical lane map not frozen | [Chiplet Fabric](CHIPLET_FABRIC.md) |
| Virtual memory | Defined architecture target | [Virtual Memory](VIRTUAL_MEMORY.md) |
| Scheduling/preemption | Defined architecture target | [Scheduling and Preemption](SCHEDULING_PREEMPTION.md) |
| Mechanical envelope | Defined target | OpenSCAD card/dock sources, SVG blueprint, STL envelope models, [Mechanical Design](MECHANICAL_DESIGN.md) |
| Analytical model | Executable | FP32 arithmetic, coolant rise, junction estimate, power efficiency, fit calculations |
| Power state controller | Executable reference | C implementation and fault state tests |
| Per-tile power management | Defined architecture + executable policy/invariant model | [Power Management](POWER_MANAGEMENT.md) and [source/power](../source/power/) |
| RTL | Limited control/storage/arithmetic RTL | Power-state/tile-enable scaffold, matrix control/staging, signed INT8 arithmetic/path, validated one-wave shell, plus parameterized resident-wave arbitration, wave-local dependency, scoreboard routing, and ordinary issue-admission RTL validated by the repository RTL simulation gate; FP16/BF16/FP8 arithmetic and physical implementation remain open |
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

Matrix tile shapes, fragment mapping, opcode assignments, per-engine issue interval, and theoretical dense arithmetic targets are frozen as architecture targets. The current peak-clock targets are 1,146.88 TFLOPS for FP16/BF16 and 2,293.76 TFLOPS/TOPS for FP8/INT8. These are not measured silicon results. The matrix register-interface schedule, modulo-8 bank-class conflict rules, pending-destination interlocks, capture-to-active operand staging, output-result staging, and per-wave ordinary VGPR hazard checks are executable and simulated where applicable. Signed INT8 functional arithmetic has passed the standalone RTL simulation gate. Capture/execute/result/writeback integration has also passed the repository RTL simulation gate, while FP16/BF16/FP8 arithmetic remains open. Resident-wave identity, wave-local matrix dependencies, round-robin request selection, per-wave scoreboard routing, and ordinary issue admission are implemented in the resident-engine RTL boundary and have passed the repository RTL simulation gate. The pooled-VGPR implementation now also has an ordinary-vector path: exact-count ordinary reads/writes, serialized distinct same-bank source reads, a shared matrix/vector/restore port arbiter, release safety across both execution classes, a wave32 INT32 ADD/SUB/AND/OR/XOR/SHL/LSR/ASR pipeline, resident-wave round-robin vector selection with non-power-of-two slot coverage and invalid-width rejection, and matrix/vector hazard and issue guards. The current local working-tree candidate passes `scripts/validate_rtl.sh` with Icarus 12.0 in Ubuntu WSL and the Release CTest suite (21/21) with GCC 13.3. The Windows validation wrapper passed repository hygiene, design-consistency, and local-link checks but could not reach its build step because `cmake.exe` is not available on Windows PATH; the available WSL toolchain completed the equivalent CMake/CTest build. These are local software/simulation results, not published CI or physical implementation evidence. The internal vector opcode encoding and mixed-workload admission policy are not frozen ISA commitments. Foundry storage-macro selection, full compute-unit integration, physical arithmetic organization, timing closure, area, and power remain unvalidated. No independent AI TOPS benchmark value or structured-sparsity multiplier is claimed.

A mixed resident execution frontend now composes the signed INT8 matrix engine and resident INT32 vector pipeline over the same unified pooled-VGPR authority. Legal matrix requests require pooled initialization/range preflight and clear live-vector dependency locks; malformed matrix requests still reach the existing controller-owned illegal path. The selected vector request uses per-wave matrix scoreboard dependencies, and one edge cannot accept both a matrix and vector instruction. The mixed frontend passes its RTL integration test in the current local candidate. A full compute-unit scheduler spanning memory waits, barriers, faults, dispatch, and retirement is still open; the standalone resident-vector boundary also retains an external dependency-ready contract.

## Evidence labels used in this repository

| Label | Meaning | Example |
|---|---|---|
| **Target** | Intended design value | 360 W P4 board limit |
| **Analytical** | Result of equations or an executable analytical model | 3.45 °C coolant rise at the stated assumptions |
| **Prototype measured** | Instrumented P0 or P1 result | Future coolant inlet/outlet measurements |
| **Surrogate measured** | Result from non CGX programmable hardware | Future Alveo bench result |
| **Silicon measured** | Result from fabricated CGX hardware | Not available yet |
