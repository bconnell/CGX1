# RTL Scope

[Documentation index](../../docs/README.md) · [Matrix engine architecture](../../docs/MATRIX_ENGINE.md) · [Electrical interface](../../docs/ELECTRICAL_INTERFACE.md) · [Validation](../../docs/VALIDATION.md)

The public RTL currently contains limited, separately testable modules and composed execution boundaries:

- `cgx1_top.sv` covers board power-state gating and compute-tile enable behavior.
- `cgx1_matrix_pipeline_control.sv` covers matrix instruction legality, decode/capture/execute/writeback sequencing, VGPR address generation, source-release events, destination-complete events, 16-cycle reissue control, and matrix-to-matrix RAW/WAW interlocks against older pending destinations.
- `cgx1_matrix_operand_staging.sv` implements the 2 KB capture buffer and separate 2 KB active-execution operand set, with commit on capture cycle 7.
- `cgx1_matrix_wave_scoreboard.sv` tracks one wave's matrix source/destination VGPR reservations and reports ordinary-instruction RAW/WAW/WAR hazards plus matrix VGPR-port conflicts. Reservations use the pipeline controller's latched accepted register bases rather than live post-handshake issue inputs.
- `cgx1_matrix_result_staging.sv` implements the 1 KB eight-register output-result slot and returns one 1,024-bit wave register for each ordered writeback cycle.
- `cgx1_matrix_int8_execution.sv` implements the functional signed INT8 M16N16K32 arithmetic path over the frozen 16-cycle execution schedule.
- `cgx1_matrix_int8_path.sv` composes capture/active staging, opcode-6 INT8 execution, cycle-0 result bypass, result staging, and ordered writeback.
- `cgx1_matrix_int8_engine_shell.sv` wraps one controller, one per-wave scoreboard, and the INT8 path behind the external whole-wave VGPR interface; it accepts only opcode `0x6` at this boundary.
- `cgx1_matrix_resident_wave_arbiter.sv` selects parameterized resident-wave matrix requests with round-robin fairness.
- `cgx1_matrix_resident_wave_scoreboard.sv` routes per-wave reservation state and ordinary issue admission by resident-wave slot.
- `cgx1_resident_wave_vgpr_file.sv` implements the earlier parameterized per-slot logical VGPR storage boundary as eight modulo-8 bank classes.
- `cgx1_pooled_vgpr_mapper.sv` and `cgx1_pooled_vgpr_restore_mapper.sv` translate exact-count Active and sanitized-Reserved architectural VGPR accesses into pooled row/bank addresses.
- `cgx1_resident_wave_vgpr_allocator.sv` implements first-fit physical-row reservation, serialized round-robin validity invalidation, activation, and quiescent release.
- `cgx1_pooled_vgpr_storage.sv` implements pooled whole-wave data plus per-register validity, alias broadcast, bank-conflict rejection, and first-touch masked-write sanitization.
- `cgx1_matrix_vgpr_preflight.sv` and `cgx1_matrix_request_preflight_array.sv` gate legal matrix requests on exact allocation bounds and initialized operands without swallowing controller-owned illegal instructions.
- `cgx1_pooled_vgpr_matrix_subsystem.sv` composes allocation, restore, preflight, pooled storage, and matrix VGPR access arbitration.
- `cgx1_matrix_int8_resident_engine.sv` remains the resident-wave matrix control/arithmetic boundary with an external wave-tagged VGPR interface.
- `cgx1_matrix_int8_pooled_resident_engine.sv` connects that resident signed INT8 engine to the pooled VGPR subsystem.
- `cgx1_pooled_vgpr_ordinary_frontend.sv` maps ordinary vector source/destination VGPRs into the same exact-count pooled row/bank space.
- `cgx1_pooled_vgpr_ordinary_read_sequencer.sv` preserves one-cycle conflict-free reads and serializes distinct same-bank source pairs without exposing stale data.
- `cgx1_pooled_vgpr_shared_port_arbiter.sv` gives accepted matrix capture/writeback fixed-cycle priority while alternating contested ordinary/restore transfers.
- `cgx1_pooled_vgpr_execution_subsystem.sv` makes allocation, validity, storage, matrix traffic, ordinary traffic, restore, and release safety one shared authority.
- `cgx1_vector_int32_alu.sv` and `cgx1_vector_int32_pipeline.sv` implement the candidate wave32 INT32 ADD/SUB/AND/OR/XOR/SHL/LSR/ASR read-execute-writeback path; illegal opcodes complete before VGPR operand access.
- `cgx1_vector_resident_wave_scheduler.sv` and `cgx1_resident_vector_execution_frontend.sv` provide parameterized resident-wave vector selection and payload routing; the scheduler rejects slot-index widths that cannot represent every configured slot.
- `cgx1_matrix_vector_hazard_guard.sv`, `cgx1_matrix_vector_hazard_array.sv`, and `cgx1_matrix_vector_issue_arbiter.sv` define cross-pipeline dependency and same-cycle issue exclusion boundaries.
- `cgx1_compute_int8_vector_execution_frontend.sv` composes resident signed INT8 matrix execution and resident INT32 vector execution over one unified pooled-VGPR authority, gates legal matrix issue with live vector locks, gates selected vector issue with the matrix scoreboard, and prevents same-edge matrix/vector acceptance.
- `cgx1_workgroup_residency_barrier.sv` atomically reserves wave slots, a complete logical pooled-VGPR row map, scalar/predicate state, shared/local bytes, barrier contexts, and additional workgroup-local state before admitting any wave. It tracks per-wave barrier arrival/generation while retaining all group waves; a waiting wave is nonissuable and its nonarrived siblings remain eligible. Retirement, fault/kill, whole-group abort, and reset update or destroy the reservation and barrier state. The RTL test drives issuable residents into `cgx1_vector_resident_wave_scheduler.sv`. This remains a standalone admission/barrier control boundary and does not yet allocate through the execution subsystem or connect to full CU dispatch, memory, fault, retirement, or shared/local-memory datapaths.


The matrix RTL implements signed INT8 arithmetic only. FP16, BF16, and FP8 arithmetic remain unimplemented because their contract requires FP32 fused multiply-add semantics. Resident-wave matrix identity/arbitration now coexists with a resident-wave INT32 vector execution path and shared pooled-VGPR arbitration. The earlier banked per-slot VGPR storage boundary and the pooled resident-wave allocation/storage path pass the local RTL simulation workflow. The current local working-tree candidate passes `scripts/validate_rtl.sh` with Icarus 12.0 in Ubuntu WSL. No foundry memory macro, timing, area, or power claim is made. The mixed execution frontend composes resident signed INT8 matrix and resident INT32 vector execution over the same pooled-VGPR authority and derives vector/matrix dependencies from the matrix scoreboard. A full compute-unit scheduler, scalar/control execution, memory execution, and physical implementation remain open.

The matrix issue interface uses payload-dependent backpressure. The producer presents opcode and register bases with `issue_valid`; `issue_ready` may remain low while those presented registers depend on an older pending matrix destination. While matrix work remains in flight, missed dependency-blocked opportunities stay aligned to the frozen 16-cycle issue cadence so capture cannot slide into an older writeback window. Once the pipeline drains, a new operation may begin immediately. A dependency stall is not an illegal instruction, so `illegal_issue` remains reserved for malformed opcode, active-mask, or register-layout input.

The matrix controller is checked by `source/rtl/tests/cgx1_matrix_pipeline_control_tb.sv`. The testbench verifies invalid issue rejection, the 8/16/8 stage schedule, exact capture/writeback addresses, source/destination completion timing, conflict-free bank classes, matrix-to-matrix RAW/WAW dependency stalls, and a three-operation independent steady stream with a 16-cycle issue interval.

The operand staging block is checked by `source/rtl/tests/cgx1_matrix_operand_staging_tb.sv`. That test verifies the full A/B/C capture contents, the cycle-7 active-load pulse, preservation of the first active operand set during cycles 0 through 6 of the next capture, and replacement only when the second capture commits.

The per-wave scoreboard is checked by `source/rtl/tests/cgx1_matrix_wave_scoreboard_tb.sv`. That integration test wires the scoreboard to the matrix pipeline controller's reservation/release/completion events and verifies ordinary RAW/WAW/WAR decisions, capture read-port conflicts, writeback write-port conflicts, and safe unrelated accesses.

The output-result staging block is checked by `source/rtl/tests/cgx1_matrix_result_staging_tb.sv`. That test verifies complete result loading, ordered eight-cycle writeback data selection, the final consumed pulse, slot release, and safe reuse.

The signed INT8 arithmetic block is checked by `source/rtl/tests/cgx1_matrix_int8_execution_tb.sv`. The testbench covers canonical full-tile fragment mapping, patterned signed data, signed extremes, 16 execution cycles, cycle-15 result validity, and explicit modulo-`2^32` overflow. The standalone arithmetic block has passed RTL CI.

The composed INT8 path is checked by `source/rtl/tests/cgx1_matrix_int8_path_tb.sv`. That testbench models architectural wave registers and verifies a full opcode-6 capture, execute, cycle-0 bypass, and eight-register writeback transaction. The integrated path has passed the repository RTL simulation gate.

The one-wave INT8 engine shell is checked by `source/rtl/tests/cgx1_matrix_int8_engine_shell_tb.sv`. That testbench verifies non-INT8 opcode rejection, register reservation/release, ordinary RAW/WAR hazard reporting, and a complete signed INT8 result transaction through the shell's external VGPR interface. The single-engine INT8 shell has passed the repository RTL simulation gate.

The resident-wave INT8 boundary is checked by `source/rtl/tests/cgx1_matrix_int8_resident_engine_tb.sv`. The test uses four resident-wave slots to exercise round-robin request selection, wave-local dependency behavior, wave-tagged VGPR transactions, per-wave ordinary hazard admission, and invalid-request tagging. The slot count is parameterized and is not frozen by the test.

The banked resident-wave VGPR storage is checked by `source/rtl/tests/cgx1_resident_wave_vgpr_file_tb.sv`. The test verifies modulo-8 source placement, exact A/B alias broadcast, adjacent C/D reads, identical architectural register numbers in independent resident waves, one-register writeback visibility, and canonical lane ordering on the 1,024-bit whole-wave buses. This test passes in the current local RTL gate; physical macros and timing/area/power closure remain unvalidated.

The complete-workgroup residency and barrier controller is checked by `source/rtl/tests/cgx1_workgroup_residency_barrier_tb.sv`, paired with the executable CU scheduler reference test. The RTL configuration checks atomic maximum-fit admission, failures that cannot be deferred (including fragmented VGPR rows), transient aggregate-resource pressure, all-wave/staggered/arbitrary barrier arrivals, issue eligibility of nonarrived siblings, generation reuse, multiple groups, wave retirement/fault while peers wait, group abort, reset, and 5,000 seeded randomized cycles. This is a logical resource-admission and barrier-control test; it does not establish composition with the physical pooled allocator or full CU integration.

Run the RTL gate with:

~~~bash
./scripts/validate_rtl.sh
~~~

The gate requires Icarus Verilog and uses SystemVerilog 2012 mode. GitHub runs the same RTL gate on Ubuntu for every push to `main`, so the final published revision receives its own RTL validation run.

A complete device still requires FP16/BF16/FP8 matrix arithmetic, physical register/storage and arithmetic implementation, caches, coherent fabric, HBM controllers and PHYs, raster, texture, ray traversal, command processors, PCIe, display, media, security, clock/reset, debug, testability, and fault management.

The power-state scaffold keeps one important control rule explicit: loss of external 48 V or valid coolant flow during P3/P4 returns the state to P0 and disables compute tiles.
