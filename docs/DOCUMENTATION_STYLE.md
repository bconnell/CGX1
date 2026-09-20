# Documentation Style

[Documentation index](README.md) · [Repository integrity](REPOSITORY_INTEGRITY.md)

Public CGX 1 documentation is engineering reference material. It should be direct enough that another engineer can understand the stated calculation, design choice, prototype step, or test requirement without access to private development notes.

## Writing rules

- State facts directly.
- Separate targets, analytical results, simulations, measurements, and planned work.
- Keep prototype results separate from custom silicon performance.
- Link a named repository document the first time it is introduced in a section.
- Prefer useful three or four column tables over narrow two column specification tables when a notes column improves readability.
- Use equations or explicit arithmetic when a numeric value is derived.
- Keep important limitations in the main text.
- Avoid promotional filler.
- Avoid internal process vocabulary that does not help explain the hardware.
- Keep private machine information, prompts, local paths, temporary evidence, and contributor tooling history out of public engineering prose.
- Technical terms such as AI, local model inference, compiler, shader, or machine learning are allowed when they describe an actual GPU workload or interface.

## Status terms

Use these terms consistently:

- **Target:** intended design value not yet physically demonstrated.
- **Analytical:** calculated from stated assumptions.
- **Executable reference:** source that builds and runs but is not the complete production implementation.
- **Measured:** observed on identified physical hardware with a reproducible procedure.
- **Planned:** not yet implemented.

## Shared design values

When a shared architecture value changes, update [design/cgx1_architecture.json](../design/cgx1_architecture.json) and every public mirror in the same revision. The consistency check must pass before the change is merged.
