# CGX1 Tile Eligibility Power Manager Design

## Goal

Replace the fixed P1/P2 tile-count mapping in `cgx1_top` with an RTL authority that publishes scheduler eligibility from the active board power state and each tile's reported operating state. Preserve the board-level P0 fallback and make emergency isolation visible at the top-level interface.

This design is based on the existing [Power Management contract](../../POWER_MANAGEMENT.md), its machine-readable architecture data, and the executable policy in `source/power/cgx1_power_management.hpp`.

## Authority and interface

- The firmware safety controller remains the source of `requested_power_state`. `cgx1_top` continues to register `active_power_state` and fall back to P0 for invalid requests, hardware faults, or loss of dock power/coolant while dock operation is active or requested.
- A new `cgx1_tile_power_manager` is the sole producer of the existing `tile_enable` vector. Its documented meaning is scheduler eligibility, not a physical power-gate control.
- `cgx1_top` accepts `emergency_thermal`, `tile_operating_state_flat` (three bits per tile), and the per-tile vectors `tile_power_good`, `tile_clocks_stable`, `tile_coherence_ready`, and `tile_isolation_asserted`. These are status inputs from tile control; the manager does not invent a tile's physical state.
- The manager publishes `tile_enable`, `tile_isolation_request`, and `emergency_isolation_required`. Reset, hardware fault, emergency thermal protection, or dock-power/coolant loss during active/requested dock operation asserts isolation for all tiles and immediately clears scheduler eligibility.

## Eligibility policy

A tile is scheduler eligible only when all of these hold:

1. Reset is deasserted, the requested board state is valid, and no emergency-isolation condition is active.
2. Its tile state is T3 Eco, T4 Nominal, or T5 Boost.
3. Its state is permitted by the stricter of the active and requested board-state caps: P0 permits through T2, P1 through T3, P2 through T4, and P3/P4 through T5. This applies a pending demotion immediately while a promotion waits for the registered active state.
4. Power-good, clocks-stable, and coherence-ready are asserted, and isolation is not asserted for that tile.

The top's registered `active_power_state` falls back to P0 on emergency or invalid request. The eligibility manager receives both active and requested state: a lower requested P-state caps eligibility in the same cycle, while a higher state cannot raise the cap until it becomes active.

The mask is computed independently per tile. P1 may therefore expose any subset of tiles actually in ready T3, and P2 any subset in ready T3/T4. Neither state selects a fixed tile count or tile index.

## Scope boundary

This is the RTL eligibility publisher and emergency override, not a DVFS sequencer, watt-budget allocator, clock/power gate, or tile-state producer. No voltage/frequency points, hysteresis timing, per-tile watt estimates, orderly drain sequencing, or physical isolation timing are introduced. Those require control/status and characterization contracts beyond the existing top-level scaffold.

## Validation

The functional `cgx1_top` test will cover every board cap, arbitrary eligible tile subsets, multiple eligible tiles in P1/P2, invalid tile states, each readiness gate, reset, invalid board requests, hardware and thermal emergencies, and dock-power/coolant loss. Emergency tests check both immediate all-tile isolation request and eligibility removal, followed by registered P0 fallback. The RTL validator and repository consistency checks will include the new authority and test; CTest continues to check the executable C++ policy.
