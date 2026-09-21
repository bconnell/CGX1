# Resident-Wave VGPR Pool

[Documentation index](README.md) · [Matrix engine architecture](MATRIX_ENGINE.md) · [Project status](STATUS.md) · [Roadmap](ROADMAP.md)

## Scope

The pooled VGPR design separates a wave's architectural 256-VGPR namespace from the amount of shared physical storage assigned to that wave.

The earlier per-resident-slot VGPR RTL remains a validated logical storage boundary. It is not the physical allocation architecture.

The pooled implementation now exists as executable C++ reference code and synthesizable SystemVerilog candidate RTL. The pooled RTL is wired into the repository RTL gate, but exact-revision RTL simulation evidence remains pending until the current published revision passes that gate.

Nothing in this boundary freezes resident-wave occupancy, physical register-file capacity, foundry memory macros, timing, area, or power.

## Physical row mapping

The eight modulo-8 bank classes remain unchanged:

```text
bank = architectural VGPR mod 8
row  = physical row base + floor(architectural VGPR / 8)
```

A request for `N` architectural VGPRs consumes `ceil(N / 8)` physical rows. Row rounding controls physical capacity only. The exact requested register count controls legal architectural access.

For example, a 9-VGPR allocation occupies two rows, but VGPRs 9 through 15 remain inaccessible.

The executable allocator uses deterministic first-fit placement. First-fit is tested behavior, not a frozen production scheduling policy.

## Allocation lifetime

The implemented lifecycle is:

`Free -> Reserved -> sanitized -> optional privileged restore -> Active -> quiescent -> Release`

Reserved rows consume capacity immediately but matrix or shader execution cannot address them.

Validity metadata is invalidated one row at a time. Invalidation selection rotates across resident waves so one repeatedly recycled low-numbered wave does not monopolize sanitization.

Activation is blocked until every row in the reservation has been sanitized. A same-wave privileged restore also blocks activation for that cycle.

A sanitized Reserved allocation has an exact-count-bounded privileged restore path for dispatch initialization and future preemption restore work.

Active allocations cannot be relocated in place. Release requires quiescence. In the pooled matrix subsystem, release is also blocked by same-wave matrix execution, visible matrix VGPR read/write traffic, or a pending same-wave restore.

## Stale-data isolation

Physical VGPR data bits do not have to be cleared when rows are reassigned. Per-register validity controls visibility.

A new reservation invalidates validity metadata before activation. A first masked write to an uninitialized register zero-fills untouched lanes before applying the lane mask. A zero-lane write remains a no-op and does not initialize the register.

This prevents a new owner from observing data left by the previous owner without requiring a full data-array clear.

## Matrix issue preflight

Runtime pooled-VGPR readiness is separate from architectural matrix legality.

For a legal matrix register layout, issue requires:

- an Active allocation;
- D, A, and B spans fully contained by the exact requested VGPR count;
- initialized A0-A3;
- initialized B0-B3;
- initialized C/D0-C/D7.

Preflight is performed independently for each resident wave, preventing one uninitialized request from head-of-line blocking another ready wave.

Architecturally illegal matrix register layouts are forwarded to the existing matrix controller rather than converted into pooled-resource stalls. Full-wave legality remains controller-owned as well.

## Matrix data path

The pooled matrix frontend maps the frozen eight-cycle capture and eight-cycle writeback schedules onto physical row/bank addresses.

Exact A/B aliasing maps to one physical address and broadcasts the stored value. Distinct same-bank reads are rejected. Matrix read and write phases remain mutually exclusive under the frozen schedule.

The pooled matrix subsystem combines:

- row allocation;
- serialized validity invalidation;
- privileged Reserved restore;
- exact-count address translation;
- matrix initialization preflight;
- pooled data and validity storage;
- release safety;
- matrix capture and writeback arbitration.

The pooled resident INT8 wrapper connects this subsystem directly to the existing resident-wave signed INT8 engine. Ordinary vector execution remains outside this boundary.

## Validation

The executable reference suite covers:

- exact-count allocation from 1 through 256 VGPRs;
- exhaustive first-fit behavior for every occupancy pattern of an eight-row pool;
- 50,000 deterministic randomized lifecycle operations;
- serialized sanitization;
- privileged restore;
- quiescent release;
- stale-data isolation;
- first masked-write zero-fill;
- zero-lane writes;
- matrix range and initialization preflight;
- cross-wave preflight independence;
- architectural-illegality forwarding;
- capture/writeback physical row and bank mapping;
- exact alias broadcast;
- same-bank conflict rejection;
- restore/activation, restore/release, release/request, and busy-release arbitration.

The local pre-publication gate compiled and ran the executable references with GCC and Clang in C++20 mode, both normally and with `NDEBUG`, using `-Wall -Wextra -Werror -pedantic`.

The repository RTL gate now includes behavioral testbenches for pooled restore mapping, matrix preflight, allocation, storage, matrix frontend mapping, the composed pooled subsystem, and the pooled resident INT8 path.

## Evidence boundary

The pooled RTL files are implemented and published. Their `simulation_exercised` architecture evidence remains **false** until the exact published revision passes the repository RTL workflow.

Even after RTL simulation passes, this boundary remains logical/synthesizable implementation evidence. It does not select a foundry register-file macro or establish timing closure, area, power, resident-wave occupancy, or fabricated-silicon performance.
