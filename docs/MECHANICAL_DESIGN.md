# Mechanical Design

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [Thermal and power](THERMAL_POWER.md) · [Prototype build](PROTOTYPE_BUILD.md)

## Card envelope

The card target remains **167.5 × 68.5 × 39.5 mm** outside the replaceable rear bracket hardware.

| Feature | Target | Prototype reference |
|---|---:|---|
| PCB length | 167.5 mm | Short card target |
| PCB height | 68.5 mm | Low profile board target |
| Installed thickness | 39.5 mm | Dual slot envelope |
| Package keepout | ≤ 55 × 55 mm | Compute + I/O + HBM package region |
| Card fans | 2 × 50 mm | Same Sky CFM-5010B-170-361-22 |
| Fan thickness | 10 mm | Manufacturer published dimension |
| Fan voltage | 12 V | PWM and tachometer capable |

The OpenSCAD model uses the selected fan thickness. The fin envelope is reduced accordingly so the complete card remains within 39.5 mm.

The 50 mm reference fan is an active Same Sky part, model **CFM-5010B-170-361-22**, specified as a 50 mm square, 10 mm thick, 12 V PWM/tachometer fan. See [Public Sources](SOURCES.md).

## Rear bracket services

The bracket concept provides:

- three Mini DisplayPort 2.1b target openings;
- one USB C DisplayPort Alt Mode target opening;
- coolant supply and return service;
- external 48 V service connection;
- interchangeable low profile and full height metalwork.

The exact connector mechanicals remain a board design task. The current SVG blueprint is a layout target, not a released sheet metal drawing.

## External thermal dock

The revised dock target is **310 × 210 × 75 mm**.

The enclosure is sized around the published dimensions of the radiator, radiator fans, and pump/reservoir, with additional volume reserved for fittings, low voltage control hardware, wiring, enclosure walls, and service routing.

### Packing references

| Component | Published size | Placement assumption |
|---|---:|---|
| Corsair XR5 240 radiator | 280 × 120 × 30 mm | Main radiator bay |
| Two 120 mm radiator fans | 120 × 120 × 25 mm each | Stacked on radiator, 55 mm radiator/fan thickness |
| Alphacool ES Reservoir DDCzero 1U with Pump, part 14571 | 112 × 57 × 41.95 mm | Alongside the radiator bay |
| Dock outer envelope | 310 × 210 × 75 mm | Allows enclosure walls, component clearance, fittings, wiring, and airflow openings |

The dock OpenSCAD source models those reference volumes directly. It is intentionally simple enough to expose interference instead of hiding it behind cosmetic geometry.

## Power supply location

The AC/DC power supply is **not inside the thermal dock**.

The electrical arrangement is:

```text
AC mains
   |
certified 48 V AC/DC supply
   |
CGX 1 thermal dock
   |
48 V + coolant
   |
CGX 1 card
```

Keeping mains conversion outside the coolant enclosure reduces dock packing pressure and keeps line voltage away from the pump, reservoir, coolant fittings, and prototype control electronics.

## Mechanical acceptance checks

Before P0 is accepted:

1. measure the finished card length, height, and thickness;
2. confirm both bracket variants fit their intended slot geometry;
3. confirm both 50 mm fans fit without exceeding 39.5 mm installed thickness;
4. confirm the 280 mm radiator and both 120 mm fans fit the dock;
5. confirm the pump/reservoir volume fits without intersecting the radiator or fan volumes;
6. confirm fitting and hose bend clearance with the enclosure closed;
7. confirm the 48 V and coolant services exit without requiring hidden side clearance;
8. inspect mounting pressure and PCB bending;
9. pressure test and leak test the coolant assembly before powered electronics are installed.

## Source files

- [Card OpenSCAD source](../mechanical/cgx1_card.scad)
- [Dock OpenSCAD source](../mechanical/cgx1_dock.scad)
- [Mechanical blueprint](../mechanical/cgx1_blueprint.svg)
- [Card STL envelope](../mechanical/cgx1_card.stl)
- [Dock STL envelope](../mechanical/cgx1_dock.stl)
