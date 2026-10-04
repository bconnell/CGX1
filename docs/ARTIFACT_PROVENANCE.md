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
| [`source/isa/`](../source/isa/) | Base ISA field encoder/decoder, provisional INT32 vector semantics, bounded vector-stream step reference, and tests | Executable references for the public base-field contract, provisional vector subset, and software PC-stepped execution from an immutable base-word image; the asynchronous RTL fetch transaction/lifecycle model remains RTL-owned |
| [`source/matrix/`](../source/matrix/) | Matrix numeric, physical architecture, register-interface, banking, staging, scoreboard, INT8 arithmetic, and INT8 path references | Executable references cover functional capture/execute/result/writeback behavior and architectural invariants; they do not establish physical timing, area, power, or measured hardware performance |
| [`source/power/`](../source/power/) | Tile power-management policy and invariant tests | Executable reference for board budgets, tile states, transitions, and hysteresis |
| [`source/firmware/`](../source/firmware/) | Power state controller | Executable reference source |
| [`source/rtl/`](../source/rtl/) | Top-level state scaffold, compute workgroup frontend, per-wave instruction fetch unit, and matrix/vector control/storage/scoreboard/arithmetic RTL | Limited RTL including matrix issue legality, staging, per-wave hazards, signed INT8 arithmetic, composed INT8 capture-to-writeback plumbing, a one-wave INT8 engine shell, abstract identity-safe fetch/response, fetched vector decode through the control-flow PC and resident execution path, and generic base-field handoff for non-vector words; class-specific non-vector semantics, FP16/BF16/FP8 arithmetic, complete top-level instruction-stream integration, and complete GPU RTL remain open |

Generated compiler output, test logs, local manifests, temporary captures, IDE files, and validation scratch files are excluded from version control.

When a derived design file is regenerated, validate it against its editable source and the machine readable design targets before merging it.
