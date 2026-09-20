# Thermal and Power Design

[Documentation index](README.md) · [Mechanical design](MECHANICAL_DESIGN.md) · [Electrical interface](ELECTRICAL_INTERFACE.md) · [Prototype build](PROTOTYPE_BUILD.md)

## Full power budget

| Subsystem | Target power | Budget role |
|---|---:|---|
| Four compute tiles | 230 W | Main execution load |
| I/O, display, media, and fabric | 25 W | Central logic and interfaces |
| HBM4 | 50 W | Two memory stacks |
| Package level SRAM/cache | 12 W | Stacked/package cache target |
| VRM and conversion loss | 28 W | Conversion loss allowance |
| Fans, sensors, and board overhead | 15 W | Card and dock support loads |
| **Total** | **360 W** | **P4 sustained board target** |

The 450 W value is an electrical transient design ceiling, not a sustained thermal target.

## 48 V input

At 360 W, an ideal 48 V source supplies 7.5 A before conversion and dock overhead.

The design calls for:

- certified external 48 V AC/DC supply;
- 10 A minimum capability;
- 12 A preferred for transient and dock margin;
- no mains conversion inside the coolant dock.

Docked P3/P4 operation limits host slot draw to 25 W. The external path supplies the remaining board power.

## Coolant calculation

The analytical model uses water like coolant properties:

```text
mass flow = 1.5 L/min × 0.997 kg/L / 60
          ≈ 0.0249 kg/s

coolant rise = 360 W / (mass flow × 4186 J/kg K)
             ≈ 3.45 °C
```

Thermal resistance targets:

- junction to coolant: ≤ 0.085 °C/W;
- radiator coolant to ambient effective: ≤ 0.040 °C/W at the full fan curve.

Using a 35 °C ambient analysis point, 360 W load, 1.5 L/min coolant flow, and half the modeled block coolant rise in the junction estimate gives approximately **81.7 °C**.

This is an analytical target. P0 hardware must establish measured temperatures and flow.

## Prototype cooling hardware

| Component | Reference | Published dimension/capability used by the design |
|---|---|---|
| Radiator | Corsair XR5 240 | 280 × 120 × 30 mm |
| Radiator fans | Two 120 mm pressure oriented fans | 25 mm thickness class assumed in dock packing |
| Pump/reservoir | Alphacool ES Reservoir DDCzero 1U, part 14571 | 112 × 57 × 41.95 mm, up to 220 L/h published maximum |
| Card fans | Same Sky CFM-5010B-170-361-22 | 50 × 50 × 10 mm, PWM/tachometer |
| Dock envelope | CGX 1 target | 310 × 210 × 75 mm |

Published pump maximum flow is not the same as loop flow under restriction. P0 must measure actual loop flow and demonstrate the 1.5 L/min operating target or revise the thermal design.

## Failure behavior

Independent hardware protection is required for:

- loss of coolant flow in P3/P4;
- loss of external 48 V in P3/P4;
- external input over voltage;
- package over temperature;
- HBM temperature beyond the selected vendor limit;
- VRM over temperature;
- major rail over current.

The reference controller returns to P0 at 25 W on dock loss, invalid coolant flow, hardware fault, GPU temperature at or above 88 °C, or VRM temperature at or above 105 °C.

Final production thresholds must come from characterized component limits rather than these prototype reference values.
