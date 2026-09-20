# RTL Scope

[Documentation index](../../docs/README.md) · [Matrix engine architecture](../../docs/MATRIX_ENGINE.md) · [Electrical interface](../../docs/ELECTRICAL_INTERFACE.md) · [Validation](../../docs/VALIDATION.md)

The public RTL currently contains four limited, separately testable boundaries:

- `cgx1_top.sv` covers board power-state gating and compute-tile enable behavior.
- `cgx1_matrix_pipeline_control.sv` covers matrix instruction legality, decode/capture/execute/writeback sequencing, VGPR address generation, source-release events, destination-complete events, 16-cycle reissue control, and matrix-to-matrix RAW/WAW interlocks against older pending destinations.
- `cgx1_matrix_operand_staging.sv` implements the 2 KB capture buffer and separate 2 KB active-execution operand set, with commit on capture cycle 7.
- `cgx1_matrix_wave_scoreboard.sv` tracks one wave's matrix source/destination VGPR reservations and reports ordinary-instruction RAW/WAW/WAR hazards plus matrix VGPR-port conflicts. Reservations use the pipeline controller's latched accepted register bases rather than live post-handshake issue inputs.

The matrix RTL does **not** implement FP16, BF16, FP8, or INT8 arithmetic. It also does not implement output-result staging, physical VGPR/storage macros, cross-lane arithmetic delivery wiring, resident-wave identity/arbitration, or an ordinary vector execution pipeline. The per-wave scoreboard logic exists, but it is not yet a complete multi-wave compute-unit scheduler.

The matrix issue interface uses payload-dependent backpressure. The producer presents opcode and register bases with `issue_valid`; `issue_ready` may remain low while those presented registers depend on an older pending matrix destination. A dependency stall is not an illegal instruction, so `illegal_issue` remains reserved for malformed opcode, active-mask, or register-layout input.

The matrix controller is checked by `source/rtl/tests/cgx1_matrix_pipeline_control_tb.sv`. The testbench verifies invalid issue rejection, the 8/16/8 stage schedule, exact capture/writeback addresses, source/destination completion timing, conflict-free bank classes, matrix-to-matrix RAW/WAW dependency stalls, and a three-operation independent steady stream with a 16-cycle issue interval.

The operand staging block is checked by `source/rtl/tests/cgx1_matrix_operand_staging_tb.sv`. That test verifies the full A/B/C capture contents, the cycle-7 active-load pulse, preservation of the first active operand set during cycles 0 through 6 of the next capture, and replacement only when the second capture commits.

The per-wave scoreboard is checked by `source/rtl/tests/cgx1_matrix_wave_scoreboard_tb.sv`. That integration test wires the scoreboard to the matrix pipeline controller's reservation/release/completion events and verifies ordinary RAW/WAW/WAR decisions, capture read-port conflicts, writeback write-port conflicts, and safe unrelated accesses.

Run the RTL gate with:

~~~bash
./scripts/validate_rtl.sh
~~~

The gate requires Icarus Verilog and uses SystemVerilog 2012 mode. GitHub runs the same test on Ubuntu when RTL or its matrix architecture inputs change.

A complete device still requires verified RTL or equivalent hardware implementation for arithmetic execution, register storage, staging, caches, coherent fabric, HBM controllers and PHYs, raster, texture, ray traversal, command processors, PCIe, display, media, security, clock/reset, debug, testability, and fault management.

The power-state scaffold keeps one important control rule explicit: loss of external 48 V or valid coolant flow during P3/P4 returns the state to P0 and disables compute tiles.
