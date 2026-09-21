# Resident-Wave VGPR Pool Reference

[Documentation index](README.md) · [Matrix engine architecture](MATRIX_ENGINE.md) · [Project status](STATUS.md) · [Roadmap](ROADMAP.md)

## Scope

The pooled VGPR reference separates the 256-register architectural namespace of a wave from the amount of physical storage assigned to that wave.

This is an executable implementation reference. It does not freeze resident-wave occupancy, a foundry memory macro, physical register-file capacity, timing, area, or power.

## Row organization

The reference retains the eight modulo-8 matrix bank classes already defined by the matrix architecture.

An architectural VGPR maps to:

```text
bank = architectural VGPR mod 8
row  = physical row base + floor(architectural VGPR / 8)
```

One physical row therefore represents one register from each of the eight bank classes. Allocation is expressed in rows rather than raw register numbers, so bank selection remains determined by the architectural VGPR index.

A request for `N` architectural VGPRs consumes `ceil(N / 8)` physical rows.

The current reference uses deterministic first-fit allocation. That policy is executable but is not a frozen production scheduling policy.

## Allocation lifetime

A resident-wave allocation moves through three states:

1. **Free**: no physical rows are assigned.
2. **Reserved**: a contiguous physical-row range is owned by the wave but cannot be addressed by shader or matrix execution.
3. **Active**: the allocation may be translated and accessed.

Reserved rows count as occupied immediately. Activation is permitted only after the storage-validity metadata for the reserved range has been invalidated.

An active allocation cannot be relocated in place. A different physical range requires release followed by a new reservation.

This separation prevents physical-row reuse from exposing the previous owner's register contents.

## Register initialization

Physical data bits are not required to be cleared when rows are reassigned. Per-register initialization state controls visibility.

A fresh allocation begins with every register marked uninitialized. Reading an uninitialized register is rejected by the executable reference.

For masked ordinary-vector writes, the first nonzero-lane write to a fresh register zero-fills the untouched lanes before applying the lane mask. A zero-lane write remains a no-op and does not initialize the register.

This rule prevents stale lane data from becoming visible after physical-row reuse while avoiding a requirement to clear the entire data array before activation.

## Matrix integration

The reference reuses the frozen matrix register layout, bank rules, capture schedule, and writeback-register schedule.

Before matrix capture begins, the complete D, A, and B register spans must fit inside the active wave allocation.

The eight capture cycles use the existing matrix schedule:

- cycles 0 through 3 read one A and one B whole-wave register;
- cycles 4 through 7 read two C/D whole-wave registers.

Exact A/B aliasing is treated as one stored value broadcast to both read results. Two distinct registers in the same bank class are rejected by the pooled-storage reference.

Matrix writeback uses the existing eight-cycle destination sequence and is subject to the same active-allocation bounds.

## Validation

`source/matrix/vgpr_pool_tests.cpp` checks allocation rounding, exhaustive first-fit behavior for every occupancy pattern of an eight-row pool, Reserved-to-Active invalidation ordering, rejection of pre-activation access, bank preservation, cross-wave storage isolation, matrix allocation bounds, complete matrix capture and writeback, exact source alias broadcast, same-bank conflict rejection, stale-data rejection after row reuse, masked-write sanitization, zero-lane writes, and 20,000 deterministic randomized operations with continuous pool-invariant checking.

The reference was compiled locally with GCC and Clang in C++20 mode using `-Wall -Wextra -Werror -pedantic` before publication.

## Remaining work

The next hardware boundary is an RTL implementation of the same lifecycle and translation contract:

- resident-wave allocation metadata;
- Reserved-to-Active validity invalidation;
- architectural VGPR to physical row/bank translation;
- pooled banked storage;
- matrix capture and writeback against that storage;
- shared access arbitration for the ordinary vector datapath.

SystemVerilog simulation evidence must exist before those items are recorded as implemented.
