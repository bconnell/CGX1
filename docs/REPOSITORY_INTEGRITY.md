# Repository Integrity

[Documentation index](README.md) · [Documentation style](DOCUMENTATION_STYLE.md) · [Validation](VALIDATION.md)

The repository uses separate checks for public wording, repository integrity, shared design values, local links, build success, and executable tests.

## Public wording

`check_public_repo_hygiene.ps1` scans first party public text for:

- private development terminology;
- internal tool references that do not belong in public engineering material;
- local machine residue;
- personal host identifiers;
- a short list of promotional filler phrases.

Technical workload language is not blocked merely because it uses terms such as AI or local model inference.

## Repository integrity

`check_repository_integrity.ps1` checks:

- tracked or unignored build output, logs, caches, binaries, office files, archives, and local environment files;
- private key and common access token signatures;
- probable embedded credential assignments;
- merge conflict markers;
- Windows PowerShell parser errors;
- external GitHub Actions that are not pinned to full commit hashes;
- required ignore patterns.

## Design consistency

`check_design_consistency.ps1` uses [design/cgx1_architecture.json](../design/cgx1_architecture.json) as the primary numeric design file and verifies selected mirrors in documentation, CAD, firmware, and model source.

The check includes card dimensions, dock dimensions, selected card fan thickness, power states, FP32 arithmetic target, memory capacity, memory bandwidth, matrix-engine count, matrix numeric-policy flags, frozen matrix tile shapes, register contract, issue timing, latency, whole-wave capture/writeback interface requirements, staging capacity, modulo-8 bank-class placement, matrix-to-matrix pending-destination interlock status, capture/active staging capacity and status, and theoretical dense-rate targets.

## Negative controls

Major repository gates include an executable negative control. Each test creates a scoped invalid input, requires the validator to reject it, verifies the expected finding, and removes the temporary input in a `finally` block.

Build and validation output remains under ignored `build/` and `out/` paths. The Windows repository workflow and path-scoped Ubuntu RTL workflow do not publish build artifacts. External actions remain pinned to full commit hashes. The checks do not reset, clean, rewrite history, or delete unrelated repository state.
