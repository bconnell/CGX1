# Host Compatibility

[Documentation index](README.md) · [Mechanical design](MECHANICAL_DESIGN.md) · [Electrical interface](ELECTRICAL_INTERFACE.md)

CGX 1 is described by host classes rather than personal computer models.

## Low profile OEM desktop class

Typical constraints:

- low profile expansion slot;
- one adjacent slot available for a dual slot card;
- limited internal PSU capacity;
- older PCIe generation or firmware;
- limited chassis airflow.

CGX 1 addresses these constraints with a 167.5 × 68.5 mm PCB target, interchangeable low profile bracket, a 25 W Safe Boot state, qualified slot modes, and an external high power path.

Docked P3/P4 operation caps host slot demand at 25 W. A dock fault returns the reference controller to P0 at 25 W rather than switching to the 70 W slot state.

Resizable BAR is not assumed. The architecture includes a bounded aperture path and large local memory/cache hierarchy.

## Compact and conventional tower class

Typical constraints:

- greater bracket flexibility;
- more internal volume but uncertain PSU headroom;
- wider PCIe generation range;
- stronger airflow than a slim OEM chassis.

The same PCB can use low profile or full height bracket metalwork. The external 48 V path remains the preferred full power source because it avoids relying on spare host PSU capacity.

## PCIe negotiation

The native controller target is PCIe Gen 6 ×16 with backward interoperability through earlier PCIe generations. A lower negotiated link does not change local VRAM capacity or card power capability, but host transfer limited workloads can lose performance.

## Required fit checks

Before installation in a specific chassis, verify:

1. card length clearance of at least 167.5 mm plus rear bracket service clearance;
2. low profile or full height bracket compatibility;
3. two slot width clearance for 39.5 mm installed thickness;
4. rear access for coolant and 48 V services;
5. no obstruction of motherboard or chassis connectors;
6. PCIe ×16 mechanical slot availability;
7. host firmware behavior with an add in display/compute device;
8. placement for the 310 × 210 × 75 mm thermal dock;
9. hose routing from the rear bracket to the dock;
10. placement for the separate certified 48 V AC/DC supply.

A chassis family name alone is not proof of physical fit because internal layouts can change between revisions.
