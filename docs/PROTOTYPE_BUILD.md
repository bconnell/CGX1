# Prototype Build Plan

[Documentation index](README.md) · [Mechanical design](MECHANICAL_DESIGN.md) · [Electrical interface](ELECTRICAL_INTERFACE.md) · [Procurement](PROTOTYPE_PROCUREMENT.md) · [Test record](TEST_RECORD_TEMPLATE.md)

## P0: electrothermal card and dock

P0 uses the final card envelope and revised external dock architecture while replacing the custom GPU package heat source with controlled electrical heaters.

P0 validates:

- 167.5 × 68.5 × 39.5 mm card packaging;
- selected 50 × 50 × 10 mm card fan volume;
- low profile and full height bracket concepts;
- rear coolant and low voltage power service routing;
- 48 V dock distribution;
- 310 × 210 × 75 mm dock packing;
- 240 mm radiator and two 120 mm fan fit;
- pump/reservoir fit and service access;
- approximately 360 W sustained thermal load handling;
- coolant flow and temperature measurement;
- fault interlocks;
- firmware power state behavior;
- host slot fit through a PCIe mechanical test card or inactive carrier.

A machined copper spreader should place heater load beneath the regions assigned to the future compute and HBM package. Instrument the spreader, coolant inlet/outlet, regulator region, external input, host slot input, and ambient air.

## P1: programmable compute surrogate

P1 adds a shared HBM capable programmable accelerator to the development bench. AMD Alveo U50 remains the reference surrogate because the production card provides a compact 75 W PCIe form factor, 8 GB HBM2, and programmable logic.

P1 can exercise:

- PCIe host software;
- HBM traffic patterns;
- firmware and telemetry protocols;
- command queue concepts;
- memory movement;
- early compute compiler/API work;
- RTL blocks that fit the selected FPGA.

P1 does not reproduce CGX 1 performance, package topology, 72 GB HBM4 capacity, or the complete graphics pipeline.

## P0 mechanical sequence

1. Build the card shroud, bracket fixtures, and dock enclosure from the repository CAD dimensions.
2. Fabricate a 167.5 × 68.5 mm carrier PCB or dimensional board with the intended PCIe edge and mounting geometry.
3. Install two actual 50 × 50 × 10 mm card fans or exact dimensional surrogates.
4. Machine a copper spreader/cold plate test assembly covering the planned package region.
5. Install controllable resistive heat sources with independent temperature sensing.
6. Install coolant fittings at the rear bracket and connect the dry break hose set.
7. Install the Corsair XR5 240 radiator reference or exact dimensional equivalent in the dock.
8. Install two 120 mm radiator fans.
9. Install the Alphacool ES Reservoir DDCzero 1U pump/reservoir or exact dimensional equivalent.
10. Install coolant flow and temperature sensing.
11. Connect a separate certified 48 V AC/DC supply to the low voltage dock input.
12. Leak test without powered electronics.
13. Bring thermal load up in controlled steps while logging temperature, flow, electrical input, and coolant rise.

## P0 electrical sequence

1. Validate the auxiliary control supply at low power.
2. Validate voltage and current sensors against bench measurements.
3. Verify that P3/P4 cannot be entered without external 48 V.
4. Verify that P3/P4 cannot be entered without valid coolant flow.
5. Verify P0, P1, P2, P3, and P4 board limits with an electronic or resistive load.
6. Verify docked host slot draw stays at or below 25 W.
7. While in P3/P4, remove external 48 V and verify immediate fallback to P0 rather than P2.
8. While in P3/P4, invalidate coolant flow and verify immediate fallback to P0.
9. Validate hardware fault and temperature fault response.
10. Validate rail sequencing before attaching a programmable compute surrogate.

## P0 acceptance targets

| Measurement | Initial target | Evidence required |
|---|---:|---|
| Full thermal load | 360 W sustained | Logged load and duration |
| Coolant flow | ≥ 1.5 L/min nominal | Calibrated flow measurement |
| Bulk coolant rise at 360 W | ≈ 3.45 °C analytical reference | Measured inlet/outlet temperatures |
| Simulated junction estimate at 35 °C ambient | < 85 °C target | Sensor placement and thermal record |
| Dock mode host slot draw | ≤ 25 W | Measured voltage/current |
| Dock fault fallback | P0 / 25 W | State log and slot power trace |
| External input | 48 V nominal | Measured voltage/current |
| Dock packing | No interference | Closed enclosure inspection and dimensions |

Use [Test Record Template](TEST_RECORD_TEMPLATE.md) for measured results.
