# CGX1 Tile Power Manager Implementation Plan

Design: [Tile Eligibility Power Manager](../specs/2026-10-03-cgx1-tile-power-manager-design.md)

## Contract

`cgx1_top` retains firmware board-state input and registered P0 fallback. A new `cgx1_tile_power_manager` derives the scheduler-eligibility mask from active/requested board caps, per-tile T0-T5 status, and readiness. Pending demotions apply immediately; promotions wait until active state catches up. Reset, thermal/hardware fault, or dock-power/coolant emergencies clear eligibility and request isolation for all tiles. P1/P2 do not imply fixed tile counts.

## Files

- `source/rtl/cgx1_top.sv`: retain the board-state safety register; replace P1/P2 count assignments with the manager's output and expose `emergency_thermal`, packed three-bit `tile_operating_state_flat`, four per-tile readiness/isolation vectors, and `tile_isolation_request`.
- `source/rtl/cgx1_tile_power_manager.sv`: centralize board caps, valid tile states, readiness gates, `scheduler_eligible_mask`, `emergency_isolation_request`, and `emergency_isolation_required`.
- `source/rtl/tests/cgx1_top_tb.sv`: exercise the actual top-level board fallback and manager connection.
- `scripts/validate_rtl.sh`: compile and run the top-level integration regression.
- `scripts/check_design_consistency.ps1`: check the policy authority and prevent reintroduction of fixed tile-count mappings.
- `source/power/cgx1_power_management.hpp` and `source/power/tests.cpp`: keep the executable emergency policy consistent with the top-level active/requested dock safety rule, and execute its assertions in Release builds.
- `docs/POWER_MANAGEMENT.md`, `docs/STATUS.md`, `docs/VALIDATION.md`, `source/rtl/README.md`, and `README.md`: describe the RTL boundary and limits accurately.

## Task 1: Prove the top-level policy gap

1. Add `cgx1_top_tb.sv` before changing RTL. Instantiate the real top with four tiles and drive actual per-tile status.
2. Check P0, P1, P2, P3, P4 caps; arbitrary ready tile subsets; no fixed count/index selection; invalid tile states; power, clock, coherence, and isolation gates; active/requested demotion behavior; reset; invalid board state; thermal/hardware fault; dock power loss; and coolant loss.
3. Add the bench compile/run command to `scripts/validate_rtl.sh` so the desired public boundary is explicit.
4. Compile/run it against the current RTL and capture the expected failure because the eligibility authority and status interface do not exist.

Expected: the test fails at compile/elaboration on missing power-manager interface, before any production RTL changes.

## Task 2: Implement the eligibility and emergency authority

1. Add the combinational `cgx1_tile_power_manager` and pass its output to the existing `tile_enable` port, documented as scheduler eligibility.
2. Derive the allowed ceiling from `min(active_power_state, requested_power_state)` using the architecture P0-P4 to T2-T5 table; invalid values fail closed.
3. Require a tile state of T3-T5 under the ceiling, power-good, stable clocks, coherence-ready, and no asserted isolation.
4. On reset, hardware fault, emergency thermal, or active/requested dock state without valid 48 V/coolant, mask eligibility and request isolation for all tiles immediately.
5. Keep `active_power_state` registered and falling back to P0 for emergency or invalid board-state requests. Remove the P1/P2 fixed bit-vector assignments only after the manager is connected.
6. Keep the executable C++ emergency policy aligned with active or requested dock operation, and retain runtime assertions in optimized Release builds.

Expected: Task 1's bench passes with no fixed P-state tile mapping.

## Task 3: Protect the contract in repository validation

1. Update `check_design_consistency.ps1` to check the new authority, cap policy, emergency gating, and top connection.
2. Add a source-level negative check for the old P1/P2 fixed-count expressions.
3. Run the top test, design consistency check, and a source-text negative control against the forbidden mapping hook.

Expected: correct policy passes, and the negative-control hook records a forbidden match.

## Task 4: Update documentation and checkpoint

1. Update the power-management contract, status table, validation evidence, and RTL README to distinguish scheduler eligibility from physical gating and identify external per-tile status inputs.
2. Record the design and implementation plan as completed with local evidence and exact hosted run IDs.
3. Run full `scripts/validate_rtl.sh`, all CTest targets, Windows consistency/link/integrity/hygiene checks, and exact-revision RTL/Windows CI.
4. Review the combined branch for interface correctness and evidence boundaries, then commit and push the existing feature branch.

Expected: exact commit has green local checks and hosted RTL/Windows workflows; no physical power, timing, area, or silicon result is claimed.

## Review focus

- No tile can become eligible in T0-T2, above the stricter active/requested P-state cap, while isolated, or before power, clocks, and coherence are ready.
- P1/P2 eligibility is driven only by tile status; no count or index is inferred from P-state.
- Hardware, thermal, dock-power, coolant, and reset emergencies immediately mask every tile and assert isolation request; board state falls to P0 through the existing sequential authority.
- Invalid board/tile encodings fail closed.
- The new boundary makes no claim about physical gate timing, DVFS transition sequencing, watts, timing, area, power, or silicon behavior.

## Execution status

- [x] Task 1: the top-level bench reproduced the missing manager/status interface before RTL implementation.
- [x] Task 2: the top-level P-state, per-tile eligibility, and emergency-isolation regression passes.
- [x] Task 3: the design-consistency negative control detects a forbidden fixed P1/P2 mapping.
- [x] Task 4 local gates: `bash scripts/validate_rtl.sh` passed under Icarus 12.0 in Ubuntu WSL; CTest passed 23/23 with the power-policy runtime assertions explicitly active in Release; Windows design consistency, Markdown links, repository integrity, public hygiene, and `git diff --check` passed.
- [x] Publish implementation commit `68cb2c3bb1c68df8c662a82959f1db8119deb8d0`; RTL CI run `37145496015` and Windows CI run `37145498188` passed on that exact commit.
- [x] Complete the final whole-delta review. It found the C++ emergency reference omitted pending dock requests; the reference, Release-active regression assertions, and policy documentation now match the existing top-level safety behavior, and the power-policy CTest plus all 23 CTest targets pass.
