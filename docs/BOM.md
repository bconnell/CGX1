# Architecture Bill of Materials

[Documentation index](README.md) · [Mechanical design](MECHANICAL_DESIGN.md) · [Electrical interface](ELECTRICAL_INTERFACE.md) · [Prototype procurement](PROTOTYPE_PROCUREMENT.md)

This is an architecture requirements BOM. Final manufacturer part numbers for custom silicon, PCB power stages, PHYs, connectors, and production cooling parts depend on implementation and validation.

## Custom silicon and package

- 4 × graphics compute chiplets on the selected process.
- 1 × central I/O and cache controller die.
- 2 × 36 GB HBM4 stacks for the 72 GB baseline.
- Package level SRAM/cache structure targeting 512 MB.
- Silicon interposer or equivalent advanced package substrate.
- Package lid or direct cold plate interface with controlled mounting pressure.

## PCB

- 167.5 × 68.5 mm low profile PCIe card.
- Approximately 16 to 20 HDI layers expected before final signal and power integrity work.
- Low loss material appropriate to the final PCIe channel target.
- Reinforced PCIe edge and package keepout.
- Backside stiffening under the package and high current regulator region.

## Power

- 48 V locking external DC connector rated above the continuous design current.
- Separate certified 48 V AC/DC supply, 10 A minimum and 12 A preferred.
- Multiphase 48 V intermediate conversion.
- Digital point of load control.
- High current integrated power stages selected against the final efficiency target.
- Hardware supervisor independent of normal GPU firmware.
- Voltage, current, and temperature telemetry.
- Input isolation that prevents slot and external rails from backfeeding each other.

See [Electrical Interface](ELECTRICAL_INTERFACE.md).

## Card cooling

| Item | Prototype reference | Purpose |
|---|---|---|
| Cold plate | Nickel plated copper hybrid cold plate target | Package to coolant heat transfer |
| Spreader | Vapor chamber or equivalent | Reduced power slot operation |
| Card fans | 2 × Same Sky CFM-5010B-170-361-22 | 50 × 50 × 10 mm PWM/tachometer airflow |
| Thermal interface | Replaceable paste/pad system | Package and regulator interfaces |
| Quick disconnects | Dry break pair | External supply and return |

## External thermal dock

| Item | Prototype reference | Purpose |
|---|---|---|
| Radiator | Corsair XR5 240 | 280 × 120 × 30 mm heat exchanger |
| Radiator fans | 2 × 120 mm pressure oriented PWM fans | Airflow through radiator |
| Pump/reservoir | Alphacool ES Reservoir DDCzero 1U, part 14571 | Compact combined pump and air volume |
| Flow sensor | To be selected | Measured interlock and telemetry |
| Coolant temperature sensors | To be selected | Inlet/outlet measurement |
| Bulk DC filtering | To be designed | Low voltage dock input conditioning |
| Dock enclosure | 310 × 210 × 75 mm target | Component packing and service clearance |

The 48 V AC/DC supply remains external to this enclosure.

## Display and board I/O

- 3 × Mini DisplayPort 2.1b connectors.
- 1 × USB C connector with DisplayPort Alt Mode target and ESD protection.
- service/debug connector.
- SPI flash for boot firmware.
- identity storage or secure element as required by the finished security design.

Detailed P0 purchasing tables are maintained in [Prototype Procurement](PROTOTYPE_PROCUREMENT.md).
