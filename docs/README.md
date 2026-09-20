# CGX 1 Documentation

[Repository home](../README.md) · [Design authorship](../AUTHORS.md) · [License](../LICENSE) · [Sources](SOURCES.md)

This directory contains the public engineering documentation for CGX 1. The documents are separated by subsystem so specifications, prototype instructions, procurement, validation, and future work do not get mixed together.

## Core design documents

| Document | Scope | Start here when |
|---|---|---|
| [Engineering Specification](ENGINEERING_SPEC.md) | Card, package, compute, memory, I/O, power, display, media, reliability | You need the complete architecture |
| [Project Status](STATUS.md) | Implemented files, executable references, prototype state, missing production work | You need to know what physically exists |
| [Mechanical Design](MECHANICAL_DESIGN.md) | Card and dock envelopes, component packing, selected fans, radiator, pump/reservoir | You are building or checking fit |
| [Electrical Interface](ELECTRICAL_INTERFACE.md) | PCIe slot power, external 48 V path, isolation, interlocks, fault fallback | You are designing power or control hardware |
| [Thermal and Power Design](THERMAL_POWER.md) | Full power budget, coolant calculation, thermal targets | You are sizing cooling or power delivery |
| [Architecture BOM](BOM.md) | Package, PCB, power, cooling, I/O requirements | You are translating architecture into hardware |

## Architecture definition

| Document | Scope | Start here when |
|---|---|---|
| [ISA and Execution Model](ISA.md) | Native wave model, registers, instruction encoding, ordering, faults | You are writing RTL, an assembler, compiler or debugger |
| [Graphics Pipeline](GRAPHICS_PIPELINE.md) | Multi-tile geometry, rasterization, render ownership, depth and presentation | You are implementing the graphics front/back end |
| [Texture and Compression](TEXTURE_COMPRESSION.md) | Samplers, filtering, format decode and lossless surface compression | You are implementing texture or memory-bandwidth logic |
| [Chiplet Fabric](CHIPLET_FABRIC.md) | Tile topology, coherence, bandwidth budget, reliability and QoS | You are designing package links or cache coherence |
| [Virtual Memory](VIRTUAL_MEMORY.md) | GPU address spaces, page tables, faults, residency and optional ATS/PASID | You are implementing memory management |
| [Scheduling and Preemption](SCHEDULING_PREEMPTION.md) | Hardware queues, priorities, preemption, watchdog and reset domains | You are implementing command processing or recovery |
| [Power Management](POWER_MANAGEMENT.md) | Per-tile DVFS, gating, board budgets, transitions and fault isolation | You are implementing tile power policy or controller logic |

## Prototype documents

| Document | Scope | Start here when |
|---|---|---|
| [Prototype Build](PROTOTYPE_BUILD.md) | P0 electrothermal build and P1 programmable bench | You are assembling the first hardware |
| [Prototype Procurement](PROTOTYPE_PROCUREMENT.md) | Exact parts, consumables, bench tools, alternatives, price snapshots | You are purchasing equipment or parts |
| [Prototype Unit Cost](PROTOTYPE_UNIT_COST.md) | Recurring prototype cost after tools are already owned | You are estimating per unit expense |
| [Test Record Template](TEST_RECORD_TEMPLATE.md) | Fields for measured prototype results | You are recording P0 or P1 data |
| [Host Compatibility](HOST_COMPATIBILITY.md) | Generic compact and tower host requirements | You are checking a chassis or motherboard |

## Software and validation

| Document | Scope | Start here when |
|---|---|---|
| [Software Stack](SOFTWARE_STACK.md) | Firmware, Linux, Windows, Vulkan, Direct3D, media, compiler, diagnostics | You are working on host software or drivers |
| [Validation](VALIDATION.md) | Repository, analytical, firmware, mechanical, prototype, and future silicon checks | You need acceptance criteria |
| [Repository Integrity](REPOSITORY_INTEGRITY.md) | Public hygiene, secrets, build output, consistency and negative controls | You are changing repository infrastructure |
| [Documentation Style](DOCUMENTATION_STYLE.md) | Public technical writing conventions | You are editing public documentation |
| [Artifact Provenance](ARTIFACT_PROVENANCE.md) | Which files are authoritative, derived, or manually maintained | You are regenerating design files |

## Reference material and future work

| Document | Scope | Start here when |
|---|---|---|
| [Reference GPU Comparison](REFERENCE_COMPARISON.md) | Dated CGX target comparison with shipping GPUs | You want a current side by side reference |
| [Public Sources](SOURCES.md) | Manufacturer, standards, process, and procurement sources | You need to verify an external fact |
| [Build Instructions](BUILD_INSTRUCTIONS.md) | Long path from architecture through ASIC, board, drivers, and qualification | You are planning beyond P0/P1 |
| [Roadmap](ROADMAP.md) | Remaining mechanical, electrical, software, prototype, and silicon work | You want the work sequence |

## Primary machine readable design file

Shared numeric targets are maintained in [`design/cgx1_architecture.json`](../design/cgx1_architecture.json). Human readable documents explain those values and their engineering context.

If a document and the machine readable file disagree on a shared target, treat the mismatch as a repository defect and fix both the value and the consistency test.
