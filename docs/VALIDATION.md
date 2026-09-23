# Validation Plan

[Documentation index](README.md) · [Project status](STATUS.md) · [Test record template](TEST_RECORD_TEMPLATE.md) · [Repository integrity](REPOSITORY_INTEGRITY.md)

Validation is separated by evidence category so a calculation cannot be mistaken for a physical measurement.

## 1. Repository validation

The repository gate checks:

- public wording policy;
- negative controls proving the wording gate rejects prohibited test cases;
- private machine paths and local residue;
- secrets and signing material patterns;
- PowerShell 5.1 parse compatibility;
- external GitHub Actions pinned to full commit hashes;
- shared design value consistency;
- local Markdown links;
- C and C++ build success;
- executable firmware, analytical-model, ISA-reference, matrix-numeric, matrix-architecture, matrix-pipeline-schedule, matrix-banking, matrix-staging, matrix-result-staging, matrix-scoreboard, matrix-INT8-execution, matrix-INT8-path, matrix-INT8-engine-shell, matrix-INT8-resident-engine, resident-wave-VGPR-storage, pooled-VGPR lifecycle/reference, and power-management policy tests. The RTL workflow also compiles and executes pooled restore-mapping, matrix-preflight, allocator, storage, matrix-frontend, pooled-subsystem, and pooled-resident-INT8 testbenches.

## 2. Analytical model

The C++ model verifies:

- FP32 arithmetic from lanes and clock;
- low profile card envelope;
- coolant temperature rise from power and flow;
- analytical junction estimate from stated thermal resistance targets;
- FP32 per watt arithmetic;
- SIMD partition-to-lane consistency;
- texture-block totals and peak bilinear sampler arithmetic;
- raster-partition and ROP-lane totals;
- chiplet-fabric read-bandwidth budget relative to HBM4;
- queue/priorities and preferred VRAM page constants;
- L1/shared, tile-L2, aggregate-L2, and package-cache consistency.

The analytical model does not produce application speedup claims.

## 3. ISA reference

The executable ISA test verifies:

- base 32-bit field encode/decode round trip;
- instruction-class recognition;
- scalar register bounds;
- full 8-bit vector register addressing.

This validates the public field contract only. It is not a shader core or ISA conformance suite.

## 4. Matrix numeric reference

The executable matrix test verifies:

- the four-matrix-engine-per-CU and native wave32 architecture constants;
- accepted FP16, BF16, OCP FP8 E4M3/E5M2, and signed INT8 precision tuples;
- rejection of unsupported and invalid tuples;
- OCP FP8 special values, subnormals, round-to-nearest ties-to-even conversion, and both saturation modes;
- exhaustive finite positive and negative FP8 encode/decode round trips for E4M3 and E5M2;
- BF16 round-to-nearest ties-to-even conversion;
- exact FP16/BF16/FP8 widening to FP32 and FP32 fused multiply-add reference behavior;
- signed INT8 to signed INT32 accumulation with defined modulo overflow behavior;
- explicit absence of TF32, FP64 matrix, FP32-input matrix, OCP MX, and structured-sparsity claims.

The separate matrix-architecture executable test verifies M16N16K16 and M16N16K32 shapes, exact wave32 fragment coverage, input packing, VGPR grouping/alignment/overlap rules, Matrix opcode validity, the 8/16/8 capture-execute-writeback schedule, 16-cycle issue interval, 33-cycle result latency, fixed per-instruction reduction order, and dense arithmetic-rate derivation.

The matrix-pipeline executable test verifies that one wave32 VGPR transfer is 1,024 bits; the input staging budget is 2,048 bytes; capture reads exactly A0-A3, B0-B3, and C/D0-C/D7; writeback covers D0-D7; source registers remain protected through capture; the destination remains pending through writeback; and a steady stream issued every 16 cycles stays within two whole-wave reads or one whole-wave write per cycle without requiring simultaneous matrix read/write access. It also validates matrix-to-matrix pending-destination dependency detection, including exhaustive comparison of every legal non-aliased matrix register layout against every aligned pending D/C range.

The matrix-banking executable test verifies eight modulo-8 bank classes, A base class 0, distinct B base class 4, exact A/B alias broadcast, C/D bank separation, and exhaustively checks every valid destination/A/B base-register combination for capture-cycle conflicts under a single-matrix-access-per-bank-class rule.

The matrix-staging executable test verifies the 2,048-byte capture set, separate 2,048-byte active execution operand set, ordered eight-cycle capture, cycle-7 commit, and preservation of the active set while the next capture is incomplete.

The matrix-result-staging executable test verifies the 1,024-byte eight-register result slot, rejection of a second load while occupied, ordered writeback cycles 0 through 7, release after the final cycle, safe slot reuse, and cycle-0 load-to-writeback bypass.

The matrix-INT8-execution executable test verifies M16N16K32 signed INT8 arithmetic over 16 execution cycles, canonical A/B/C/D fragment mapping, two K terms per output per cycle, the frozen even/odd signed INT32 reduction order, signed extreme inputs, and explicit modulo-`2^32` overflow.

The matrix-INT8-path executable test composes capture-to-active operand staging, the 16-cycle signed INT8 execution model, cycle-0 result bypass, and ordered result drain. The corresponding SystemVerilog integration testbench models the wave register file and performs a complete opcode-6 capture/execute/writeback transaction; that integrated path has passed RTL CI.

The matrix-INT8-engine-shell SystemVerilog testbench adds the controller and per-wave scoreboard around that path, rejects a non-INT8 matrix opcode, models the external 256-entry whole-wave VGPR namespace, verifies source and destination hazard reporting, and checks a complete opcode-`0x6` result transaction. The single-engine INT8 shell has passed the repository RTL simulation gate.

The matrix-INT8-resident-engine SystemVerilog testbench uses a four-slot test configuration of the parameterized resident-wave boundary. It checks round-robin selection, wave-tagged VGPR traffic, identical VGPR-number independence across waves, same-wave pending-destination blocking, per-wave ordinary RAW admission, wave-tagged writeback, and invalid full-wave request tagging. Four slots is a test configuration, not a frozen architecture count. The test also exercises a dependency-stalled request across a missed issue slot and verifies that the next accepted request preserves the 16-cycle matrix cadence without simultaneous matrix VGPR read/write traffic. The resident-engine boundary has passed the repository RTL simulation gate.

The resident-wave VGPR storage SystemVerilog testbench exercises a four-slot parameterization of an eight-bank, 32-row-per-bank organization. It verifies two whole-wave reads, one whole-wave write, modulo-8 bank placement for canonical A/B and adjacent C/D accesses, exact source alias broadcast, independent storage for identical architectural VGPR numbers in different resident waves, and canonical lane order on the 1,024-bit delivery buses. Four slots is a test configuration rather than a frozen occupancy target. Exact-revision simulation evidence remains false until this candidate passes RTL CI.

The matrix-scoreboard executable test verifies a 256-VGPR per-wave reservation state, all single-register ordinary RAW/WAW/WAR outcomes across the full register namespace, source release, destination completion, multiple independent pending destinations, exact A/B alias handling, and read/write-port conflict reporting. The RTL integration test additionally changes the live issue register inputs after acceptance and verifies that scoreboard state is created from the controller-latched accepted bases.

These references validate the architecture contract and functional reference behavior. The standalone signed INT8 arithmetic RTL has passed the repository simulation gate. The composed INT8 path has its own exact-revision simulation evidence flag. None of these tests establish physical VGPR macros, timing closure, area/power characterization, compiler integration, or measured silicon performance.

The mixed resident execution frontend has a dedicated executable admission reference and SystemVerilog integration test. The test covers pooled initialization, resident vector execution/writeback, release blocking while vector execution is live, matrix blocking on a live vector destination hazard, recovery after that hazard clears, and same-edge matrix/vector acceptance exclusion. The external per-wave vector dependency-ready input remains a scheduler contract rather than evidence of a completed compute-unit scheduler.

## 5. Power-management reference

The executable power-management test verifies:

- unchanged 25/45/70/220/360 W board limits;
- P3/P4 dock-state classification;
- P0-P4 maximum tile operating classes;
- scheduler eligibility only for executable tile states;
- rejection of invalid board/tile-state values and negative, non-finite, and over-limit budget requests;
- rejection of combined plans that violate either tile-state caps or the active board budget;
- exact-limit budget acceptance;
- exhaustive rejection of skipped orderly tile-state transitions;
- voltage-before-frequency ordering for performance increases;
- frequency-before-voltage ordering for performance decreases;
- scheduler-drain and dirty-coherence guards before orderly idle/retention/off transitions;
- coherence-ready guards before wake reaches Idle or becomes scheduler eligible;
- emergency isolation conditions for hardware, thermal, dock-power, and coolant faults;
- configurable promotion/demotion hysteresis behavior.

The policy model does not claim a measured tile power, regulator response time, transition latency, or silicon V/F curve.

## 6. Firmware

Reference firmware tests cover:

- P0 through P4 board limits;
- external 48 V required for P3/P4;
- valid coolant flow required for P3/P4;
- dock loss fallback to P0;
- coolant flow loss fallback to P0;
- hardware fault fallback to P0;
- high GPU temperature fallback;
- high VRM temperature fallback;
- invalid requested state fallback.

The dock fault tests also verify that the fallback does not request a 70 W slot state.

## 7. RTL boundary

The public RTL currently covers top-level power-state/tile-enable behavior, matrix pipeline control, capture/active operand staging, output-result staging, signed INT8 arithmetic/path, one-wave hazard reporting, parameterized resident-wave matrix arbitration, wave-local dependency handling, per-wave scoreboard routing, and ordinary issue admission. FP16/BF16/FP8 arithmetic, physical resident-wave VGPR/storage macros, ordinary vector execution, and the rest of the GPU pipeline remain open.

RTL simulation is run with Icarus Verilog in SystemVerilog 2012 mode through `scripts/validate_rtl.sh`. The Ubuntu RTL CI workflow runs for every push to `main`, preventing a final reference, schema, or truth-state revision from escaping exact-revision RTL validation. Functional unit and integration testbenches do not replace constrained-random verification, formal work, synthesis, FPGA/emulation, timing closure, or physical implementation.

The critical architecture contracts are defined in [ISA](ISA.md), [Graphics Pipeline](GRAPHICS_PIPELINE.md), [Texture and Compression](TEXTURE_COMPRESSION.md), [Chiplet Fabric](CHIPLET_FABRIC.md), [Virtual Memory](VIRTUAL_MEMORY.md), and [Scheduling and Preemption](SCHEDULING_PREEMPTION.md). RTL must match those contracts or update them and their tests in the same revision.

The power state scaffold must keep the reported state and tile enable state consistent. A dock fault reports P0 and disables compute tiles.

## 8. Mechanical validation

Before P0 acceptance:

- verify 167.5 × 68.5 mm PCB dimensions;
- verify 39.5 mm installed card thickness;
- verify selected 50 × 50 × 10 mm card fan fit;
- verify both bracket variants;
- verify the 310 × 210 × 75 mm dock enclosure;
- verify 280 × 120 × 30 mm radiator fit;
- verify two 120 × 25 mm radiator fan volumes;
- verify 112 × 57 × 41.95 mm pump/reservoir volume;
- verify fitting, hose, wiring, and enclosure wall clearance;
- verify coolant and power services clear the chassis rear boundary;
- inspect mounting pressure and PCB bending;
- pressure and leak test the cooling assembly.

## 9. P0 electrothermal validation

P0 measures:

- 360 W sustained heat removal;
- coolant inlet/outlet temperature;
- actual loop flow;
- cold plate and simulated package temperatures;
- external 48 V current and voltage;
- host slot current in dock mode;
- regulator and connector temperatures;
- fan and pump speed;
- external 48 V loss response;
- coolant flow loss response.

Use [Test Record Template](TEST_RECORD_TEMPLATE.md) for each repeatable configuration.

## 10. P1 surrogate validation

P1 results must identify the surrogate hardware. Alveo U50 measurements cannot be labeled as CGX performance.

P1 can provide evidence for:

- host PCIe software;
- memory traffic experiments;
- telemetry protocols;
- queue and command concepts;
- selected RTL blocks;
- early compiler/API experiments.

## 11. Future silicon validation

A fabricated CGX device requires separate evidence for:

- PCIe compliance and signal integrity;
- HBM training, ECC, sustained bandwidth, and error handling;
- compute instruction correctness;
- matrix precision, conversion, accumulation, capability enumeration, frozen tile/fragment/opcode behavior, register-file delivery, issue timing, RTL timing closure, area/power, throughput validation, and compiler lowering;
- graphics API conformance;
- shader/compiler correctness;
- raster and depth/stencil correctness;
- ray tracing correctness;
- media codec correctness;
- display timing and link compliance;
- power and transient behavior;
- per-tile DVFS characterization, transition ordering, gating/retention correctness, hysteresis stability, and emergency isolation;
- thermal characterization;
- reset and fault recovery;
- long duration workloads;
- application and game compatibility.

## 12. Reporting results

Every published result should identify whether it is:

- a target;
- analytical;
- simulated;
- measured on P0;
- measured on P1 surrogate hardware;
- measured on engineering silicon;
- measured on production silicon.

A calculation does not replace a hardware measurement, and surrogate hardware does not establish CGX application performance.

The executable matrix test set now also includes ordinary/shared pooled-VGPR and resident INT32 vector execution/scheduling references. The RTL workflow includes ordinary/shared arbitration, same-bank read sequencing, vector INT32 ALU/pipeline, resident vector scheduling, and unified pooled execution-subsystem behavioral tests. These tests establish logical behavior only; they do not establish timing, area, power, or silicon performance.

