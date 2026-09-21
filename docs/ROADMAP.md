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
- matrix-engine numeric contract, M16N16 physical tile definitions, wave32 fragment map, base ISA opcodes, pipeline timing target, dense-rate derivation, executable register-interface schedule, and exhaustive modulo-8 bank-conflict reference;
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
- obtain exact-revision RTL simulation evidence for the published pooled resident-wave VGPR allocator, storage, matrix preflight, capture/writeback, and resident INT8 integration boundary;
- implement the ordinary vector execution datapath and shared pooled-VGPR access arbitration while preserving matrix hazard, validity, allocation-lifetime, and port-ownership rules;
- select implementation storage macros without prematurely freezing resident-wave occupancy, implement FP16/BF16/FP8 matrix arithmetic with the frozen FP32-FMA semantics, and validate timing, area, and power; revise timing targets if physical evidence cannot close them;
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
