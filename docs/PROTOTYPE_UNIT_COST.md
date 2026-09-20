# Prototype Unit Cost Planning

[Documentation index](README.md) · [Procurement](PROTOTYPE_PROCUREMENT.md) · [Prototype build](PROTOTYPE_BUILD.md)

Prices are planning snapshots from September 20, 2026. Tax, shipping, fabrication setup charges, supplier changes, and replacement parts are not included.

## Cost after bench equipment is already owned

| Prototype configuration | Planning range | Included scope |
|---|---:|---|
| P0 thermal/mechanical card using an existing dock and bench | ~$200 to $300 | Card body, heater/cold plate hardware, wiring, consumed materials, carrier/control allowance |
| P0 active card using an existing dock | ~$300 to $450 | More complete control/power electronics plus card hardware |
| P0 complete system with dedicated thermal dock | **~$850 to $1,050** | Card plus separate 48 V supply, radiator, pump/reservoir, fans, plumbing, control hardware, and consumed materials |
| P1 bench with AMD Alveo U50 and dedicated dock | ~$3,450 to $3,700 | Shared programmable accelerator plus P0 class infrastructure |
| Additional P1 configuration reusing an existing dock | ~$3,050 to $3,250 | Accelerator and card side requirements while reusing dock hardware |

The revised complete P0 range reflects the selected Alphacool ES Reservoir DDCzero 1U pump/reservoir, currently about $199.99 in US retail listings, instead of the earlier generic pump allowance.

The programmable accelerator dominates P1 cost. The preferred development arrangement is one shared U50 class accelerator with multiple lower cost mechanical, thermal, and power prototypes.

## Shared test infrastructure

The first thermal program may use approximately $108 of cartridge heaters and a roughly $65 PCIe riser. These are test assets rather than parts that remain in every later card. Bench meters, scopes, inspection equipment, rework tools, and thermal instruments are also excluded from recurring unit cost once owned.

## Early custom hardware BOM range

A future 72 GB HBM4 custom device has a different cost structure. The following figures are **planning allowances, not supplier quotes**.

| Custom hardware category | Early planning range | Basis |
|---|---:|---|
| Custom GPU chiplets | ~$300 to $700 | Unquoted early device allowance |
| 72 GB HBM4 | ~$600 to $1,000 | Unquoted memory allowance |
| Advanced package/interposer | ~$250 to $500 | Unquoted package allowance |
| High layer count PCB | ~$75 to $150 | Low volume board allowance |
| VRM and power electronics | ~$80 to $150 | Low volume power allowance |
| Cooling plate and card mechanicals | ~$75 to $125 | Custom machining/mechanical allowance |
| Remaining electronics and connectors | ~$50 to $100 | Board support hardware |
| Assembly and test allocation | ~$50 to $100 | Low volume allowance |
| **Estimated hardware BOM** | **~$1,480 to $2,825** | **Not a manufacturing quote** |

This range excludes non recurring ASIC engineering, licensed IP, masks, tapeout, foundry qualification, advanced package NRE, production test development, driver engineering, and yield effects. HBM4 and advanced packaging can vary materially with volume and supplier agreements.
