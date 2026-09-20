# RTL Scope

[Documentation index](../../docs/README.md) · [Electrical interface](../../docs/ELECTRICAL_INTERFACE.md) · [Validation](../../docs/VALIDATION.md)

`cgx1_top.sv` covers the public power state gating and compute tile enable boundary.

It does **not** implement the complete GPU.

A complete device still requires verified RTL or equivalent hardware implementation for compute issue/execution, caches, coherent fabric, HBM controllers and PHYs, raster, texture, ray traversal, command processors, PCIe, display, media, security, clock/reset, debug, testability, and fault management.

The current scaffold keeps one important control rule explicit: loss of external 48 V or valid coolant flow during P3/P4 returns the state to P0 and disables compute tiles.
