# Artifact Provenance

[Documentation index](README.md) · [Repository integrity](REPOSITORY_INTEGRITY.md)

The repository distinguishes editable engineering source from derived files.

| Artifact | Role | Maintenance rule |
|---|---|---|
| [`design/cgx1_architecture.json`](../design/cgx1_architecture.json) | Shared numeric design targets | Primary file for mirrored target values |
| [`mechanical/cgx1_card.scad`](../mechanical/cgx1_card.scad) | Card mechanical source | Edit this before regenerating card mesh |
| [`mechanical/cgx1_dock.scad`](../mechanical/cgx1_dock.scad) | Dock mechanical source | Edit this before regenerating dock mesh |
| [`mechanical/cgx1_blueprint.svg`](../mechanical/cgx1_blueprint.svg) | Dimensioned drawing | Maintained drawing source and README preview |
| [`mechanical/cgx1_card.stl`](../mechanical/cgx1_card.stl) | Card envelope mesh | Derived from card dimensions |
| [`mechanical/cgx1_dock.stl`](../mechanical/cgx1_dock.stl) | Dock envelope mesh | Derived from dock dimensions |
| [`source/model/`](../source/model/) | Analytical calculation source | Executable engineering source |
| [`source/isa/`](../source/isa/) | Base ISA field encoder/decoder and tests | Executable reference for the public instruction field contract |
| [`source/matrix/`](../source/matrix/) | Matrix numeric, physical architecture, register-interface, and banking references | Executable reference for formats, tile shapes, fragment mapping, instruction validation, pipeline targets, capture/writeback demand, staging, hazards, bank-class conflict rules, reduction order, and rate derivation; not matrix RTL or measured performance |
| [`source/power/`](../source/power/) | Tile power-management policy and invariant tests | Executable reference for board budgets, tile states, transitions, and hysteresis |
| [`source/firmware/`](../source/firmware/) | Power state controller | Executable reference source |
| [`source/rtl/`](../source/rtl/) | Top-level state scaffold and matrix pipeline-control RTL | Limited executable control RTL including matrix issue legality, stage sequencing, bank-safe addressing, and pending-destination interlocks; not matrix arithmetic or complete GPU RTL |

Generated compiler output, test logs, local manifests, temporary captures, IDE files, and validation scratch files are excluded from version control.

When a derived design file is regenerated, validate it against its editable source and the machine readable design targets before merging it.
