# Production Build and Bring Up Instructions

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [Software stack](SOFTWARE_STACK.md) · [Validation](VALIDATION.md)

This document describes the path from the public architecture package to custom GPU silicon. It does not replace foundry, package vendor, memory vendor, PCIe, electrical safety, or board manufacturing requirements.

## 1. Freeze interfaces

Define and verify:

- compute tile to I/O die fabric;
- HBM4 controller and PHY boundary;
- cache coherence behavior;
- command processor and queue model;
- PCIe BAR and address translation behavior;
- display and media block interfaces;
- firmware mailbox and telemetry registers;
- reset, power, fault, and recovery behavior.

## 2. Implement and verify logic

1. Implement scalar/vector issue, register files, arithmetic, matrix engines, load/store, texture, ray traversal, raster functions, and local caches.
2. Implement package fabric and coherent cache controllers.
3. Implement command processors, hardware queues, preemption, memory protection, and reset handling.
4. Integrate licensed or independently verified high speed PHY and codec blocks where appropriate.
5. Build constrained random verification around interfaces and state transitions.
6. Add formal properties for deadlock freedom, coherence invariants, privilege boundaries, reset behavior, and fault containment.
7. Run compute, shader, memory, and command processor conformance workloads against pre silicon models.

The public SystemVerilog directory is a top level state scaffold. It is not full GPU RTL.

## 3. Physical design

1. Select target process libraries and foundry PDK.
2. Partition compute tiles so long global timing paths do not cross tile boundaries unnecessarily.
3. Place global scheduling, HBM controllers, display/media, PCIe, security, and package cache coordination on the central I/O die.
4. Close the sustained clock target before qualifying the peak clock bin.
5. Complete static timing, IR drop, electromigration, power integrity, clock, thermal, DRC, LVS, DFT, and package bump signoff.
6. Use validation silicon where practical before committing the full package.

## 4. Package and PCB

1. Assemble compute tiles, I/O die, cache structure, and HBM stacks on the advanced package substrate.
2. Validate package warpage and cold plate mounting pressure.
3. Route the card within [PCB Constraints](../pcb/BOARD_CONSTRAINTS.md).
4. Simulate the complete PCIe channel including connector and package discontinuities.
5. Validate external power attach/detach behavior at the electrical boundary.
6. Populate engineering boards with current shunts, temperature probes, compliance access, and debug headers.

## 5. Cooling system

1. Machine the copper cold plate to cover compute and HBM heat sources.
2. Integrate the standalone spreading and fin path used for slot operation.
3. Pressure test the liquid assembly above expected pump head.
4. Leak test before installing electronics.
5. Validate actual loop flow through the final hose and quick disconnect assembly.
6. Tune radiator fan control against coolant and component temperature measurements.

Prototype dimensions and selected components are in [Mechanical Design](MECHANICAL_DESIGN.md).

## 6. Board bring up

1. Begin from P0 Safe Boot.
2. Validate auxiliary controller, SPI flash, telemetry, clocks, and reset tree.
3. Enumerate PCIe conservatively and increase link generation after signal validation.
4. Bring up one compute tile and HBM at reduced clocks.
5. Validate HBM training, ECC, and address behavior.
6. Enable compute tiles incrementally.
7. Validate external 48 V detection with high power rails disabled.
8. Attach the thermal dock and verify flow and temperature interlocks.
9. Enter P3 before attempting P4.
10. Remove external 48 V and verify fallback to P0 without increased slot demand.
11. Characterize each rail before performance work.

## 7. Driver bring up

Follow [Software Stack](SOFTWARE_STACK.md):

1. Linux PCIe enumeration and memory management;
2. reset, interrupts, command submission, fences, faults, telemetry;
3. Vulkan compute;
4. rasterization, depth, texture, presentation;
5. shader compiler expansion;
6. ray tracing;
7. media APIs;
8. Windows display/compute stack;
9. Direct3D 12.

## 8. Manufacturing acceptance

Each production candidate needs traceable results for:

- power rail limits and efficiency;
- PCIe compliance;
- HBM training and error handling;
- display outputs;
- compute and graphics correctness;
- media encode/decode correctness;
- thermal soak;
- fault interlocks;
- dock attach/detach behavior;
- firmware update and recovery;
- driver reset and recovery;
- mechanical fit and mounting pressure.
