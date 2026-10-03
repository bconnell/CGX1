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
- executable firmware, analytical-model, ISA-reference, matrix-numeric, matrix-architecture, matrix-pipeline-schedule, matrix-banking, matrix-staging, matrix-result-staging, matrix-scoreboard, matrix-INT8-execution, matrix-INT8-path, matrix-INT8-engine-shell, matrix-INT8-resident-engine, resident-wave-VGPR-storage, pooled-VGPR lifecycle/reference, ordinary/shared execution, resident-vector scheduling, mixed-compute admission, and power-management policy tests. The RTL workflow also compiles and executes the resident-wave matrix arbiter, pooled restore mapping, matrix preflight, allocator, storage, matrix frontend, pooled subsystem, ordinary/shared access, same-bank sequencing, vector INT32 ALU/pipeline including illegal-opcode completion without operand service, resident-vector scheduling including non-power-of-two fairness and invalid-width rejection, mixed frontend, and cadence/service-policy testbenches.

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

The resident-wave VGPR storage SystemVerilog testbench exercises a four-slot parameterization of an eight-bank, 32-row-per-bank organization. It verifies two whole-wave reads, one whole-wave write, modulo-8 bank placement for canonical A/B and adjacent C/D accesses, exact source alias broadcast, independent storage for identical architectural VGPR numbers in different resident waves, and canonical lane order on the 1,024-bit delivery buses. Four slots is a test configuration rather than a frozen occupancy target. The current local working-tree candidate passed this test in `scripts/validate_rtl.sh`; published CI and physical storage validation remain separate evidence.

The matrix-scoreboard executable test verifies a 256-VGPR per-wave reservation state, all single-register ordinary RAW/WAW/WAR outcomes across the full register namespace, source release, destination completion, multiple independent pending destinations, exact A/B alias handling, and read/write-port conflict reporting. The RTL integration test additionally changes the live issue register inputs after acceptance and verifies that scoreboard state is created from the controller-latched accepted bases.

These references validate the architecture contract and functional reference behavior. The standalone signed INT8 arithmetic RTL has passed the repository simulation gate. The composed INT8 path has its own exact-revision simulation evidence flag. None of these tests establish physical VGPR macros, timing closure, area/power characterization, compiler integration, or measured silicon performance.

The mixed resident execution frontend has a dedicated executable admission reference and SystemVerilog integration test. Its vector dependency scoreboard now also receives pending LSU load destinations. The workgroup layer composes CU-local admission, barriers, pooled VGPR state, the shared/local region allocator, and a decoded LSU. LSU regression coverage includes local store/load, global delayed requests, response/writeback backpressure, per-register dependency stalls, independent wave and same-wave progress, barrier membership during memory wait, store completion, address and downstream faults, kill before/after service, reset epochs, stale responses after reuse, abort/quiescent drain, local-region reuse, and seeded request/fault/reuse stress. The request boundary starts after decode because memory instruction opcode and operand encodings are not defined. Hardware queue/runtime integration, compiler dispatch/completion, and physical memory remain open.

The workgroup scheduler reference composes `ComputeUnitWorkgroupScheduler` with the actual `ResidentWaveVgprPool`, `PooledVgprStorage`, and shared/local-memory region allocator; its tests include per-wave counts, complete admission rollback, quiescent retirement, fault/kill/reset, stale-data rejection, and 100,000 randomized residency transitions. Its memory integration tests check byte-region admission and fragmentation, issue rejection during memory waits and barriers, response-consumption wakeup, sibling and independent-workgroup progress, terminal cancellation drain, a faulted memory waiter releasing a surviving sibling at its barrier while shared storage remains owned, reset, and 5,000 deterministic mixed memory/barrier cycles. `cgx1_compute_workgroup_execution_frontend_tb.sv` composes the actual RTL memory-region allocator, mixed matrix/vector frontend, transactional VGPR reservation, and barrier membership. It covers maximum-fit allocation, shared-memory fragmentation rejection and hole reuse, VGPR-fragmentation rollback across both allocators, final-release backpressure while same-wave restore traffic is active, duplicate dispatch IDs, independent groups, real matrix and vector work across sibling waves, barrier generations and waiter issue masking, vector- and matrix-in-flight faults with deferred release, a dependency-stalled survivor, kill while blocked, reset during active and partial admission, and more than 5,000 randomized arrivals. The membership-only `cgx1_workgroup_residency_barrier_tb.sv` additionally tests simultaneous and staggered arrivals, arbitrary physical slot maps, busy arrival exclusion, survivor-set updates, and release completion.

At the prior workgroup/local-memory checkpoint before this RTL LSU slice, the focused executable and `cgx1_workgroup_scheduler_checks` passed, strict GCC compilation with `-Wconversion -Wsign-conversion -Werror` passed, and all 23 CTest targets passed. The Windows validation wrapper passed repository hygiene, integrity, design consistency, negative controls, and Markdown links, then stopped at CMake configuration because `cmake.exe` was not on Windows PATH; the WSL CMake build and full CTest run passed. Those results are for that earlier candidate and do not imply hosted CI coverage for the current LSU changes.

`cgx1_shared_local_memory_checks` tests the executable finite-region reference with isolation, allocation reuse, capacity and fragmentation, active-lane masking, whole-request fault prevalidation, tagged waits/responses, duplicate-wave exclusion, bank-conflict serialization, independent-bank parallel service, arbitration progress, cancellation drain, reset, and 5,000 deterministic service cycles. `cgx1_cu_shared_local_memory_tb.sv` covers standalone RTL region allocation, 32-lane access, masking, fault atomicity, bank service, response stability, cancellation, release, and reset/reuse. `cgx1_compute_workgroup_lsu_tb.sv` exercises the LSU request table and lifecycle; `cgx1_compute_workgroup_execution_frontend_tb.sv` tests the LSU composed with live workgroup admission, pooled VGPR storage, barrier tracking, and region release. Local simulations establish only their exercised protocol/model behavior.

Hosted evidence is revision-specific. RTL CI run `37091104373` and Windows CI run `37091104769` both completed successfully for exact SHA `56dde4cd92c261063d62c7019d81f6d8b4c8cc01`. This checkpoint includes C++ scheduler memory waits and RTL workgroup-owned memory-region allocation. Local C++ and Icarus evidence does not establish hosted CI for a later revision, synthesis, timing, area, power, physical implementation, or silicon behavior. Hardware queues, compiler/runtime dispatch and completion, RTL load/store issue and memory waits, and full GPU integration remain open.

For commit `2de4a188e9d925d4fd74b45308d6b719c2980c79`, the focused per-wave LSU test and authoritative workgroup frontend test passed, the complete `scripts/validate_rtl.sh` gate passed, and the WSL Release build plus CTest passed all 23 targets. Local Windows repository hygiene, integrity, design consistency, negative controls, and Markdown-link checks passed; the local wrapper stopped at CMake configuration because `cmake.exe` is not on Windows PATH. [RTL CI run 37142609707](https://github.com/bconnell/CGX1/actions/runs/37142609707) and [Windows CI run 37142609735](https://github.com/bconnell/CGX1/actions/runs/37142609735) both passed on that exact SHA. The global interface is a functional ready/valid model only; this slice establishes no cache, MMU, HBM, timing, area, power, or physical-memory evidence.

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

The public RTL currently covers top-level P0-P4 fallback, per-tile scheduler eligibility and emergency-isolation request, matrix pipeline control, capture/active operand staging, output-result staging, signed INT8 arithmetic/path, resident-wave arbitration/dependencies, pooled VGPR lifecycle/storage, ordinary INT32 vector execution, a mixed matrix/vector frontend, and a workgroup frontend with an integrated decoded per-wave LSU. The tile power manager consumes active/requested board state and external per-tile state/readiness, enforces the documented caps, and leaves tile-state sequencing and physical gate timing open. The workgroup frontend connects local-region access and tagged global ready/valid transactions through load-result writeback, dependency tracking, memory faults, cancellation, and quiescent resource release. The local candidate passed `scripts/validate_rtl.sh` with Icarus 12.0 in Ubuntu WSL, and all 23 CTest targets passed under GCC in WSL. The power-policy C++ test keeps its assertions active under Release (`NDEBUG`) builds. Local Windows hygiene, integrity, design consistency, negative-control, and Markdown-link checks passed; its CMake step could not run because `cmake.exe` is absent from local Windows PATH. Hosted RTL CI run `37145496015` and Windows CI run `37145498188` both passed on exact commit `68cb2c3bb1c68df8c662a82959f1db8119deb8d0`. This evidence does not establish formal verification, synthesis, timing, area, power, physical implementation, or silicon behavior. Full tile-state sequencing, hardware queue/runtime integration, FP16/BF16/FP8 arithmetic, foundry storage-macro selection, a complete CU scheduler, and the rest of the GPU pipeline remain open.

RTL simulation is run with Icarus Verilog in SystemVerilog 2012 mode through `scripts/validate_rtl.sh`. The Ubuntu RTL CI workflow runs for every push to `main`, preventing a final reference, schema, or truth-state revision from escaping exact-revision RTL validation. Functional unit and integration testbenches do not replace constrained-random verification, formal work, synthesis, FPGA/emulation, timing closure, or physical implementation.

The critical architecture contracts are defined in [ISA](ISA.md), [Graphics Pipeline](GRAPHICS_PIPELINE.md), [Texture and Compression](TEXTURE_COMPRESSION.md), [Chiplet Fabric](CHIPLET_FABRIC.md), [Virtual Memory](VIRTUAL_MEMORY.md), and [Scheduling and Preemption](SCHEDULING_PREEMPTION.md). RTL must match those contracts or update them and their tests in the same revision.

The power-state fallback keeps active board state safe: invalid requests and hardware/thermal/dock emergencies report P0. `cgx1_tile_power_manager` removes scheduler eligibility immediately and requests all-tile isolation during reset/emergency. Tile eligibility also requires the tile to be in an allowed T3-T5 state with power, clocks, coherence, and isolation status ready.

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
