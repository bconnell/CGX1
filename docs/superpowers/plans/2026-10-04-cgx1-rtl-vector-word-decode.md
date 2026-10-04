# CGX1 RTL Vector Word Decode Plan

> **Execution:** Implement in the existing CGX1 checkout, validate the exact candidate, and checkpoint locally.

**Goal:** Feed a 32-bit base instruction word into the existing resident-wave INT32 vector issue path without inventing memory or control encodings.

**Boundary:** A combinational per-wave decoder converts Vector-class base fields into the existing opcode/source/destination/lane-mask request bundle. The source retains each input word until the corresponding vector request is accepted. Other classes pass through unchanged to a future class handler with independent ready/valid handshaking. Opcodes 0x8-0xF remain routed to the existing vector pipeline's illegal-opcode handling.

**Out of scope:** Instruction-memory requests/responses, request identity and cancellation, wave-PC ownership, extension-word decode, memory/control operand formats, compiler/runtime, and public opcode assignments.

## Tasks

- [x] Add an RTL test first for raw-word field decode, per-wave ready/valid backpressure, non-vector pass-through, and vector execution through the resident scheduler and INT32 pipeline.
- [x] Run the test before implementation and confirm it fails because the decoder module is absent.
- [x] Implement the stateless decoder with parameterized per-wave vectors.
- [x] Add the test to `scripts/validate_rtl.sh` and run the focused bench.
- [x] Update validation, status, roadmap, artifact provenance, and completeness matrix to state the RTL decode boundary and its limits.
- [x] Run C++ build/CTest (26/26), focused decoder RTL simulation, repository consistency/integrity/public-hygiene/Markdown checks, matrix JSON, candidate fingerprint, and whitespace checks. The full RTL gate stopped at the existing resident VGPR-file compilation bottleneck before reaching the new test.
- [ ] Inspect the staged delta and commit one local checkpoint without pushing.
