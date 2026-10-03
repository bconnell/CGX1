# RTL Scope

[Documentation index](../../docs/README.md) · [Matrix engine architecture](../../docs/MATRIX_ENGINE.md) · [Electrical interface](../../docs/ELECTRICAL_INTERFACE.md) · [Validation](../../docs/VALIDATION.md)

The public RTL currently contains limited, separately testable modules and composed execution boundaries:

- `cgx1_top.sv` retains board-state fallback and connects `cgx1_tile_power_manager.sv`, which publishes the scheduler-eligibility mask and emergency isolation request from per-tile status.
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
- `cgx1_workgroup_residency_barrier.sv` owns only committed group membership, local-to-actual-slot maps, arrival masks, and barrier generations. It has no physical VGPR-row allocator.
- `cgx1_wave_control_flow.sv` owns bounded per-resident-wave PC, branch/loop, call/return, and live/active-lane state after decode. Barrier reconvergence is checked after resolving each workgroup-local wave through the residency authority's actual slot map.
- `cgx1_compute_workgroup_execution_frontend.sv` selects free slots from the mixed frontend's actual allocator map, reserves each exact per-wave VGPR count, waits for sanitization, activates each allocation, and commits the whole group only after the final activation. A late first-fit failure releases every earlier reservation before reporting failure. Matrix and vector request arrays are gated by committed live nonwaiting membership and actual active allocation state.
- `cgx1_compute_workgroup_lsu.sv` accepts one decoded memory operation per wave, captures request identity and operands, routes zero-extended 32-bit local offsets through the admitted workgroup region, and exposes full 57-bit global virtual addresses at the tagged ready/valid boundary. Per-wave waits, load-destination dependencies, response writeback, store completion, fault delivery, cancellation, and reset-epoch stale-response rejection are integrated with the workgroup frontend.
- Terminal waves are removed from issue and barrier participation immediately. The workgroup frontend waits for matrix/vector/LSU busy state and accepted memory traffic to quiesce before requesting release through the pooled execution subsystem; the subsystem's release guard remains authoritative for in-flight VGPR traffic. A real shared/local-memory range remains owned until both its allocator and the pooled VGPR allocator can accept final release in the same cycle; a late VGPR allocation failure releases the provisional range before reporting dispatch failure.
- `cgx1_compute_workgroup_execution_frontend_tb.sv` exercises the actual mixed execution path, variable VGPR counts, maximum-fit and aggregate failures, shared-memory maximum fit, fragmented range rejection and reuse, VGPR-failure rollback across both allocators, sibling matrix/vector execution, barrier waiting during memory wait, load dependencies, delayed global responses, store completion, terminal busy release, kill, abort, reset, stale-response rejection, and randomized lifecycle sequences. The simulation covers the integrated decoded LSU boundary; full queue/runtime integration and physical implementation remain open.


The matrix RTL implements signed INT8 arithmetic only. FP16, BF16, and FP8 arithmetic remain unimplemented because their contract requires FP32 fused multiply-add semantics. Resident-wave matrix identity/arbitration coexists with resident INT32 vector execution, decoded per-wave control flow, and the integrated per-wave LSU over shared pooled-VGPR storage. The exact RTL candidate at `68cb2c3bb1c68df8c662a82959f1db8119deb8d0` passed `scripts/validate_rtl.sh` locally and hosted RTL CI. No foundry memory macro, timing, area, or power claim is made. Base-ISA control/memory opcode decode, fetch, compiler/runtime lowering, a complete CU scheduler, scalar execution, physical global memory, and physical implementation remain open.

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

The workgroup boundary has two RTL checks: `source/rtl/tests/cgx1_workgroup_residency_barrier_tb.sv` exercises membership, generations, arbitrary slot maps, busy-arrival exclusion, survivor updates, and allocator-release completion; `source/rtl/tests/cgx1_compute_workgroup_execution_frontend_tb.sv` composes the admission controller, this membership-only barrier, the mixed matrix/vector execution frontend, and its actual pooled VGPR allocator. The integrated test covers complete admission, exact per-wave counts, fragmented rollback, runnable siblings, matrix/vector execution, deferred fault release, kill, active and partial-admission reset, and 5,100 seeded randomized barrier-arrival transactions.

`cgx1_wave_control_flow_tb.sv` exercises nested valid and malformed joins, calls/returns, loop call-depth handling, lane termination, invalid masks, stack limits, reset, and a deterministic randomized control trace. The integrated frontend test additionally checks accepted PC advancement, divergent vector writes, and barrier reconvergence with workgroups mapped to nonzero resident slots. These tests cover post-decode control only; fetch/decode, opcode encoding, compiler lowering, the complete CU scheduler, runtime integration, and physical implementation remain open.

The `cgx1_cu_shared_local_memory` block is instantiated by workgroup admission as the authoritative byte-range allocator. Its standalone testbench covers range allocation, wave32 dword requests, bank conflicts, tagged responses, request faults, cancellation drain, and reset/reuse. In the workgroup frontend, the LSU routes 32-bit local offsets through that owned region and forwards all 57 global virtual-address bits through an abstract ready/valid interface; accepted memory activity participates in barrier membership, wave issue masking, fault/kill cleanup, and quiescent resource release. Hardware queues, runtime integration, base-ISA memory decode, physical global memory, and a complete CU scheduler remain open; Icarus results do not establish synthesis or physical implementation.

Run the RTL gate with:

~~~bash
./scripts/validate_rtl.sh
~~~

The gate requires Icarus Verilog and uses SystemVerilog 2012 mode. GitHub runs the same RTL gate on Ubuntu for every push to `main`, so the final published revision receives its own RTL validation run.

A complete device still requires FP16/BF16/FP8 matrix arithmetic, physical register/storage and arithmetic implementation, caches, coherent fabric, HBM controllers and PHYs, raster, texture, ray traversal, command processors, PCIe, display, media, security, clock/reset, debug, testability, and fault management.

The tile power manager caps each reported tile state against the stricter active/requested P-state, requires power-good, stable clocks, coherence readiness, and released isolation, and never infers a fixed tile count from P1/P2. Hardware or thermal faults, dock power/coolant loss while dock operation is active or requested, and reset immediately clear eligibility and assert all-tile isolation request; `cgx1_top.sv` retains the registered P0 fallback. Per-tile state is external status input. The RTL does not claim a tile-state sequencer, physical gate timing, DVFS behavior, watt allocation, or measured power.
