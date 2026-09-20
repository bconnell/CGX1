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
- executable firmware and analytical model tests.

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
- queue/priorities and preferred VRAM page constants.

The analytical model does not produce application speedup claims.

## 3. ISA reference

The executable ISA test verifies:

- base 32-bit field encode/decode round trip;
- instruction-class recognition;
- scalar register bounds;
- full 8-bit vector register addressing.

This validates the public field contract only. It is not a shader core or ISA conformance suite.

## 4. Firmware

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

## 5. RTL boundary

The public RTL currently covers top level power state gating and tile enable behavior. It does not implement or verify a complete GPU pipeline, cache fabric, HBM controller, display engine, media engine, PCIe controller, shader ISA, or production security design.

Future RTL work needs unit, integration, constrained random, formal, FPGA, and emulation work appropriate to each block.

The critical architecture contracts are defined in [ISA](ISA.md), [Graphics Pipeline](GRAPHICS_PIPELINE.md), [Texture and Compression](TEXTURE_COMPRESSION.md), [Chiplet Fabric](CHIPLET_FABRIC.md), [Virtual Memory](VIRTUAL_MEMORY.md), and [Scheduling and Preemption](SCHEDULING_PREEMPTION.md). RTL must match those contracts or update them and their tests in the same revision.

The power state scaffold must keep the reported state and tile enable state consistent. A dock fault reports P0 and disables compute tiles.

## 6. Mechanical validation

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

## 7. P0 electrothermal validation

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

## 8. P1 surrogate validation

P1 results must identify the surrogate hardware. Alveo U50 measurements cannot be labeled as CGX performance.

P1 can provide evidence for:

- host PCIe software;
- memory traffic experiments;
- telemetry protocols;
- queue and command concepts;
- selected RTL blocks;
- early compiler/API experiments.

## 9. Future silicon validation

A fabricated CGX device requires separate evidence for:

- PCIe compliance and signal integrity;
- HBM training, ECC, sustained bandwidth, and error handling;
- compute instruction correctness;
- graphics API conformance;
- shader/compiler correctness;
- raster and depth/stencil correctness;
- ray tracing correctness;
- media codec correctness;
- display timing and link compliance;
- power and transient behavior;
- thermal characterization;
- reset and fault recovery;
- long duration workloads;
- application and game compatibility.

## 10. Reporting results

Every published result should identify whether it is:

- a target;
- analytical;
- simulated;
- measured on P0;
- measured on P1 surrogate hardware;
- measured on engineering silicon;
- measured on production silicon.

A calculation does not replace a hardware measurement, and surrogate hardware does not establish CGX application performance.
