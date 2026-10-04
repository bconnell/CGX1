# CGX1 Provisional Vector Instruction Stream Reference Plan

> **Execution:** Follow these test-first tasks in the existing CGX1 checkout and create one local checkpoint after validation.

**Goal:** Execute the current provisional INT32 vector subset from a bounded 32-bit instruction image using the wave's byte-addressed PC.

**Architecture:** A small C++ reference fetches one base word from an immutable span, routes only supported Vector-class opcodes to the existing vector semantics model, and advances PC by four only when execution succeeds. Fetch faults, unsupported classes, and illegal vector opcodes leave PC and vector state unchanged.

**Tech Stack:** C++20, `std::span`, existing CGX1 ISA decoder and vector semantics, CMake/CTest.

**Spec:** [ISA contract](../../ISA.md), [decoded control-flow contract](../../CONTROL_FLOW.md), and [provisional vector semantics](2026-10-04-cgx1-vector-semantics.md).

## Global Constraints

- Instruction addresses are four-byte aligned and within the 57-bit GPU virtual-address range.
- The reference image contains 32-bit base words only; this vector subset uses no extension words.
- Only a successfully executed supported vector instruction advances PC by four.
- Fetch faults, non-vector words, and illegal vector opcodes do not modify PC or VGPR state.
- The vector opcode mapping remains provisional; no memory/control opcode or operand formats are assigned.
- This reference does not model RTL backpressure, global memory, compilation, runtime dispatch, or physical behavior.

## Review Focus

- Unaligned, below-base, beyond-image, and out-of-range 57-bit PCs fail without state mutation.
- A dependent second instruction observes the first instruction's destination after PC advances.
- Unsupported classes and reserved vector opcodes leave PC and VGPR state unchanged.
- The final in-image vector word completes and leaves the next PC for the following fetch to fault if it is outside the image.

---

### Task 1: Add the bounded stream-step reference

**Files:**
- Create: `source/isa/cgx1_vector_stream.hpp`
- Modify: `source/isa/tests.cpp`

**Interface:**
- Produces `VectorStreamStepStatus` and `StepVectorInstructionStream(words, image_base, pc, registers, active_lane_mask)`.
- `words` is a `std::span<const std::uint32_t>`; `image_base` and `pc` are 64-bit containers validated against the 57-bit ISA address limit.

- [x] Add tests for sequential dependent execution, accepted-only PC advancement, fetch faults, unsupported classes, illegal opcodes, invalid image bases, and final-word behavior.
- [x] Build `cgx1_isa_tests` and confirm the missing stream API fails before implementation.
- [x] Implement bounded word selection and delegate arithmetic to `ExecuteVectorBaseInstruction`.
- [x] Rebuild and run the focused ISA CTest target.

### Task 2: Record scope and evidence

**Files:**
- Modify: `docs/ISA.md`
- Modify: `docs/STATUS.md`
- Modify: `docs/ROADMAP.md`
- Modify: `docs/VALIDATION.md`
- Modify: `docs/ARTIFACT_PROVENANCE.md`
- Modify: `design/cgx1_completeness_matrix.json`

- [x] Describe this as a bounded software reference, not RTL fetch or complete ISA execution.
- [x] Run the full C++ build/CTest suite (26/26 passed), matrix JSON, repository consistency, public hygiene, Markdown-link, and whitespace checks. Record the final candidate fingerprint before checkpointing.
- [ ] Inspect the full delta and commit one local checkpoint without pushing.
