# CGX1 RTL Command Queue Rings Implementation Plan

> **Implementation note:** Keep each step test-first and run the focused Icarus bench before the full RTL gate.

**Goal:** Add parameterized per-context byte rings and a fair packet feeder in front of the existing RTL parser and one-CU dispatcher.

**Architecture:** A ready/valid byte-write ingress selects a registered queue ring. A round-robin feeder offers only complete trustworthy packets, or enough header bytes for the parser to fault an untrustworthy envelope. The ring consumer stays pinned until the parser completion or CUDS descriptor handshake commits the command outcome.

**Spec:** [2026-10-03-cgx1-rtl-command-queue-ring-design.md](../specs/2026-10-03-cgx1-rtl-command-queue-ring-design.md)

## Constraints

- Mirror the C++ reference defaults of 64 contexts and 4,096 bytes per context, with the reference's 65,536-byte per-context and 4 MiB aggregate bounds. Keep capacities parameterized and do not claim a physical SRAM implementation.
- Preserve the provisional v1 packet format and existing parser/CUDS contracts.
- Do not hold an incomplete packet's context lock; another complete context must progress.
- Do not advance ring consumer state before accepted parser/dispatcher outcome.
- Call recovery `ingress_recovery_*`; it drops unread ingress bytes and clears parser fault state only. It does not cancel complete parser/CUDS descriptors.
- Do not claim queue unregistration/reuse, full queue cancellation, final retirement completion, global multi-CU placement, or a frozen ABI.

## Tasks

1. [x] Add a focused integration bench that connects the ring frontend, existing parser, and existing CUDS. It first failed at elaboration because the ring module was absent; the final bench covers registration, byte-ring behavior, wrap, incomplete-context skipping, correlation, and parser recovery ownership.
2. [x] Implement registered metadata/incarnation state, bounded ring storage, ready/valid byte ingress, per-context positions/occupancy, round-robin complete-frame selection, consumer commit, and ingress-only recovery.
3. [x] Add deterministic seeded inter-byte gaps, repeated wrap across independent contexts, round-robin arbitration with two contexts ready, reset with unread/queued state, and continuous occupancy/position invariants.
4. [x] Add the new bench to `scripts/validate_rtl.sh`; the focused bench and complete Icarus 12.0 RTL gate passed.
5. [x] Run WSL CMake/CTest (26/26), the Windows wrapper's hygiene/integrity/design/negative-control/Markdown checks, JSON and exact-candidate fingerprint validation. The Windows wrapper stopped at CMake because `cmake.exe` is unavailable on Windows PATH; lifecycle limits are recorded in the spec, status, validation document, and matrix.
6. [x] Review the complete diff, update the ignored SDD progress ledger, and create a local checkpoint without pushing. Continue with `rtl_command_queue_lifecycle_completion`.
