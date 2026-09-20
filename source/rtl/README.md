# RTL Scope

[Documentation index](../../docs/README.md) · [Matrix engine architecture](../../docs/MATRIX_ENGINE.md) · [Electrical interface](../../docs/ELECTRICAL_INTERFACE.md) · [Validation](../../docs/VALIDATION.md)

The public RTL currently contains two limited, separately testable control boundaries:

- `cgx1_top.sv` covers board power-state gating and compute-tile enable behavior.
- `cgx1_matrix_pipeline_control.sv` covers matrix instruction legality, decode/capture/execute/writeback sequencing, VGPR address generation, source-release events, destination-complete events, and 16-cycle reissue control.

The matrix control module does **not** implement FP16, BF16, FP8, or INT8 arithmetic. It also does not implement the physical VGPR storage macros, matrix staging memories, cross-lane data wiring, scoreboard storage, or a complete compute unit.

The matrix controller is checked by `source/rtl/tests/cgx1_matrix_pipeline_control_tb.sv`. The testbench verifies invalid issue rejection, the 8/16/8 stage schedule, exact capture/writeback addresses, source/destination completion timing, conflict-free bank classes, and a three-operation steady stream with a 16-cycle issue interval.

Run the RTL gate with:

~~~bash
./scripts/validate_rtl.sh
~~~

The gate requires Icarus Verilog and uses SystemVerilog 2012 mode. GitHub runs the same test on Ubuntu when RTL or its matrix architecture inputs change.

A complete device still requires verified RTL or equivalent hardware implementation for arithmetic execution, register storage, staging, caches, coherent fabric, HBM controllers and PHYs, raster, texture, ray traversal, command processors, PCIe, display, media, security, clock/reset, debug, testability, and fault management.

The power-state scaffold keeps one important control rule explicit: loss of external 48 V or valid coolant flow during P3/P4 returns the state to P0 and disables compute tiles.
