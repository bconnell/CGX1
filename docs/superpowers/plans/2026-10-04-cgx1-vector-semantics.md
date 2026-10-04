# CGX1 Provisional INT32 Vector Semantics Implementation Plan

> **Execution:** Follow these test-first tasks in the existing CGX1 checkout and create one local checkpoint after validation.

**Goal:** Add an executable reference for the existing eight-op INT32 vector subset using the current 32-bit base instruction fields.

**Architecture:** Decode a base instruction word through the existing ISA decoder, then apply the supported vector operation to active lanes in a 256-register, 32-lane wave register file. Preserve the current ALU opcode meanings as provisional implementation mappings; do not assign memory, control, scalar, or matrix encodings and do not claim the vector subset is a frozen ISA commitment.

**Tech Stack:** C++20, CMake/CTest, existing CGX1 ISA encoder/decoder, SystemVerilog behavior as the implementation cross-check.

**Spec:** [ISA contract](../../ISA.md), [`cgx1_isa.hpp`](../../../source/isa/cgx1_isa.hpp), and [`cgx1_vector_int32_alu.sv`](../../../source/rtl/cgx1_vector_int32_alu.sv).

## Global Constraints

- Use the existing 32-bit base-word class/opcode/destination/source0/source1 fields.
- Vector operands name one of 256 registers; each register has 32 32-bit lane elements.
- Only active lanes receive destination updates; inactive destination elements retain their prior value.
- The current INT32 vector ALU mappings are opcodes 0-7: ADD, SUB, AND, OR, XOR, SHL, logical SHR, arithmetic SHR.
- Unsupported classes do not mutate vector state; unsupported vector opcodes report an illegal-vector-op result without mutation.
- No memory or control opcode/operand assignment, fetch interface, compiler/ABI, timing, area, power, or physical claim is in scope.

## Review Focus

- 32-bit wraparound and five-bit shift-count behavior, including shift count 0 and 31.
- Arithmetic right shift sign extension without undefined or implementation-defined signed behavior.
- Inactive-lane preservation and empty active mask behavior.
- Source/destination register aliasing.
- Lane-specific source and shift-count values.
- Illegal vector opcode and non-vector class rejection without partial register mutation.

---

### Task 1: Add executable vector semantics

**Files:**
- Create: `source/isa/cgx1_vector_semantics.hpp`
- Modify: `source/isa/tests.cpp`

**Interfaces:**
- Consumes: `cgx1::isa::DecodeBase` and `InstructionClass` from `cgx1_isa.hpp`.
- Produces: `VectorRegister` (32 lanes), `VectorRegisterFile` (256 registers), `VectorInstructionStatus`, and `ExecuteVectorBaseInstruction(word, registers, active_lane_mask)`.

- [x] Add focused tests for all eight opcode results, wraparound, shifts 0/31, arithmetic sign fill, active/inactive lanes, source/destination aliasing, empty masks, and unsupported inputs.
- [x] Build and run `cgx1_isa_encoding_checks`; confirm the new API tests fail before implementation for the missing declarations.
- [x] Implement a stateless word decoder/executor with local operand snapshots and deterministic unsigned bit operations.
- [x] Rebuild and run `cgx1_isa_encoding_checks` to green; a temporary saturating-add mutation made the wrap test fail, then the wrapping implementation passed again.

### Task 2: Document provisional status and exact evidence

**Files:**
- Modify: `docs/ISA.md`
- Modify: `docs/ROADMAP.md`
- Modify: `docs/STATUS.md`
- Modify: `docs/ARTIFACT_PROVENANCE.md`
- Modify: `docs/VALIDATION.md`
- Modify: `design/cgx1_completeness_matrix.json`

- [x] Document the current RTL/reference opcode correspondence as provisional and state that other classes and complete instruction-stream execution remain open.
- [x] Record the focused executable test and keep fetch/decode/RTL issue integration as the next dependency candidate.
- [x] Run `ctest --test-dir build -R cgx1_isa_encoding_checks --output-on-failure`, matrix JSON parsing, repository consistency, Markdown-link, and `git diff --check` checks.
- [x] Update the candidate hash in the completeness matrix and inspect the full delta.
- [x] Commit a local checkpoint without pushing.
