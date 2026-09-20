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
- executable firmware, analytical-model, ISA-reference, matrix-numeric, matrix-architecture, matrix-pipeline-schedule, matrix-banking, and power-management policy tests.

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

The matrix-pipeline executable test verifies that one wave32 VGPR transfer is 1,024 bits; the input staging budget is 2,048 bytes; capture reads exactly A0-A3, B0-B3, and C/D0-C/D7; writeback covers D0-D7; source registers remain protected through capture; the destination remains pending through writeback; and a steady stream issued every 16 cycles stays within two whole-wave reads or one whole-wave write per cycle without requiring simultaneous matrix read/write access.

The matrix-banking executable test verifies eight modulo-8 bank classes, A base class 0, distinct B base class 4, exact A/B alias broadcast, C/D bank separation, and exhaustively checks every valid destination/A/B base-register combination for capture-cycle conflicts under a single-matrix-access-per-bank-class rule.

These references validate the architecture contract, logical register-interface schedule, and bank-class conflict rules. They do not validate physical VGPR macros, matrix RTL, timing closure, area/power characterization, compiler integration, or measured performance.

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

The public RTL currently covers top-level power-state/tile-enable behavior and the matrix pipeline control schedule. The matrix RTL controller validates issue legality, capture/execute/writeback sequencing, VGPR addresses, source release, destination completion, bank-class conflict freedom, and 16-cycle steady-state reissue behavior. It does not implement the matrix arithmetic datapath, physical VGPR macros, staging memories, or a complete GPU pipeline.

RTL control simulation is run with Icarus Verilog in SystemVerilog 2012 mode through `scripts/validate_rtl.sh` and the path-scoped Ubuntu RTL CI workflow. Future RTL work still needs arithmetic unit tests, integration, constrained random, formal, synthesis, FPGA/emulation, and implementation work appropriate to each block.

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
