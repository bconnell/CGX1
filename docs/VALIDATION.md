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

## Release and exact-candidate gates

Executable C and C++ test expectations use `CGX1_TEST_CHECK`, which evaluates once and remains active in Debug, Release, and `NDEBUG`. The source-aware test gate maps CTest executables to their source files, rejects runtime `assert(...)` in test sources, and keeps `static_assert(...)` valid. Positive and negative controls exercise that gate. A Release/NDEBUG false-check probe is run through CTest and must fail with the expected diagnostic.

Historical Release CTest runs from before this migration remain valid build and test-invocation evidence, and explicit checks that were not ordinary `assert` remain valid. They do **not** establish that assertion-based expected-result expressions ran: `NDEBUG` may have removed those checks. Fresh post-migration Debug and Release runs are the evidence for those expectations.

`validate_clean_candidate.py` snapshots the reviewed Git index tree into a temporary detached worktree. It establishes the commit, Git tree, index tree, source fingerprint, and isolated path before configuration; requires the gate files to exist in that tree; rejects an existing `build/` directory; and verifies identity again after validation. The local Windows path runs the Windows repository/design/hygiene gates and then launches the Linux gates through `wsl.exe` as a non-root user (`nobody` by default). It translates Windows paths with `wslpath -a -u`, checks that the selected UID is nonzero, and passes Git's safe-directory setting only to that process for the exact checkout. The Linux runner creates a deterministic detached worktree in Linux `/tmp`, verifies the same commit/tree/fingerprint from Linux Git, and runs the Python gates, Release/NDEBUG failure probe, fresh Debug and Release CMake/CTest builds, and bounded RTL suite using the WSL user's own `PATH`. It checks Linux candidate identity again before cleanup. Windows and Linux committed-tree fingerprints must match before configuration and after validation. No persistent WSL account is required. If no configured non-root WSL account can start, use the exact-SHA hosted RTL workflow, which runs the same clean-candidate validator with Icarus on its ordinary unprivileged Linux runner. A WSL root run is diagnostic evidence only; it is not canonical clean-candidate evidence. The hosted Windows job uses its clean candidate worktree. Candidate worktrees and clean build trees are removed on success and failure; an unexplained prior candidate or build tree blocks a duplicate run and is left for ownership classification.

Python validators derive their default repository root from their own script location. If a Windows-style `--root` is explicitly supplied from POSIX/WSL, the path helper invokes `wslpath` and rejects an unmapped or unexpected drive path with a diagnostic. `CGX1_WSL_DISTRO` and `CGX1_WSL_USER` can select another already-installed distribution and account; the runner rejects UID 0. Candidate identity is a gate prerequisite: missing Git commit/tree/index data or a source fingerprint stops validation before any configure/build and cannot be reported as a clean pass.

The clean CMake runner preflights the filesystem that will receive output before making a build directory. It builds Debug and Release sequentially, applies the selected compiler operation's output-tree limit, checks individual generated-file sizes, removes each temporary configuration after its CTest run, and reports compiler paths, IDs and versions, CMake/CTest versions, wall time, test counts, peak configuration-tree bytes, and free space before and after cleanup. A failed configuration records its partial tree size before cleanup; Windows builds include verbose MSBuild diagnostics. The developer profile warns below 50 GiB and blocks below a 40 GiB reserve; both values can be overridden through `CGX1_DISK_WARNING_FREE_BYTES` and `CGX1_DISK_MINIMUM_FREE_BYTES`. Hosted jobs use a separate 2 GiB reserve and explicitly select the hosted profile. Exact-SHA hosted measurements from commit `ae0dbd016ed32abfcaec24351e0679f3b892f3db` recorded GCC Debug at 28,471,237 bytes, GCC Release at 3,612,512 bytes, and the larger ASan/UBSan tree at 87,320,145 bytes (Clang; GCC measured 68,108,995). The bounded Icarus scan measured 11,022,503 bytes across 98 files. These are output-tree observations, not filesystem high-water measurements; the configured tree limits are twice each observed size. The hosted candidate source tree measured 14,116,649 bytes after its clean CMake outputs were removed, so that value does not represent candidate-validation peak storage. GCC, sanitizer, and Icarus estimates remain workload observations rather than guarantees for other toolchains or source revisions. Clang Debug/Release, complete clean-candidate peak, Windows clean-CMake peak, complete Verilator build peak, synthesis, and formal output sizes remain unmeasured. For an optional local sanitizer build, run `python scripts/check_disk_budget.py --profile developer --operation sanitizer-build --output-path build/sanitizers` before configuring it; the developer profile blocks this class in its warning state. The hosted sanitizer and Verilator source-build steps use the independent hosted profile.

`scripts/check_disk_budget.py` resolves a nonexistent output leaf to its nearest existing parent and measures that filesystem, so output-volume checks work for native Windows paths and native Linux/WSL paths. It rejects Windows path syntax inside Linux and requires callers to translate it first. Its output scan does not follow symlinks or reparse points and reports the five largest generated files. Default per-file limits are 16 MiB for waveforms and 64 MiB for other generated test output. The pinned Verilator workflow scans both disjoint generated roots together: the source/build checkout at `.tools/verilator` and the installed prefix under `$RUNNER_TEMP/verilator-5.052`. Its operation-specific 256 MiB per-file limit accommodates the observed 231,709,824-byte `verilator_bin_dbg`; the installed prefix alone measured 257,576,704 bytes across 127 files on commit `ae0dbd016ed32abfcaec24351e0679f3b892f3db`. The combined tree size and full-build peak remain unmeasured until the aggregate scan completes on the next exact candidate; policy does not treat the installed-prefix measurement as a full-build estimate. The Icarus output tree fails if it grows beyond 22,045,006 bytes, twice the current 11,022,503-byte hosted scan, so a material accumulation of individually small files is surfaced. `build/source` is the reusable current-development CMake output; `build/rtl` and `build/rtl-tools` are reusable current validation outputs whose fixed test binaries and logs are overwritten at deterministic names. Their scans run before and after each gate. `build/clean-validation` and `build/cgx1-clean-candidates` hold only owned temporary runs; the clean CMake runner removes each configuration after testing and candidate validators remove their worktrees on success and failure. Candidate summaries record the candidate tree size and free space before and after cleanup. Registered or unexplained leftovers block duplicate runs and are never silently deleted. CI sanitizer and pinned-tool outputs live for the hosted job. The WSL preflight measures Linux free space on `/tmp`; Windows host free space is measured by the Windows-side preflight. Linux free space does not imply that a WSL virtual disk has returned the same amount to the Windows host. No WSL VHDX compaction or shared-cache purge is performed automatically.

Hosted Linux sanitizer and RTL-tools lanes add GCC/Clang ASan+UBSan and bounded Verilator/Yosys lint, property, and synthesis-smoke checks. These lanes preflight their output volumes and report generated-tree sizes. Those tool lanes do not establish timing, area, power, physical routability, or silicon behavior.

The branch-state gate reports local-to-feature publication and feature-to-main integration separately, including both SHAs, merge bases, ahead/behind counts, open integration-PR query state, latest exact hosted-valid feature SHA, and hosted-green integration debt. `--for-major-slice` blocks a new major slice while main has unmerged commits or hosted-green completeness work remains outside main. Feature milestones integrate through a protected ancestry-preserving PR merge; the completeness branch is then reconciled with main.

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
- full 8-bit vector register addressing;
- current provisional INT32 vector ADD/SUB/AND/OR/XOR/SHL/SHR/ASR results, including 32-bit wraparound, shift-count masking, arithmetic sign fill, source/destination aliasing, active-lane preservation, and illegal vector-op rejection.
- bounded vector-stream stepping over an immutable base-word span, including dependent sequential instructions, PC advancement only on successful execution, unaligned/below-base/out-of-image/out-of-range fetch faults, invalid image bases, unsupported classes, illegal vector opcodes, and the final valid instruction address at the 57-bit boundary.

The stream reference performs software word selection and advances its supplied PC after successful vector execution. It does not model a hardware fetch interface, decode other instruction classes into execution, integrate with RTL issue, or establish frozen opcode assignments. This remains a limited provisional reference, not a shader core or ISA conformance suite.

The pre-hardening fetched-Control baseline had local WSL evidence for CMake build, CTest (26/26), and the RTL gate. The Windows wrapper passed hygiene, integrity, design consistency, their negative controls, and Markdown links, then stopped because `cmake.exe` was unavailable from Windows PATH. These results are historical local-only evidence and do not attest later source trees. The validator now reports working-tree and committed identities separately; revision-specific hosted runs are recorded in `design/cgx1_validation_evidence.json`.

`cgx1_vector_instruction_word_decoder_tb.sv` connects raw per-wave base words through the RTL decoder, resident-wave vector scheduler, and INT32 vector pipeline. It covers two waves issuing under pipeline backpressure, field/lane-mask decode, masked lane-local arithmetic writeback, non-vector raw-word pass-through with independent backpressure, and reserved vector opcode completion. `cgx1_provisional_control_instruction_dispatch_tb.sv` checks termination and branch decode, signed branch target generation, accepted-event-only consumption, raw-handler pass-through, external-event priority, control-event backpressure, round-robin progress, final-PC arithmetic, and reset. The optional instruction-fetch integration composes these decoders with the authoritative workgroup frontend and control-flow PC; raw non-vector acceptance uses the external handler's sequential-PC metadata, while fetched Control opcodes 0 and 1 terminate active lanes and unconditionally branch through normal wave-control events. The integrated frontend test covers fetched vector execution, generic raw-word acceptance, branch to target, invalid-target fault retirement, and fetched termination.

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

The mixed resident execution frontend has a dedicated executable admission reference and SystemVerilog integration test. Its vector dependency scoreboard now also receives pending LSU load destinations. The workgroup layer composes CU-local admission, barriers, pooled VGPR state, the shared/local region allocator, and a decoded LSU. LSU regression coverage includes local store/load, full 57-bit global virtual-address capture through delayed requests and backpressure, rejection of local addresses with nonzero high bits, response/writeback backpressure, per-register dependency stalls, independent wave and same-wave progress, barrier membership during memory wait, store completion, address and downstream faults, kill before/after service, reset epochs, stale responses after reuse, abort/quiescent drain, local-region reuse, and seeded request/fault/reuse stress. The request boundary starts after decode because memory instruction opcode and operand encodings are not defined. Hardware queue/runtime integration, compiler dispatch/completion, and physical memory remain open.

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

The public RTL includes top-level power eligibility, matrix and vector execution, pooled VGPR storage, authoritative workgroup admission and barriers, decoded per-wave control flow and LSU, a CU-local decoded-workgroup dispatcher integrated with the real frontend, and a bounded per-context ring/parser/lifecycle path through quiescent retirement in simulation. The command path is not connected to `cgx1_top`. Hosted CI, global queue arbitration, a frozen command packet ABI, graphics dispatch, multi-CU placement, compiler/runtime lowering, the full per-wave instruction-issue controller, formal verification, synthesis, timing, area, power, physical implementation, and silicon remain unverified or open. Current source contains `cgx1_tile_power_manager` wired to `cgx1_top.tile_enable`; the manager derives eligibility from active/requested board-state limits and per-tile operating/readiness state. The `cgx1_top_tb` passes arbitrary eligible subsets and emergency masking, resolving the fixed P1/P2 mapping concern at this RTL boundary. Global scheduling consumption of the mask, tile-state sequencing, and physical actuation remain open.

RTL simulation is run with Icarus Verilog in SystemVerilog 2012 mode through `scripts/validate_rtl.sh`. The Ubuntu RTL CI workflow runs for every push to `main`, preventing a final reference, schema, or truth-state revision from escaping exact-revision RTL validation. Functional unit and integration testbenches do not replace constrained-random verification, formal work, synthesis, FPGA/emulation, timing closure, or physical implementation.

### Instruction fetch and CU PC integration

`cgx1_instruction_fetch_unit_tb.sv` validates full request identity capture, stable request fields under backpressure, two resident waves waiting independently, out-of-order responses, stale identity rejection, buffered-word hold/consume, terminal fault retention, kill-and-drain, reset with outstanding work using a new external epoch, slot reuse, and a fixed-seed 200-transaction lifecycle-pressure sequence. `cgx1_vector_instruction_word_decoder_tb.sv` also verifies generic class/opcode/destination/source extraction for non-vector words. `cgx1_provisional_control_instruction_dispatch_tb.sv` checks round-robin acceptance of fetched branches and terminations alongside raw-handler traffic, external-event priority, accepted-event backpressure, signed target formation, out-of-range sentinel propagation, unsupported-opcode pass-through, and reset recovery. `cgx1_compute_workgroup_execution_frontend_tb.sv` composes dispatch PC/workgroup ownership, the fetch unit, fetched base-word decoder, and resident INT32 vector execution. It checks a sibling wave executes while another waits, only the accepted fetched vector advances its PC, raw handlers receive common base fields and identity and advance to supplied sequential-PC metadata on acceptance, fetched Control branch opcode 1 changes PC only through its accepted branch event and invalid targets retire through the normal fault path, Control opcode 0 terminates through normal resource release, an outstanding aborted request blocks release, and response faults use ordinary workgroup terminal retirement. The executable ISA reference checks branch offsets and target faults as well as Control termination of active divergent lanes, deferred-lane resumption, and terminal retirement.

The fetch interface is abstract ready/valid and remains disabled unless the consumer enables it. Control opcodes 0 and 1 are provisional; the regression does not establish other non-vector instruction semantics, frozen encodings, extension-word support, execute permission, address translation, caches, physical instruction memory, top-level GPU integration, synthesis, timing, area, power, hosted CI, or silicon behavior. Reset safety depends on the external execution-epoch/flush contract described in [Instruction Fetch](INSTRUCTION_FETCH.md).

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

## CU-local decoded workgroup dispatch

`cgx1_cu_dispatch_scheduler_checks` validates the C++ CU dispatch reference: queue-context identity and capacity, per-context FIFO, tile eligibility, complete-workgroup admission, retry without dropping pending work, permanent rejection, weighted service, aging progress, queue faults, reset cancellation, resource release, and 600 deterministic randomized scheduling cycles. The standalone `cgx1_compute_workgroup_dispatch_scheduler_tb.sv` validates RTL buffering, payload and queue-identity preservation, tile and fault gating, retryable versus terminal admission results, FIFO ordering, aging, and reset. `cgx1_compute_workgroup_dispatch_integration_tb.sv` composes that scheduler with the authoritative workgroup frontend and checks complete admission, duplicate rejection, retention during transient wave-slot pressure, accepted termination, shared-region release, and successful retry.

At the preceding CU-dispatch checkpoint based on `054c1e93bd88983e09026254c81d7dba280d6b12`, the C++ suite passed 25/25 and `bash scripts/validate_rtl.sh` passed under Ubuntu WSL with Icarus Verilog 12.0. That candidate covered one CU's decoded compute workgroup dispatch; global queue management and command packet processing remained open at that revision.

## Bounded command-queue reference

`cgx1_command_queue_runtime_checks` covers a literal provisional packet byte vector, malformed/unsupported commands including fragmented packets with reserved flags, bounded per-context rings, fragmented ingress, physical wrap, full-ring and completion-capacity backpressure, registered queue identity, scheduler retry and end-to-end terminal resource rejection, queue fault/reset, pending-work cancellation, quiescent resident cancellation, same-context duplicate submission tokens, completion correlation, incarnation-safe queue-context reuse, and deterministic randomized scheduling/reuse. The runtime feeds the existing `ComputeUnitDispatchScheduler`; it does not add another residency or resource-admission authority.

At the C++ reference checkpoint based on `dcbc8f82cdb6f1454b057955a4425b68465721d0`, the full WSL CMake build and CTest suite passed 26/26. `scripts/validate_windows.ps1` passed repository hygiene, integrity, design consistency, all negative controls, and local Markdown-link checks, then stopped at CMake configuration because `cmake.exe` was unavailable on Windows PATH. The command packet remains a provisional ABI; hosted CI, command loader/compiler integration, global hardware queue management, synthesis, timing, area, power, physical implementation, and silicon evidence remain unverified.

## RTL command-packet ingress

`cgx1_compute_workgroup_command_packet_parser_tb.sv` exercises the provisional byte format with a golden vector, deterministic inter-byte gaps, captured start-of-packet identity, maximum-fit waves and 256 VGPRs, held output under backpressure, partial-packet reset, framed reserved flags, unsupported opcodes, malformed PC and wave records, fixed-prefix and exact-length errors, trusted-frame consumption, over-capacity rejection, per-context framing faults and parser recovery, and workgroup-ID exhaustion. The bench runs at the default 57-bit address width and at 48 bits to prove that high PC bytes are rejected before truncation. `cgx1_compute_workgroup_command_runtime_tb.sv` connects the parser to the CU dispatcher and checks duplicate submission tokens at distinct packet positions, identity through the admission result, and that parser recovery preserves a complete descriptor already owned by the dispatcher. The new `cgx1_compute_workgroup_command_queue_frontend_tb.sv` adds registered ring identity/incarnations, duplicate and unregistered-context rejection, incomplete-context progress, wrapped packets, completion and CUDS backpressure, untrustworthy-frame pinning, descriptor-preserving ingress recovery, fair service across two ready contexts, seeded randomized byte gaps and repeated ring wrap, plus a continuous producer/consumer/occupancy invariant. The dispatch/frontend test also proves that 32-bit other-workgroup-state values survive the queue and admission path and that `0x00010000` and `0x80000000` reject against a 128-unit CU limit. The barrier test checks 32-bit state retention until workgroup resource release.

The queue frontend feeds one CU-local scheduler in simulation; it is not connected to `cgx1_top`. Parser errors, CU admission results, and final command completions remain separate interfaces. `ingress_recovery_*` still only clears parser fault state and drops unread ring bytes. The separate queue-reset handshake cancels pending work, waits for lifecycle drain and resident memory quiescence, returns the old incarnation and discarded range, and unregisters only after its response is acknowledged. Re-registration obtains a new incarnation.

`cgx1_compute_workgroup_command_lifecycle_tb.sv` checks admission versus final retirement, terminal admission results, pending and resident cancellation, abort backpressure, unmatched retirement, and stable final completion. `cgx1_compute_workgroup_command_lifecycle_integration_tb.sv` composes the real ring, parser, CU dispatcher, lifecycle manager, and authoritative workgroup frontend. It covers successful retirement, unread-byte reset, reset while parsing, cancellation before dispatch, cancellation during multi-cycle admission, multiple resident workgroups, delayed global-memory response holding resource retirement, completion/reset-response backpressure, incarnation reuse, and whole-device reset with ring/parser/lifecycle/resident state present.

The historical queue-ring implementation checkpoint was based on `2fc1721f24d826a0d7f8f68f8df8690d610e14e3`. The 2026-10-03 local-only command-lifecycle record was based on `19f6bdd5a0f5d34f7e943801b75e23b316a36865`; its WSL CMake build, 26 CTest targets, and full Icarus gate passed, while native Windows CMake was unavailable after the Windows repository checks passed. The old changed-file fingerprint is retained as a legacy local-only record, not as an active candidate identity. Hosted CI was not run for that working tree. These local gates do not establish global queue integration, public ABI stability, SRAM inference, synthesis, timing, area, power, physical implementation, or silicon behavior.
