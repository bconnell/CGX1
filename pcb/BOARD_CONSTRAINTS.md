# PCB Constraints

[Documentation index](../docs/README.md) · [Engineering specification](../docs/ENGINEERING_SPEC.md) · [Electrical interface](../docs/ELECTRICAL_INTERFACE.md)

1. Board outline: 167.5 × 68.5 mm.
2. Installed thickness: no more than 39.5 mm outside the bracket zone.
3. High power and coolant services exit through the rear bracket.
4. Internal host cabling should not require more than 10 mm of side clearance beyond the card envelope.
5. ASIC/HBM package target: no larger than 55 × 55 mm.
6. Keep the package centroid close to the PCIe connector support region to control board stress.
7. PCIe Gen 6 routing requires complete channel simulation. Length matching alone is insufficient.
8. Separate sensitive reference clocks from multiphase switching nodes and fan/pump PWM paths.
9. Slot 12 V and external 48 V inputs require isolation so neither source can backfeed the other.
10. The board must boot with external 48 V absent.
11. External power presence must be hardware detectable before P3/P4 rails can enable.
12. The coolant flow interlock must directly participate in P3/P4 authorization.
13. Loss of external 48 V or valid coolant flow during P3/P4 must force the reference control path to P0 Safe Boot.
14. Provide rail test points and high speed compliance access on engineering boards.
15. Use replaceable bracket metalwork so one PCB can support low profile and full height installations.
16. Final stackup, via structure, copper weight, materials, impedance, spacing, and creepage require manufacturer and signal/power integrity signoff.

The selected 50 × 50 × 10 mm card fan volume and revised external dock packing are documented in [Mechanical Design](../docs/MECHANICAL_DESIGN.md).
