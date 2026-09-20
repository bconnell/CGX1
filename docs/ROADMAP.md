# Roadmap

[Documentation index](README.md) · [Project status](STATUS.md) · [Prototype build](PROTOTYPE_BUILD.md)

## Current design package

- architecture specification and machine readable target file;
- revised card and thermal dock envelopes;
- selected prototype fan, radiator, and pump/reservoir references;
- analytical thermal, power, fit, and FP32 model;
- reference power state firmware;
- top level RTL state scaffold;
- prototype procurement and cost planning;
- software implementation plan;
- native wave32 ISA and executable base instruction encoder/decoder;
- matrix-engine numeric contract, M16N16 physical tile definitions, wave32 fragment map, base ISA opcodes, pipeline timing target, dense-rate derivation, and executable references;
- multi-tile graphics pipeline and render ownership model;
- texture block and lossless surface-compression architecture;
- coherent chiplet-fabric protocol and bandwidth budget;
- virtual-memory/page-fault architecture;
- queue scheduling, preemption and reset containment model;
- per-tile DVFS, clock/power-gating architecture and executable policy/invariant model;
- validation and repository integrity checks.

## P0 manufacturing package

- dimensioned heater locations matching planned package heat regions;
- copper spreader and cold plate machining drawing;
- rear power and coolant connector drawing;
- low profile and full height bracket drawings;
- detailed dock internal arrangement and hose/fitting clearance;
- 48 V low voltage harness drawing;
- control PCB schematic;
- control PCB layout, drill files, and manufacturing outputs;
- instrumented 360 W thermal procedure.

## P0 physical validation

- fabricate card carrier and revised dock;
- validate selected 50 mm fan fit;
- validate radiator, radiator fans, and pump/reservoir packing;
- validate actual loop flow;
- validate coolant rise and component temperatures;
- validate connector heating and 48 V delivery;
- validate P3/P4 dock loss fallback to P0;
- measure card and dock dimensions;
- revise mechanical and thermal targets from measured results.

## P1 programmable bench

- integrate one shared HBM programmable accelerator;
- prototype command, telemetry, memory movement, and selected RTL blocks;
- establish reproducible host software tests;
- keep surrogate results labeled as surrogate measurements.

## Architecture implementation

- implement the complete ISA semantics and assembler/disassembler;
- build an instruction-level emulator and shader execution tests;
- implement command processor and queue packet ABI;
- implement page tables, translation caches and replayable-fault model;
- implement tile coherence protocol and fabric transaction model;
- implement texture sampling and compression reference models;
- implement primitive binning, raster ownership and back-end ordering models;
- implement matrix RTL against the frozen tile, fragment, register, opcode, reduction-order, issue-interval, and scoreboard contracts;
- design and validate matrix register-file banking, cross-lane delivery, input/output staging, timing, area, and power; revise the timing target if physical evidence cannot close it;
- validate every advertised precision profile against the numeric and physical architecture references, then add compiler/API lowering;
- characterize finer-than-workgroup preemption cost before adding it to the baseline;
- characterize real per-tile V/F curves, leakage, transition latency, and controller hysteresis;
- implement and verify the I/O-die power manager, tile isolation, retention, clock gating, and power-gating RTL.

## Custom silicon

- implement the defined ISA and shader execution model in verified RTL and software;
- complete compute, raster, ray, cache, fabric, memory, display, media, security, and debug RTL;
- complete verification and FPGA/emulation work;
- select licensed PHY and codec IP;
- complete physical design and package engineering;
- fabricate validation silicon;
- develop Linux and Windows drivers;
- complete graphics, compute, media, and application conformance;
- characterize production silicon and publish measured performance separately from design targets.
