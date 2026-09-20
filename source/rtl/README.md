# RTL Scope

[Documentation index](../../docs/README.md) · [Matrix engine architecture](../../docs/MATRIX_ENGINE.md) · [Electrical interface](../../docs/ELECTRICAL_INTERFACE.md) · [Validation](../../docs/VALIDATION.md)

The public RTL currently contains six limited, separately testable boundaries:

- `cgx1_top.sv` covers board power-state gating and compute-tile enable behavior.
- `cgx1_matrix_pipeline_control.sv` covers matrix instruction legality, decode/capture/execute/writeback sequencing, VGPR address generation, source-release events, destination-complete events, 16-cycle reissue control, and matrix-to-matrix RAW/WAW interlocks against older pending destinations.
- `cgx1_matrix_operand_staging.sv` implements the 2 KB capture buffer and separate 2 KB active-execution operand set, with commit on capture cycle 7.
- `cgx1_matrix_wave_scoreboard.sv` tracks one wave's matrix source/destination VGPR reservations and reports ordinary-instruction RAW/WAW/WAR hazards plus matrix VGPR-port conflicts. Reservations use the pipeline controller's latched accepted register bases rather than live post-handshake issue inputs.
- `cgx1_matrix_result_staging.sv` implements the 1 KB eight-register output-result slot and returns one 1,024-bit wave register for each ordered writeback cycle.
- `cgx1_matrix_int8_execution.sv` implements the functional signed INT8 M16N16K32 arithmetic path over the frozen 16-cycle execution schedule.

The matrix RTL implements signed INT8 arithmetic only. FP16, BF16, and FP8 arithmetic remain unimplemented because their contract requires FP32 fused multiply-add semantics. Physical VGPR/storage macros, physical arithmetic decomposition, resident-wave identity/arbitration, and an ordinary vector execution pipeline also remain open. The per-wave scoreboard logic exists, but it is not yet a complete multi-wave compute-unit scheduler.

The matrix issue interface uses payload-dependent backpressure. The producer presents opcode and register bases with `issue_valid`; `issue_ready` may remain low while those presented registers depend on an older pending matrix destination. A dependency stall is not an illegal instruction, so `illegal_issue` remains reserved for malformed opcode, active-mask, or register-layout input.

The matrix controller is checked by `source/rtl/tests/cgx1_matrix_pipeline_control_tb.sv`. The testbench verifies invalid issue rejection, the 8/16/8 stage schedule, exact capture/writeback addresses, source/destination completion timing, conflict-free bank classes, matrix-to-matrix RAW/WAW dependency stalls, and a three-operation independent steady stream with a 16-cycle issue interval.

The operand staging block is checked by `source/rtl/tests/cgx1_matrix_operand_staging_tb.sv`. That test verifies the full A/B/C capture contents, the cycle-7 active-load pulse, preservation of the first active operand set during cycles 0 through 6 of the next capture, and replacement only when the second capture commits.

The per-wave scoreboard is checked by `source/rtl/tests/cgx1_matrix_wave_scoreboard_tb.sv`. That integration test wires the scoreboard to the matrix pipeline controller's reservation/release/completion events and verifies ordinary RAW/WAW/WAR decisions, capture read-port conflicts, writeback write-port conflicts, and safe unrelated accesses.

The output-result staging block is checked by `source/rtl/tests/cgx1_matrix_result_staging_tb.sv`. That test verifies complete result loading, ordered eight-cycle writeback data selection, the final consumed pulse, slot release, and safe reuse.

The signed INT8 arithmetic block is checked by `source/rtl/tests/cgx1_matrix_int8_execution_tb.sv`. The testbench covers canonical full-tile fragment mapping, patterned signed data, signed extremes, 16 execution cycles, cycle-15 result validity, and explicit modulo-`2^32` overflow. Its simulation-evidence status is recorded separately in the machine-readable architecture file.

Run the RTL gate with:

~~~bash
./scripts/validate_rtl.sh
~~~

The gate requires Icarus Verilog and uses SystemVerilog 2012 mode. GitHub runs the same test on Ubuntu when RTL or its matrix architecture inputs change.

A complete device still requires verified RTL or equivalent hardware implementation for arithmetic execution, register storage, staging, caches, coherent fabric, HBM controllers and PHYs, raster, texture, ray traversal, command processors, PCIe, display, media, security, clock/reset, debug, testability, and fault management.

The power-state scaffold keeps one important control rule explicit: loss of external 48 V or valid coolant flow during P3/P4 returns the state to P0 and disables compute tiles.
