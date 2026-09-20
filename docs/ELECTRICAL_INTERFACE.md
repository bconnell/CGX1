# Electrical Interface

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [Thermal and power](THERMAL_POWER.md) · [Power management](POWER_MANAGEMENT.md) · [Validation](VALIDATION.md)

## Power sources

CGX 1 has two input domains:

1. the normal PCIe slot supply used for boot and qualified standalone modes;
2. a rear 48 V DC input used for docked high power operation.

The external 48 V source is supplied by a separate certified AC/DC unit. The thermal dock distributes and monitors the low voltage DC path but does not contain mains conversion.

## Power states

| State | Board limit | Maximum host slot demand | Entry requirement |
|---|---:|---:|---|
| P0 Safe Boot | 25 W | 25 W | Always available after reset |
| P1 Slot Eco | 45 W | 45 W | Host qualified for the requested slot power |
| P2 Slot Max | 70 W | 70 W | Host qualified for the requested slot power |
| P3 Dock Quiet | 220 W | 25 W | External 48 V present and coolant flow valid |
| P4 Dock Full | 360 W | 25 W | External 48 V present and coolant flow valid |

P3 and P4 take the remaining board power from the external 48 V path.

## Dock loss behavior

Loss of either of the following while P3 or P4 is active is treated as a dock fault:

- external 48 V presence;
- valid coolant flow.

The reference controller returns directly to **P0 Safe Boot**, limiting the board to 25 W. It does not jump to P2 because doing so could increase PCIe slot demand at the same moment the external source disappears.

A production device may later support a higher host qualified fallback, but that behavior requires explicit host capability detection and validation. P0 remains the default fault state.

## Input isolation

The final board requires hardware isolation that prevents either input source from backfeeding the other.

Required behavior:

- slot power cannot energize the external 48 V connector;
- external 48 V cannot backfeed the motherboard slot;
- the card can boot with the external source absent;
- P3/P4 rail enable is blocked until external power and coolant flow are valid;
- hardware fault logic can reduce power without depending on normal GPU firmware execution.

## External input

At 360 W, the ideal current from a 48 V source is 7.5 A before conversion and dock overhead.

The design target is:

- 48 V nominal input;
- 10 A minimum supply capability;
- 12 A preferred for transient and dock margin;
- locking connector and contacts rated above continuous design current;
- bulk filtering in the dock;
- intermediate conversion and point of load regulation on the card.

## Monitoring

Engineering boards should measure:

- PCIe slot voltage and current;
- external 48 V voltage and current;
- major regulator rail voltage/current;
- GPU/package temperature;
- HBM temperature;
- regulator temperature;
- coolant inlet and outlet temperature;
- coolant flow;
- pump speed;
- card fan speed;
- radiator fan speed.

## Internal allocation boundary

This document defines the external and board-level electrical limits. [Power Management](POWER_MANAGEMENT.md) defines how compute-tile capacity is allocated inside those limits.

The internal power manager cannot promote the board into a higher P-state. It receives the already-permitted state from the firmware safety controller and must keep authorized non-tile plus per-tile budgets within that board limit.

## Reference implementation

The public C implementation is in [source/firmware/cgx1_power.c](../source/firmware/cgx1_power.c). The SystemVerilog top level scaffold is in [source/rtl/cgx1_top.sv](../source/rtl/cgx1_top.sv).

Both are reference boundaries, not a production power controller or complete GPU.
