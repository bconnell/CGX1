# Project Status

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [Validation](VALIDATION.md) · [Roadmap](ROADMAP.md)

CGX 1 is an engineering architecture and prototype program. No custom CGX 1 ASIC has been fabricated.

## Current repository contents

| Area | Current state | Evidence in this repository |
|---|---|---|
| Architecture | Defined target | [Engineering Specification](ENGINEERING_SPEC.md) and [machine readable design file](../design/cgx1_architecture.json) |
| ISA/execution model | Defined architecture + executable base encoder/decoder | [ISA](ISA.md) and [source/isa](../source/isa/) |
| Graphics pipeline | Defined architecture target | [Graphics Pipeline](GRAPHICS_PIPELINE.md) |
| Texture/compression | Defined architecture target | [Texture and Compression](TEXTURE_COMPRESSION.md) |
| Chiplet fabric/coherence | Defined architecture target; physical lane map not frozen | [Chiplet Fabric](CHIPLET_FABRIC.md) |
| Virtual memory | Defined architecture target | [Virtual Memory](VIRTUAL_MEMORY.md) |
| Scheduling/preemption | Defined architecture target | [Scheduling and Preemption](SCHEDULING_PREEMPTION.md) |
| Mechanical envelope | Defined target | OpenSCAD card/dock sources, SVG blueprint, STL envelope models, [Mechanical Design](MECHANICAL_DESIGN.md) |
| Analytical model | Executable | FP32 arithmetic, coolant rise, junction estimate, power efficiency, fit calculations |
| Power state controller | Executable reference | C implementation and fault state tests |
| Per-tile power management | Defined architecture + executable policy/invariant model | [Power Management](POWER_MANAGEMENT.md) and [source/power](../source/power/) |
| RTL | Top level scaffold | Power state and tile enable boundary only |
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

## Evidence labels used in this repository

| Label | Meaning | Example |
|---|---|---|
| **Target** | Intended design value | 360 W P4 board limit |
| **Analytical** | Result of equations or an executable analytical model | 3.45 °C coolant rise at the stated assumptions |
| **Prototype measured** | Instrumented P0 or P1 result | Future coolant inlet/outlet measurements |
| **Surrogate measured** | Result from non CGX programmable hardware | Future Alveo bench result |
| **Silicon measured** | Result from fabricated CGX hardware | Not available yet |
