# Prototype Procurement Guide

[Documentation index](README.md) · [Prototype build](PROTOTYPE_BUILD.md) · [Mechanical design](MECHANICAL_DESIGN.md) · [Unit cost](PROTOTYPE_UNIT_COST.md)

This purchasing plan supports the P0 electrothermal card and thermal dock first. P1 adds a shared HBM programmable accelerator only when PCIe, memory traffic, RTL, or host software work needs it.

Prices are snapshots checked September 20, 2026. Retail pricing and stock can change.

## Consumable manufacturing supplies

| Consumable | Suggested quantity | Snapshot price | Purpose | Source |
|---|---:|---:|---|---|
| Chip Quik SMD291SNL SAC305 lead free solder paste, 15 g | 1 | $15.95 | SMT assembly and rework | [DigiKey](https://www.digikey.com/en/products/detail/chip-quik-inc/SMD291SNL/1160001) |
| Chip Quik SMD291NL no clean flux | 1 | $11.95 | Rework and connector soldering | [DigiKey](https://www.digikey.com/en/products/detail/chip-quik-inc/SMD291NL/1160000) |
| Kester 44 63/37 solder wire, 1 oz | 1 | $15.93 | Hand assembly | [Metrocom](https://metrocomusa.com/products/b00avlm4so) |
| MG Chemicals SuperWick, 5 ft | 1 | $6.73 | Desoldering and correction | [DigiKey](https://www.digikey.com/en/products/filter/desoldering-braid-wick-pumps/265) |
| Max Pro 99.9% IPA electronics cleaner | 1 | $12.99 | Board cleanup | [Micro Center](https://www.microcenter.com/product/623506/max-pro-isopropyl-alcohol-all-purpose-cleaner-12-oz) |
| Tapes Master polyimide tape, 1 in × 36 yd | 1 | $9.75 | Thermal masking and insulation | [Walmart](https://www.walmart.com/ip/Tapes-Master-1-Mil-1-inch-x-36-Yds-Kapton-Tape-Amber-Polyimide-High-Temperature-Tape/1150397847) |
| Arctic MX-6, 4 g | 1 | $11.99 | Heater/package to cold plate interface | [Micro Center](https://www.microcenter.com/product/685652/arctic-mx-6-thermal-paste-4-g) |
| GELID GP Extreme 0.5 mm pad | 1 | $9.99 | Thin thermal gap interface | [Walmart](https://www.walmart.com/ip/Gelid-Solutions-GP-Extreme-0-5mm-Thermal-Pad-TP-GP01-A/756327260) |
| GELID GP Extreme 1.0 mm pad | 1 pack | $14.99 | Regulator/package height adjustment | [Walmart](https://www.walmart.com/ip/Gelid-Solutions-GP-Extreme-12W-Thermal-Pad-80x40x1-0-2pcs-Excellent-Heat-Conduction-Ideal-Gap-Filler-Easy-Installation/815284725) |
| GELID GP Extreme 1.5 mm pad | 1 | $14.99 | Larger thermal gaps | [Newegg](https://www.newegg.com/gelid-solutions/p/2MB-004H-00034) |
| Corsair XL8 clear coolant, 1 L | 1 | $24.99 | External cooling loop | [Corsair](https://www.corsair.com/us/en/p/custom-liquid-cooling/cx-9060007-ww/hydro-x-series-xl8-performance-coolant-1l-aca-a-clear-cx-9060007-ww) |
| EK Loop ZMT 10/16 mm tubing, 3 m | 1 | $29.99 | Dock coolant lines | [EKWB](https://www.ekwb.com/shop/accessories/tubing/10-16mm-3-8-5-8-tubing) |
| 10 AWG silicone power wire | 5 ft red + 5 ft black | $13.99 | 48 V low voltage harness | [Walmart](https://www.walmart.com/ip/326626641) |
| 18 AWG silicone wire assortment | 1 | ~$16.40 | Fans, sensors, and control wiring | [TinyRacer](https://tinyracer.com/products/18awg-silicone-electrical-wire-cable-6-colors-5ft-each-18-gauge-hookup-wires-kit-stranded-tinned-copper-wire-flexible-and-soft-super-low-impedance-high-temperature-resistance-size-6-colors-each-5ft-style-18awg) |
| Heat shrink assortment | 1 | $6.47 | Harness construction | [Walmart](https://www.walmart.com/ip/Hyper-Tough-120-Piece-Assortment-Heat-Shrink-Tubing/13708908712) |
| Black PETG filament, 1 kg | 1 spool | $14.99 | Prototype shroud, ducting, and dock shell | [Overture](https://overture3d.com/products/overture-high-speed-petg) |
| M3 stainless fastener assortment | 1 | $15.54 | Card and dock assembly | [Home Depot](https://www.homedepot.com/p/MYWISH-550-Piece-M3-x-Assorted-304-Stainless-Steel-Hex-Drive-Button-Head-Socket-Head-Cap-Screws-Assortment-Kit-SF-TZ00002/337625654) |

## P0 card and dock hardware

| Product | Quantity | Snapshot price | Use | Source |
|---|---:|---:|---|---|
| Mean Well LRS-600N2-48 | 1 | $64.00 | Separate 48 V, 600 W, 12.5 A AC/DC supply | [DigiKey](https://www.digikey.com/en/products/detail/mean-well-usa-inc/LRS-600N2-48/21531502) |
| Corsair XR5 240 radiator | 1 | $74.99 | 280 × 120 × 30 mm external heat exchanger | [Corsair](https://www.corsair.com/us/en/p/custom-liquid-cooling/cx-9030002-ww/hydro-x-series-xr5-240mm-water-cooling-radiator-cx-9030002-ww) |
| Alphacool ES Reservoir DDCzero 1U with Pump, 14571 | 1 | $199.99 | 112 × 57 × 41.95 mm compact pump/reservoir | [Titan Rig](https://www.titanrig.com/alphacool-es-reservoir-ddczero-1u-with-pump.html) |
| Noctua NF-A12x25 PWM | 2 | $38.79 each | 120 mm radiator airflow | [Newegg](https://www.newegg.com/noctua-nf-a12x25-pwm-case-fan/p/1YF-000T-000K7) |
| Same Sky CFM-5010B-170-361-22 | 2 | Check lead time/quote | 50 × 50 × 10 mm card fan, PWM + tach | [DigiKey](https://www.digikey.com/en/products/detail/same-sky-formerly-cui-devices/CFM-5010B-170-361-22/22259116) |
| Koolance QD3 coolant pairs | 2 pairs | ~$72.40 total | Dry break supply and return | [Koolance](https://koolance.com/quick-disconnect-couplings-3rd-generation-qd3) |
| EK Torque STC 10/16 fittings, 6 pack | 1 | $49.99 | Tube termination | [EKWB](https://www.ekwb.com/shop/quantum/torque-fittings/torque-stc-fittings) |
| Universal copper water block | 1 | $54.99 | First cold plate substitute | [Newegg](https://www.newegg.com/p/3C6-06GK-00XB3) |
| 48 V cartridge heaters | 4 | $27 each | Artificial GPU/package heat load | [HartSmart](https://hartsmartproducts.com/products/high-wattage-cartridge-heaters-24v-48v) |
| Anderson SB50 connector with contacts | 2 | ~$6.60 each | Removable 48 V low voltage connection | [AndyMark](https://andymark.com/products/sb50-anderson-powerpole-connector-with-contacts) |

The Mean Well unit is a separate external supply. It is not packed inside the 310 × 210 × 75 mm thermal dock.

The Same Sky fan is an active exact dimensional reference but may require lead time. A prototype can use an electrically compatible 50 × 50 × 10 mm fan as a temporary mechanical substitute, provided the actual dimensions and control features are recorded.

## P1 programmable accelerator and bench hardware

| Product | Stage | Snapshot price | Use | Source |
|---|---|---:|---|---|
| AMD Alveo U50 | P1 | $2,965.00 | Shared HBM/PCIe programmable accelerator | [AMD](https://www.amd.com/en/products/accelerators/alveo/u50/a-u50-p00g-pq-g.html) |
| Lian Li PCIe 5.0 ×16 riser | Bench | $64.99 | Operate a test card outside the chassis | [Micro Center](https://www.microcenter.com/product/694523/lian-li-pcie-50-x16-riser-cable) |
| Hakko FX-888DX | Bench | $121.47 | Soldering station | [Hakko](https://hakkousa.com/fx-888dx.html) |
| Quick 861DW | Bench | $293.78 | Hot air rework | [Elektor](https://www.elektor.com/products/quick-861dw-hot-air-rework-station-1000-w) |
| Miniware MHP30 | Bench | $99.95 | PCB preheat/local reflow | [Adafruit](https://www.adafruit.com/minihotplate) |
| AmScope SE400-Z | Bench | $291.99 | PCB inspection | [AmScope](https://amscope.com/products/se400-z) |
| PCB holder | Bench | $23.99 | Board fixture | [Walmart](https://www.walmart.com/ip/MMOBIEL-Adjustable-PCB-Holder-Circuit-Board-Holder-Tool-for-Circuit-Board-Soldering-Desoldering-Repair-Tool-360-Degree-Rotation/2203904857) |
| Rigol DHO804 | Bench | $413.10 | Four channel oscilloscope | [Rigol](https://www.rigolna.com/products/rigol-digital-oscilloscopes/dho800/) |
| Fluke 87V | Bench | $461.90 | Electrical measurements | [Home Depot](https://www.homedepot.com/b/Electrical-Electrical-Tools-Electrical-Testers-Multimeter/FLUKE/N-5yc1vZchjcZyuk) |
| FLIR C5 | Bench | $699.00 | Thermal imaging | [FLIR](https://www.flir.com/products/c5/) |

## Lower cost bench substitutes

| Standard item | Substitute | Snapshot price | Tradeoff | Source |
|---|---|---:|---|---|
| Quick 861DW | Yihua 8786D-I combined station | $59.99 | Lower airflow and thermal capacity | [Micro Center](https://www.microcenter.com/product/709629/-yihua-8786d-i-hot-air-rework-station-with-soldering-iron) |
| Hakko FX-888DX | Pinecil V2 | ~$53.14 | Portable form instead of a full bench station | [DREMC](https://store.dremc.com.au/products/pinecil-smart-mini-portable-soldering-iron-version-2) |
| Stereo microscope | 1600× USB microscope | $29.99 | No optical stereo depth perception | [Walmart](https://www.walmart.com/ip/1600X-USB-Digital-Microscope-8-LED-Lights-Stand-Portable-Handheld-Inspection-Magnifier-Compatible-Android-Windows-XP-Win-7-10-Vista-Linux-Mac/5254491137) |
| Rigol DHO804 | FNIRSI 2C53P | $128.99 | Fewer channels and less bench capability | [Micro Center](https://www.microcenter.com/product/701500/fnirsi-2c53p-handheld-tablet-oscilloscope-multimeter-dds-signal-generator-3-in-1) |
| Fluke 87V | Klein MM420 | $69.97 | Fewer industrial meter features | [Home Depot](https://www.homedepot.com/p/Klein-Tools-600-Volt-Digital-Multimeter-TRMS-Auto-Ranging-Temp-MM420/320822810) |
| FLIR C5 | Klein IR5 spot thermometer | $69.99 | No thermal image | [Home Depot](https://www.homedepot.com/p/207004900) |
| Programmable electronic load | Four 100 W, 24 ohm aluminum resistors | ~$22.98 for four | Manual load arrangement | [Walmart](https://www.walmart.com/ip/Aluminum-Case-Resistor-100W-24Ohm-Wirewound-Yellow-2pcs/103362154) |
| Custom machined cold plate | Universal copper water block | $54.99 | Does not reproduce final internal geometry | [Newegg](https://www.newegg.com/p/3C6-06GK-00XB3) |
| AMD Alveo U50 during P0 | Omit the FPGA accelerator | $0 | P0 remains mechanical, electrical, firmware, and thermal only | — |
| AMD Alveo U50 for smaller RTL experiments | Digilent Genesys 2 class board | roughly $1,099 | No HBM and weaker representation of the intended memory system | [Digilent](https://digilent.com/reference/programmable-logic/genesys-2/start) |

## PCB fabrication

The control and power PCB should be professionally fabricated and assembled. The final quote depends on the manufacturing files, copper weight, layer count, controlled impedance requirements, via structure, surface finish, assembly side count, and component sourcing.

A public assembly pricing reference is maintained in [Sources](SOURCES.md). Obtain a fresh quote from the actual manufacturing files before ordering.

## P0 purchase order

1. separate certified 48 V AC/DC supply;
2. radiator, radiator fans, pump/reservoir, coolant, tubing, fittings, and disconnects;
3. card fans or exact dimensional surrogates;
4. cold plate substitute and heater load hardware;
5. wire, connectors, thermal interface material, fasteners, and enclosure material;
6. control PCB fabrication and components;
7. only then add bench instruments not already available;
8. add the shared programmable HBM accelerator when P1 work begins.

An open frame AC/DC supply needs its own suitable electrical enclosure or guarded installation so mains terminals are not exposed in normal use.
