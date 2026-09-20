# CGX 1 Engineering Specification

[Documentation index](README.md) · [Project status](STATUS.md) · [Mechanical design](MECHANICAL_DESIGN.md) · [Electrical interface](ELECTRICAL_INTERFACE.md) · [Software stack](SOFTWARE_STACK.md)

## 1. Design objective

CGX 1 targets high compute and memory throughput in a low profile PCIe add in card. The architecture separates the card envelope from bulk power delivery and full load heat rejection. Full power arrives from an external 48 V source and the liquid loop transports most full load heat to an external thermal dock.

The design covers two broad host classes:

- low profile OEM desktops where internal power and cooling are limited;
- compact and conventional tower systems where a short card and independent power path improve installation flexibility.

Exact chassis fit depends on physical clearance, slot geometry, firmware behavior, and the host PCIe implementation.

## 2. Mechanical architecture

### 2.1 Card envelope

| Parameter | Target | Notes |
|---|---:|---|
| PCB | 167.5 × 68.5 mm | Low profile board target |
| Installed thickness | 39.5 mm | Dual slot envelope |
| Bracket | Low profile or full height | Replaceable two slot metalwork |
| Package target | ≤ 55 × 55 mm | Compute, I/O, cache, HBM package region |
| Card fans | 2 × 50 × 50 × 10 mm | Same Sky CFM-5010B-170-361-22 reference |

High current power and coolant services exit at the rear bracket. The primary package region is kept close to the slot support region to reduce board bending moment.

The card CAD and selected fan reference are documented in [Mechanical Design](MECHANICAL_DESIGN.md).

### 2.2 External thermal dock

The dock contains the low voltage cooling and monitoring hardware. Mains conversion remains in a separate certified 48 V AC/DC supply.

| Parameter | Target/reference | Notes |
|---|---:|---|
| Dock outer envelope | 310 × 210 × 75 mm | Revised from the earlier undersized envelope |
| Radiator | Corsair XR5 240 | 280 × 120 × 30 mm |
| Radiator fans | 2 × 120 × 120 × 25 mm class | Pressure oriented PWM fans |
| Pump/reservoir | Alphacool ES Reservoir DDCzero 1U, part 14571 | 112 × 57 × 41.95 mm |
| Nominal coolant flow | 1.5 L/min | Thermal analysis point |
| Quick disconnects | Dry break | Supply and return |

The revised dock dimensions leave separate volumes for the 55 mm radiator/fan stack and the pump/reservoir, plus enclosure walls, fittings, wiring, sensors, and service clearance.

See [Mechanical Design](MECHANICAL_DESIGN.md).

## 3. Silicon architecture

### 3.1 Process and package

The preferred first implementation process is TSMC N2P. TSMC A16 remains a later process option. TSMC states that N2P and A16 volume production is scheduled for the second half of 2026, with A16 using backside power delivery for dense HPC designs. See [Public Sources](SOURCES.md).

The package target contains:

- four graphics compute tiles;
- one central I/O, display, media, security, fabric, and cache controller die;
- two 36 GB HBM4 stacks;
- a 512 MB package level stacked SRAM cache target;
- a silicon interposer or equivalent advanced package substrate.

Nominal package envelope target: no larger than 55 × 55 mm.

### 3.2 Compute organization

| Item | Target | Derivation or purpose |
|---|---:|---|
| Compute tiles | 4 | Physical compute partition |
| Compute units per tile | 50 | 200 total |
| Compute units total | 200 | Architecture target |
| FP32 lanes per compute unit | 128 | 25,600 total |
| FP32 lanes total | 25,600 | Peak arithmetic input |
| Matrix engines per compute unit | 4 | One per SIMD32 partition; physical shape, mapping, instruction form, and issue model are defined architecture targets |
| Ray traversal/intersection engines per compute unit | 1 | Architecture target, throughput not yet frozen |
| ROPs | 256 | Architecture target |
| Sustained full clock | 2.65 GHz | Full load target |
| Peak clock | 2.80 GHz | Peak arithmetic target |

Peak FP32 arithmetic target:

```text
25,600 lanes × 2 operations/FMA × 2.80 GHz = 143.36 TFLOPS
```

This is a theoretical arithmetic target, not measured application performance.

Matrix-engine architecture targets are defined separately in [Matrix Engine Architecture](MATRIX_ENGINE.md). FP16/BF16 use M16N16K16 tiles; FP8/INT8 use M16N16K32 tiles. With a 16-cycle per-engine issue interval, the derived dense peak-clock targets are 1,146.88 TFLOPS for FP16/BF16 and 2,293.76 TFLOPS/TOPS for FP8/INT8. These are architectural arithmetic targets, not measured silicon or application results.

### 3.3 Cache hierarchy

- 128 KB combined L1/shared memory per compute unit target.
- 16 MB L2 slice per compute tile.
- 64 MB aggregate L2 target.
- 512 MB package level stacked SRAM victim/cache layer target.

The package level cache is intended to reduce HBM traffic and reduce sensitivity to older host PCIe links and systems without Resizable BAR.

### 3.4 Memory

- 2 × 36 GB HBM4 baseline.
- 72 GB baseline VRAM.
- Up to 3.3 TB/s target per stack.
- Up to 6.6 TB/s aggregate peak target.
- ECC enabled by default for development and compute use.
- 96 GB remains a future capacity target if two 48 GB HBM4 stacks satisfy package, thermal, supply, and controller requirements.

Samsung currently publishes HBM4 capacities through 36 GB on 12 layers at up to 3.3 TB/s per stack, with 16 layer configurations extending to 48 GB. See [Public Sources](SOURCES.md).

### 3.5 Execution model

Each compute unit contains four SIMD32 partitions, giving the existing 128 FP32 lanes per CU. Native wave size is 32 lanes. The first instruction contract uses a 32-bit base word and an optional 32-bit extension word.

The dedicated matrix-engine target uses wave32 cooperative execution with FP16, BF16, OCP FP8 E4M3/E5M2, and signed INT8 baseline profiles. Floating profiles accumulate to FP32; signed INT8 accumulates to signed INT32. Physical matrix tile dimensions, issue rate, and throughput remain unfrozen.

See [ISA and Execution Model](ISA.md) and [Matrix Engine Architecture](MATRIX_ENGINE.md).

### 3.6 Graphics and texture organization

The four compute tiles form one logical GPU. Each tile targets 25 texture blocks, four raster partitions and 64 color/depth result lanes. Render work uses dynamic 32 × 32 pixel macro-tile ownership so ordered render-target updates can remain local to one tile while active.

The texture target is 100 blocks total at four bilinear sample results per block per cycle under the simple cache-resident arithmetic case. At 2.80 GHz this is a 1,120 Gsamples/s arithmetic ceiling, not a guaranteed application rate.

See [Graphics Pipeline](GRAPHICS_PIPELINE.md) and [Texture and Compression](TEXTURE_COMPRESSION.md).

### 3.7 Chiplet fabric

The central I/O/cache die maintains directory coherence across four write-back tile L2 caches. Aggregate tile read payload budget is 7.2 TB/s so the fabric target does not undercut the 6.6 TB/s HBM4 peak before cache effects.

UCIe 3.0 is the preferred die-to-die PHY/management reference. UCIe compliance and physical lane counts are not currently claimed.

See [Chiplet Fabric](CHIPLET_FABRIC.md).

### 3.8 Virtual memory

The architecture targets 57-bit GPU virtual addresses, 4 KiB/64 KiB/2 MiB pages, 64 KiB preferred VRAM pages and replayable page faults. PCIe ATS, PRI and PASID are optional host accelerators; basic operation does not require them.

See [Virtual Memory](VIRTUAL_MEMORY.md).

### 3.9 Scheduling and preemption

The first scheduler target provides 64 resident hardware queue contexts, eight priorities, power-aware placement and weighted fair scheduling with aging. Mandatory preemption is workgroup-boundary for compute and draw/dispatch-packet boundary for graphics. Recovery escalates engine, tile, then device reset.

See [Scheduling and Preemption](SCHEDULING_PREEMPTION.md).

## 4. Host interface

### 4.1 PCIe

- Native target: PCIe Gen 6 ×16.
- Backward interoperability target through earlier PCIe generations.
- Non Resizable BAR support through a bounded aperture and command buffer paging design.
- Local VRAM and package cache reduce dependence on host link bandwidth.

PCI SIG states that PCIe 6.0 maintains backward compatibility with previous PCIe generations. Final card compliance still requires the complete electrical and protocol implementation.

### 4.2 Boot behavior

The card enters P0 Safe Boot after reset. Early firmware reads:

- negotiated PCIe generation and width;
- host firmware capabilities;
- external 48 V presence;
- coolant flow and temperature sensors;
- slot voltage and current telemetry.

The card cannot enter P3 or P4 when required dock conditions are absent.

## 5. Power states

| State | Board limit | Host slot limit | Behavior |
|---|---:|---:|---|
| P0 Safe Boot | 25 W | 25 W | Reset, diagnostics, unknown host, fault fallback |
| P1 Slot Eco | 45 W | 45 W | Qualified reduced slot operation |
| P2 Slot Max | 70 W | 70 W | Qualified maximum slot operation |
| P3 Dock Quiet | 220 W | 25 W | External 48 V and valid coolant flow required |
| P4 Dock Full | 360 W | 25 W | External 48 V and valid coolant flow required |
| Electrical transient ceiling | 450 W | External path | Short electrical excursion only |

If external 48 V or valid coolant flow is lost in P3/P4, the reference controller returns to P0 at 25 W. This avoids increasing motherboard slot demand during a dock fault.

See [Electrical Interface](ELECTRICAL_INTERFACE.md).

### 5.1 Internal power management

P0-P4 remain board-level electrical and safety envelopes. They do not prescribe a fixed active compute-tile count.

The I/O-die power-management controller targets independent per-tile DVFS, clock gating, and whole-tile retention/off states inside the active P-state budget. The scheduler uses a power-manager eligibility mask rather than manipulating rails directly.

Exact tile voltage/frequency points are not frozen. The architecture retains the 0.55 V to 0.90 V GPU-core target range and the 2.65/2.80 GHz clock targets, but a real V/F curve requires physical timing, power, process, and silicon characterization.

See [Power Management](POWER_MANAGEMENT.md).

## 6. Voltage regulation

The high power input uses 48 V to reduce cable current. A separate certified AC/DC supply creates the 48 V rail. The thermal dock handles low voltage distribution and monitoring. The card uses intermediate conversion followed by point of load rails.

Principal target rails:

- GPU core: 0.55 V to 0.90 V adaptive;
- SRAM/cache: 0.65 V to 0.90 V;
- HBM rails per memory vendor specification;
- 1.8 V, 3.3 V, and auxiliary I/O/control rails.

Power conversion targets:

- at least 94 percent weighted conversion efficiency in P4;
- telemetry on every major rail;
- independent over current and over voltage protection;
- slot and external inputs isolated against backfeed.

## 7. Display and media

Display target:

- 3 × Mini DisplayPort 2.1b;
- 1 × USB C DisplayPort Alt Mode output;
- HDR and modern variable refresh support in the eventual display stack.

Media target:

- four hardware encode engines;
- four hardware decode engines;
- AV1 encode and decode as a primary format;
- H.264 and HEVC compatibility;
- low latency capture path suitable for game recording and streaming software.

## 8. Software implementation

A complete device requires firmware, kernel drivers, user mode graphics and compute drivers, shader compiler support, media integration, diagnostics, and application conformance work.

Planned implementation order:

1. firmware and board management;
2. Linux allocation, reset, interrupt, and display basics;
3. Vulkan compute;
4. basic Vulkan graphics;
5. shader compiler and conformance expansion;
6. ray tracing and advanced graphics features;
7. media APIs;
8. Windows display and compute stack;
9. native Direct3D 12 support.

CUDA compatibility is not claimed.

The software plan is expanded in [Software Stack](SOFTWARE_STACK.md).

## 9. Reliability and serviceability

- Hardware fault logic must be able to reduce power without normal GPU firmware execution.
- Dock loss or invalid flow in P3/P4 returns the reference controller to P0.
- Power, temperature, flow, and fault telemetry must be exposed to firmware and diagnostics.
- The thermal dock is serviceable independently of the card.
- The cold plate, pump/reservoir, fans, and quick disconnect hardware should be replaceable without replacing the compute board.

## 10. Production work still required

A tapeout capable implementation still requires full compute and graphics RTL, verified HBM and PCIe PHY integration, foundry PDK work, DFT, physical design, timing closure, IR/EM signoff, DRC/LVS, package simulation, signal integrity, power integrity, thermal simulation, masks, silicon validation, manufacturing test development, driver development, and application qualification.

See [Build Instructions](BUILD_INSTRUCTIONS.md) and [Roadmap](ROADMAP.md).
