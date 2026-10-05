# CGX1 Validation Gate Hardening Implementation Plan

> **Execution:** Follow the tasks in order. Preserve the existing checkout, local commits, ignored build outputs, and publish validated coherent commits only to `origin/codex/cgx1-completeness` using fast-forward pushes. Keep `main` protected; do not rewrite history or publish known-red checkpoints. At a hosted-green milestone, integrate through a PR to `main` with ancestry preserved, then reconcile the completeness branch before starting another major subsystem.

**Goal:** Make validation claims traceable to executable checks, exact source identity, and honest C/C++/RTL evidence.

**Architecture:** Keep subsystem maturity in the completeness matrix, but move revision and workflow evidence into a canonical ledger whose own file is excluded from the source-content fingerprint. Add portable validators for evidence, links, test and resource inventories, then wire them into local and hosted gates.

**Tech Stack:** Python 3 standard library, PowerShell, CMake/CTest, GCC/Clang, Icarus Verilog, GitHub Actions.

**Spec:** User-supplied validation/gate-hardening directive for CGX1.

## Global Constraints

- Preserve all existing work and do not rewrite history.
- Keep local working, committed, remote, and hosted-validated candidates distinct.
- Do not claim physical implementation evidence from C++ or RTL simulation.
- Keep complete-composition RTL compile-only/partial until it is actually simulated.
- Executable C/C++ test expectations use always-on checks; Release/NDEBUG evidence includes a deliberate failing check that CTest observes.
- Validate a staged candidate tree from a clean isolated checkout and a fresh build directory; do not attest uncommitted helper files.
- Cross-environment clean validation must run without root: translate Windows paths explicitly, establish the same Git/tree/fingerprint identity in Linux, and verify identity before and after validation.
- Treat WSL root runs as diagnostics only. Prefer an existing unprivileged account; do not create a persistent WSL user if a usable account or hosted unprivileged Linux runner is available.
- Add GPU-specific Verilator, synthesis-smoke, sanitizer, coverage, escaped-defect, and fault-injection evidence where current tools and RTL contracts support it.
- Validation remains CPU-only and headless; optional heavier lanes cannot become a baseline hardware requirement.
- Commit one coherent batch only after its complete validation gate passes; push the validated commit to the completeness branch, verify the exact remote SHA, dispatch applicable workflows, and continue local work while hosted checks run.
- Treat feature publication and main integration as separate relationships: report local-to-feature and feature-to-main SHAs, ancestry, ahead/behind counts, integration PR state, hosted-green integration debt, and latest integrated main SHA.
- Do not begin a new major GPU subsystem while main is behind the hosted-green feature milestone or contains commits absent from the feature branch.

## Review Focus

- A clean worktree must not let a stale ledger attest a different source tree.
- Matrix `validated` states must identify their required evidence class and runnable reference.
- Release/NDEBUG tests must execute every check expression and state-changing operation.
- Ordinary runtime `assert(...)` is forbidden in executable test sources, including pure expected-result checks; `static_assert` remains allowed.
- The test-source assertion gate must inspect source tokens rather than comments or string literals and must have positive and negative controls.
- A Release/NDEBUG CTest regression must fail for an intentionally false always-on expectation.
- Every RTL test marked simulated must have a bounded compile and actual bounded simulation.
- The pooled resident INT8 plus ordinary-vector composition must remain explicitly partial if only compiled.
- Missing Markdown targets and missing heading anchors must fail with distinct diagnostics.
- Randomized failures must report seed and enough iteration/state to reproduce them.

### Task 1: Candidate identity and executable evidence ledger

**Files:** Add portable evidence validator and its Python tests; update `design/cgx1_completeness_matrix.json`, add the evidence ledger, and remove stale revision claims from architecture data.

- [x] Write tests for deterministic source identity, evidence-schema validity, legal maturity transitions, exact-CI SHA mismatch, invalid evidence class, and stale-current-claim rejection.
- [x] Run the tests and confirm each negative control fails for its intended reason.
- [x] Implement candidate identity and ledger validation; ensure the ledger is excluded from its own source fingerprint.
- [x] Attach concrete evidence references to validated matrix rows and downgrade compile-only compositions to partial.
- [x] Run positive and negative controls.

### Task 2: Public hygiene and Markdown anchors

**Files:** Update `scripts/check_public_repo_hygiene.ps1` and its test script; upgrade the Markdown link checker and add portable checker tests.

- [x] Add positive hygiene cases for legitimate technical uses of “source fingerprint” and negative cases for actual workflow wording.
- [x] Add Markdown negative controls for a missing file and missing heading, plus positive cases for valid, duplicate, and encoded anchors.
- [x] Implement contextual hygiene matching and GitHub-compatible local heading slug resolution.
- [x] Run all positive and negative controls and inspect their diagnostics.

### Task 3: Resource-limit and randomized-test evidence

**Files:** Add a machine-readable limit registry and validator/tests; improve randomized test failure context and architecture wording.

- [x] Add inventory coverage for significant architectural, implementation, physical-candidate, representation, safety, malformed-input, and test-only limits.
- [x] Add boundary coverage references and negative controls for missing classification or test evidence.
- [x] Preserve deterministic seeds and report seed, iteration, and relevant operation/state on failure.
- [x] Add an escaped-defect ledger mapping known defect classes to permanent regressions/gates and locations.
- [x] Add a pairwise/high-risk lifecycle fault-injection matrix tied to executable tests.
- [x] Record toolchain provenance and practical validation time/resource budgets.
- [x] Verify scalar/predicate registers are described as logical counts plus finite capacity accounting, not allocated data storage.
- [x] Preserve provisional opcode and implementation-policy status in consistency gates.

### Task 4: Always-on C/C++ test assertions and warning policy

**Files:** Add an always-on test check helper and NDEBUG regression, migrate test assertions, add a source check, and define canonical CMake warning options.

- [x] Audit every C/C++ executable test target and its source files.
- [x] Add an always-on test check helper; replace every runtime test `assert`, including pure expected-result checks; preserve `static_assert`.
- [x] Add a source-aware gate with positive controls for the helper and `static_assert`, and a negative control for runtime `assert` in a test source.
- [x] Add an intentionally false test check and execute its CTest under Release/NDEBUG; prove it fails, then isolate the fixture from passing runs.
- [x] Record that previous Release builds remain build evidence, while assertion-based Release expectations require fresh post-migration runs.
- [x] Add reviewed strict warnings and promote clean warning classes to errors without broad suppression.
- [x] Add hosted Linux AddressSanitizer and UndefinedBehaviorSanitizer coverage.
- [ ] Run Debug and Release CTest with GCC and Clang where available. Clang is not installed in the local WSL environment; exact-SHA hosted checks remain pending.

### Task 5: RTL inventory, bounded tools, and warning classification

**Files:** Update `scripts/validate_rtl.sh`, add inventory/warning validators and fixtures, update architecture and matrix evidence.

- [x] Inventory every `iverilog` top and every simulation invocation; add tests rejecting an unbounded compiler, a simulated-but-not-run top, or a falsely simulated compile-only entry.
- [x] Add compiler/elaboration timeouts, capture output, and classify warnings with explicit reasons.
- [x] Add an executable inventory for every first-party production RTL module and important composed top.
- [x] Add a Verilator parse/lint/elaboration lane and classify any retained warnings individually.
- [x] Add bounded Yosys (or compatible open frontend) synthesis smoke for representative tops where supported.
- [x] Add bounded formal/property checks for small high-value ownership, handshake, barrier, stale-response, and reset invariants where tools and harnesses support them.
- [x] Preserve deterministic random seeds and print seed plus test context for failing random sequences.
- [x] Keep the resident pooled INT8/ordinary-vector composition compile-only/partial unless the complete composition is bounded and simulated.
- [x] Run the full RTL gate and all inventory positive/negative controls.

### Task 6: Canonical local and hosted validation entry points

**Files:** Update validation wrappers, CMake/CI configuration, `docs/VALIDATION.md`, `docs/STATUS.md`, architecture/matrix descriptions, and relevant READMEs.

- [x] Ensure required gate failures propagate to the final exit code.
- [x] Add executable regressions for Windows-style paths entering WSL, `/mnt/<drive>` translation, Linux-side Git identity, Windows/WSL source-fingerprint equality, and clear fail-closed identity diagnostics.
- [x] Run the isolated Linux clean candidate as an existing unprivileged WSL user; verify non-root UID, exact commit/tree/index/fingerprint, and pre/post identity. Do not count root-only runs as contributor-grade evidence.
- [x] Include diff checks, matrix/schema/identity, clean/staged scope, hygiene, repository integrity, design consistency, negative controls, Markdown links, CTest, and RTL in authoritative local/hosted paths.
- [x] Validate the exact staged source tree in a clean isolated checkout with no pre-existing build output; prove an uncommitted required helper cannot satisfy this gate.
- [x] Configure a fresh build directory, build required targets, and execute CTest; clean-build proof must be part of the canonical gate.
- [x] Validate the reconstructed publication artifact for uncommitted dependencies, generated junk, personal paths, stale docs, and broken links.
- [x] Run GCC/Clang and Debug/Release jobs automatically for the completeness branch and pull requests.
- [x] Add hosted sanitizer coverage and the applicable Verilator/synthesis-smoke lanes.
- [x] Audit commit SHA, workflow run ID, “current candidate”, `simulation_exercised`, and matrix evidence claims; preserve historical claims with explicit dates and exact evidence.
- [x] Fail closed on unexplained local/remote branch divergence and record local HEAD, feature SHA, main SHA, both merge bases, ahead/behind counts, open integration PR, latest hosted-valid feature SHA, and latest integrated main SHA.
- [x] Document evidence classes and the candidate/source fingerprint method without self-referential commit metadata.

### Task 7: Full candidate verification and one coherent commit

- [x] Run all local positive and negative controls, Debug/Release CTest with GCC, the complete RTL gate, repository/design/hygiene/link checks, and exact source identity. Clang is unavailable locally; exact-SHA hosted checks remain pending.
- [ ] Run applicable clean-room, clean-build, sanitizer, Verilator, synthesis-smoke, formal/property, RTL coverage, escaped-defect, fault-injection, provenance, and resource-budget gates.
- [ ] Review the entire staged diff and verify documentation truth against executable output.
- [ ] Commit one coherent gate-hardening batch after all applicable local checks pass; push it fast-forward to the completeness branch and verify the exact remote SHA.
- [ ] Require successful Windows CI, RTL CI, Linux Sanitizers, and RTL Tools CI on the exact published candidate; record those runs without changing the candidate source fingerprint.
- [ ] Create or update the integration PR from `codex/cgx1-completeness` to protected `main`; verify exact PR head/base, all required checks, and the complete merge diff.
- [ ] Merge through the protected workflow with ancestry preserved; verify resulting main SHA and ancestry, fetch it, reconcile the completeness branch by fast-forward when possible, and rerun branch-state checks.
- [ ] Only after integration is complete, run the major-slice preflight and resume the dependency-aware complete-GPU queue.

**Explicit deferral:** External-consumer validation is not required in this batch because an assembler/compiler/runtime consumer path is not yet ready; retain it as a dependency-queue item until those interfaces exist.
