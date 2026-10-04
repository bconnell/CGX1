# Roadmap

[Documentation index](README.md) · [Project status](STATUS.md) · [Prototype build](PROTOTYPE_BUILD.md)

## Current design package

- architecture specification and machine readable target file;
- machine-readable subsystem completeness matrix with explicit evidence-level states;
- revised card and thermal dock envelopes;
- selected prototype fan, radiator, and pump/reservoir references;
- analytical thermal, power, fit, and FP32 model;
- reference power state firmware;
- top-level P0-P4 fallback with per-tile scheduler-eligibility and emergency-isolation RTL;
- prototype procurement and cost planning;
- software implementation plan;
- native wave32 ISA, executable base encoder/decoder, provisional INT32 vector semantics, bounded vector/control software stream references, and optional RTL instruction-memory request/response integration through the workgroup-owned PC, vector decoder, resident execution path, and provisional Control termination; remaining class-specific semantics and compiler/runtime lowering remain open;
- matrix-engine numeric contract, M16N16 physical tile definitions, wave32 fragment map, base ISA opcodes, pipeline timing target, dense-rate derivation, executable register-interface schedule, and exhaustive modulo-8 bank-conflict reference;
- multi-tile graphics pipeline and render ownership model;
- texture block and lossless surface-compression architecture;
- coherent chiplet-fabric protocol and bandwidth budget;
- virtual-memory/page-fault architecture;
- queue scheduling, preemption and reset containment model;
- authoritative complete-workgroup residency reference and RTL frontend composed with the actual pooled VGPR allocator, mixed matrix/vector execution, barrier generations, and quiescent retirement;
- CU-local decoded compute workgroup dispatch reference and RTL queue, integrated with the authoritative residency frontend, plus a bounded C++ command-queue reference and local RTL integration of parameterized per-context rings, packet parsing, bounded command lifecycle, queue reset/cancellation, and quiescent retirement; global queue arbitration, a frozen command ABI, graphics dispatch, public runtime/compiler integration, and multi-CU placement remain open;
- shared/local-memory reference and RTL integrated with workgroup-owned regions, a decoded per-wave LSU, memory-wait issue gating, tagged global ready/valid responses, load writeback, fault/cancel handling, and quiescent release; base-ISA memory decode and a physical global-memory backend remain open;
- per-tile DVFS, clock/power-gating architecture and executable policy model; the RTL eligibility authority removes fixed P1/P2 tile counts, while tile-state sequencing and physical actuation remain open;
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
- extend provisional fetched Control operations from termination to explicit branch/call/return contracts, then connect selected handlers to control-flow events while keeping opcode assignments explicitly provisional;
- define provisional memory instruction encodings and connect fetched memory words to LSU issue acceptance, operand capture, sequential-PC metadata, and fault retirement;
- build an instruction-level emulator and shader execution tests;
- extend the locally integrated RTL command lifecycle toward global queue arbitration, then freeze the public queue packet ABI after reference-model validation;
- implement page tables, translation caches and replayable-fault model;
- implement tile coherence protocol and fabric transaction model;
- implement texture sampling and compression reference models;
- implement primitive binning, raster ownership and back-end ordering models;
- extend the CU-local decoded workgroup dispatcher into the global I/O-die hardware queue manager and multi-CU/tile placement path, with fault reporting and fairness while preserving complete-workgroup residency and quiescent retirement;
- extend the candidate command-queue reference into the I/O-die global queue manager, RTL packet-processing path, and runtime/compiler submission and completion path feeding CU-local dispatch;
- connect decoded per-wave issue selection, LSU waits, matrix/vector dependencies, and barrier generations under one canonical CU execution controller; the current dispatcher arbitrates workgroups only;
- replace remaining externally supplied per-wave readiness contracts in standalone vector integration with the canonical compute-unit scheduler/scoreboard source, while keeping mixed-workload service-window policy parameterized until scheduling evidence supports a value;
- select implementation storage macros without prematurely freezing resident-wave occupancy, implement FP16/BF16/FP8 matrix arithmetic with the frozen FP32-FMA semantics, and validate timing, area, and power; revise timing targets if physical evidence cannot close them;
- validate every advertised precision profile against the numeric and physical architecture references, then add compiler/API lowering;
- characterize finer-than-workgroup preemption cost before adding it to the baseline;
- characterize real per-tile V/F curves, leakage, transition latency, and controller hysteresis;
- implement the tile-state sequencer, orderly drain/retention transitions, and physical isolation, clock-gating, and power-gating RTL after control/status and physical timing contracts are established.

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
