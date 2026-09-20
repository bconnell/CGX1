# CGX 1 Power Management

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [Electrical interface](ELECTRICAL_INTERFACE.md) · [Scheduling and preemption](SCHEDULING_PREEMPTION.md)

This document defines the internal power-management contract beneath the existing P0-P4 board power states. It is an architecture target and executable policy reference, not a characterized silicon voltage/frequency curve.

## Authority

CGX 1 separates safety authority from performance policy.

- The existing firmware safety controller selects the permitted **board power state** and retains authority over dock, coolant, thermal, and hardware-fault fallback.
- The I/O-die power-management controller allocates compute-tile capacity **inside** the power limit of that board state.
- The scheduler requests capacity and consumes a tile-eligibility mask. It does not directly control voltage rails, power gates, or isolation.
- The internal controller may reduce performance below the board-state maximum at any time. It may not raise the board into a higher P-state.

This keeps P0-P4 as electrical/safety envelopes instead of turning them into fixed tile-count presets.

## Board states and tile states

Board power limits remain unchanged:

| Board state | Board limit | Dock required | Highest tile operating class permitted |
|---|---:|---|---|
| P0 Safe Boot | 25 W | No | T2 Idle |
| P1 Slot Eco | 45 W | No | T3 Eco |
| P2 Slot Max | 70 W | No | T4 Nominal |
| P3 Dock Quiet | 220 W | Yes | T5 Boost |
| P4 Dock Full | 360 W | Yes | T5 Boost |

The tile-state cap is a permission, not a command. A P4 board may have zero, one, or several schedulable tiles depending on workload, telemetry, and the board budget.

Tile operating states:

| Tile state | Meaning | Scheduler eligible |
|---|---|---|
| T0 Off | Compute-tile power gated; architectural execution state not retained | No |
| T1 Retention | Minimum retained state for restart; execution unavailable | No |
| T2 Idle | Powered/coherent control state; execution clocks substantially gated | No |
| T3 Eco | Schedulable low-power execution class | Yes |
| T4 Nominal | Schedulable normal execution class | Yes |
| T5 Boost | Schedulable highest performance class permitted by available electrical and thermal headroom | Yes |

T3-T5 are policy classes, not frozen frequencies or voltages.

## DVFS boundary

The existing GPU-core target range is **0.55 V to 0.90 V**, with 2.65 GHz sustained and 2.80 GHz peak architecture clock targets.

CGX 1 does **not** publish a fabricated V/F curve. Exact per-tile voltage/frequency points require timing closure, process data, leakage analysis, power characterization, and silicon measurement.

The sequencing contract is still fixed:

- performance may increase only after the required voltage state is established;
- voltage may decrease only after clock frequency is at or below the lower safe target;
- a tile may not become scheduler eligible until power, clocks, isolation, and coherence state are valid;
- a tile leaving execution must become scheduler ineligible before retention or power gating.

The four compute tiles target independent DVFS control. This does not imply four independent software-visible GPUs.

## Board-budget invariant

The power controller tracks a non-tile budget plus an authorized budget for each compute tile.

For an active board state:

```text
non-tile budget
+ tile 0 budget
+ tile 1 budget
+ tile 2 budget
+ tile 3 budget
<= active P-state board limit
```

The reference model rejects negative, non-finite, and over-limit requests.

These are controller budgets, not claims that an uncharacterized tile consumes a specific number of watts. Final budgets must be calibrated against rail telemetry and characterized silicon.

There is intentionally **no fixed mapping such as P1 = one tile or P2 = two tiles**. The controller may prefer more tiles at lower V/F or fewer tiles at higher V/F when measurements demonstrate that one policy is more efficient.

## Clock and power gating

The physical implementation should support clock gating below the tile level for idle execution resources, including:

- CU groups;
- texture blocks;
- raster/back-end blocks;
- matrix engines;
- ray engines;
- tile-local fabric and cache interfaces where coherence permits.

Whole-tile power gating is separate from fine-grained clock gating.

A unit being clock gated must not make its parent tile disappear from coherence or scheduling state unless the corresponding tile transition is completed.

## Memory and package-cache domains

HBM and package-cache power policy is independent of active compute-tile count.

A tile becoming idle or off must not automatically power down memory required by:

- another compute tile;
- PCIe transfers;
- display scanout;
- media engines;
- firmware;
- page tables or fault handling.

P0 guarantees the control and diagnostic behavior required for safe boot. CGX 1 does **not** currently claim that all HBM capacity remains fully active and addressable inside the 25 W P0 envelope. That behavior must be established by memory-controller design and measured power data.

## Orderly tile power-down

A normal transition toward retention/off follows this logical order:

1. stop new dispatch to the tile;
2. drain or preempt current work at an allowed boundary;
3. resolve dirty coherent state by writeback or ownership transfer;
4. remove the tile from the scheduler-eligible mask;
5. reduce clock state in a safe V/F order;
6. gate execution clocks;
7. assert isolation before retention/off;
8. enter retention or remove tile power.

A dirty coherent tile must not be intentionally power gated through the orderly path before its required state is resolved.

## Orderly tile power-up

A normal wake follows this logical order:

1. establish tile power;
2. establish the required voltage state;
3. verify power-good;
4. start and stabilize required clocks;
5. restore or initialize retained state;
6. release isolation;
7. join the coherence domain;
8. publish scheduler eligibility only after the tile is ready to execute.

The final hardware design must define timing and acknowledgement signals for each boundary.

## Emergency behavior

Emergency safety has higher authority than orderly performance transitions.

Hardware fault, emergency thermal protection, or dock/coolant loss while a docked state is active may require immediate isolation before normal drain/writeback can finish. In that case:

- the tile is removed from scheduler eligibility immediately;
- unfinished work may be lost;
- dirty state that could not be made coherent is not claimed to be preserved;
- firmware/driver recovery must report the resulting context or device loss;
- the existing board-level controller retains the P0 fallback behavior.

The repository therefore does not claim that an emergency power cut is equivalent to an orderly tile shutdown.

## Hysteresis

Performance promotion and demotion require hysteresis so brief utilization changes do not cause continuous voltage, frequency, or power-gate oscillation.

The architecture requires hysteresis but does not freeze time constants or sample counts. Those values must come from controller-loop stability work and silicon characterization.

Emergency fault response is not delayed by performance hysteresis.

## Scheduler contract

The power manager publishes an eligible-tile mask.

The scheduler:

- dispatches only to eligible tiles;
- stops assigning new work before an orderly tile shutdown;
- cooperates with preemption/drain requests;
- redistributes runnable work when available tile count changes;
- retains its fairness/aging guarantees across eligible resources.

Power management must not create a permanently starved queue simply because tile availability changes.

## Reference implementation

[`source/power/cgx1_power_management.hpp`](../source/power/cgx1_power_management.hpp) and its executable tests model:

- unchanged P0-P4 board limits;
- rejection of invalid board-state and tile-state values;
- dock-state identification;
- maximum tile classes per board state;
- scheduler eligibility;
- combined rejection of plans that violate either tile-state caps or the active board budget;
- total board-budget enforcement;
- exhaustive rejection of skipped orderly tile transitions;
- V/F sequencing guards;
- coherence-ready guards before wake reaches Idle or becomes scheduler eligible;
- dirty-state and scheduler-drain guards;
- emergency isolation conditions;
- configurable hysteresis acceptance.

The reference implementation is a policy/invariant model. It is not a regulator driver, physical power controller, or measured silicon power model.
