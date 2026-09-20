# CGX 1 Matrix Engine Architecture

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [ISA](ISA.md) · [Software stack](SOFTWARE_STACK.md) · [Validation](VALIDATION.md)

This document defines the current CGX 1 matrix-engine architecture target. It covers numeric formats, physical tile dimensions, wave32 fragment ownership, register use, instruction encoding, issue timing, reduction order, and theoretical dense arithmetic rates.

The design is still pre-silicon. The rates in this document are architecture targets derived from the frozen execution model. They are not measured performance, and the current repository does not claim matrix RTL has closed timing, area, or power.

## Engine placement and cooperative scope

Each compute unit contains four SIMD32 partitions and four matrix engines. One matrix engine is paired with each SIMD32 partition.

A resident wave32 issues matrix work to the matrix engine paired with its SIMD32 partition. A matrix instruction is cooperative across all 32 lanes and requires a full active-lane mask. Compilers and runtimes must reconverge the wave before issuing a matrix instruction.

The logical operation is:

\x60D = A × B + C\x60

The base ISA uses a tied accumulator form, so the destination register group contains \x60C\x60 on input and receives \x60D\x60 on completion.

## Baseline precision profiles and tile shapes

| Opcode | A operand | B operand | Accumulator/result | Tile |
|---:|---|---|---|---|
| \x600x0\x60 | IEEE binary16 (FP16) | IEEE binary16 (FP16) | FP32 | M16N16K16 |
| \x600x1\x60 | BF16 | BF16 | FP32 | M16N16K16 |
| \x600x2\x60 | OCP FP8 E4M3 | OCP FP8 E4M3 | FP32 | M16N16K32 |
| \x600x3\x60 | OCP FP8 E4M3 | OCP FP8 E5M2 | FP32 | M16N16K32 |
| \x600x4\x60 | OCP FP8 E5M2 | OCP FP8 E4M3 | FP32 | M16N16K32 |
| \x600x5\x60 | OCP FP8 E5M2 | OCP FP8 E5M2 | FP32 | M16N16K32 |
| \x600x6\x60 | signed INT8 | signed INT8 | signed INT32 | M16N16K32 |

Opcodes \x600x7\x60 through \x600xF\x60 in the Matrix instruction class are reserved in this architecture revision.

FP32 input matrix acceleration, FP64 matrix acceleration, TF32, OCP MX block-scaled formats, unsigned or mixed-sign integer profiles, and structured sparsity acceleration are not part of the baseline.

The 16 × 16 output tile divides cleanly across wave32 while keeping eight 32-bit accumulator elements per lane. The deeper K dimension for 8-bit inputs keeps the source register footprint unchanged while allowing two 8-bit products per output element per execution cycle.

Public AMD/Clang WMMA documentation provides an external precedent for wave32 cooperative 16 × 16 matrix operations and eight FP32 accumulator elements per lane. CGX 1 does not use AMD's fragment layout or instruction semantics; its mapping is defined below and validated by the repository's executable model. See [Public Sources](SOURCES.md).

## Wave32 fragment ownership

The physical fragment mapping is part of the architecture contract.

### Accumulator/result fragment

Each lane owns eight elements of the 16 × 16 output tile.

For lane \x60L\x60 and local output element \x60e\x60, where \x600 <= L < 32\x60 and \x600 <= e < 8\x60:

\x60row = floor(L / 2)\x60

\x60column = (L mod 2) × 8 + e\x60

Therefore lanes 0 and 1 own output row 0, lanes 2 and 3 own output row 1, and so on. The even lane owns columns 0 through 7 and the odd lane owns columns 8 through 15.

### FP16/BF16 A fragment

A is a 16 × 16 matrix.

Each lane owns eight 16-bit A elements:

\x60row = floor(L / 2)\x60

\x60k = (L mod 2) × 8 + e\x60

The eight values are packed two per 32-bit VGPR, low half first, for four VGPRs per lane.

### FP16/BF16 B fragment

B is a 16 × 16 matrix.

Each lane owns eight 16-bit B elements:

\x60k = floor(L / 2)\x60

\x60column = (L mod 2) × 8 + e\x60

The eight values are packed two per 32-bit VGPR, low half first, for four VGPRs per lane.

### FP8/INT8 A fragment

A is a 16 × 32 matrix.

Each lane owns sixteen 8-bit A elements:

\x60row = floor(L / 2)\x60

\x60k = (L mod 2) × 16 + e\x60

The sixteen values are packed four per 32-bit VGPR in increasing byte order for four VGPRs per lane.

### FP8/INT8 B fragment

B is a 32 × 16 matrix.

Lane \x60L\x60 owns all sixteen columns for \x60k = L\x60:

\x60k = L\x60

\x60column = e\x60

The sixteen values are packed four per 32-bit VGPR in increasing byte order for four VGPRs per lane.

The executable architecture test proves that every required A, B, and D element is owned exactly once by the 32-lane wave for each supported tile shape.

## Register contract

Every baseline matrix opcode uses the same VGPR group sizes per lane:

| Fragment | VGPRs per lane | Alignment |
|---|---:|---:|
| A | 4 | 4-register boundary |
| B | 4 | 4-register boundary |
| C/D | 8 | 8-register boundary |

The instruction fields name the base register of each group.

The C/D group is read and written by the matrix instruction. It must not overlap either source group. A and B are read-only and may alias each other.

All groups must fit entirely inside the architectural 256-entry vector-register namespace.

Across one wave, a matrix instruction reads 2,048 bytes of fragment state and writes 1,024 bytes of result state.

## Matrix instruction encoding

Matrix operations use the existing 32-bit base ISA word:

~~~text
31          28 27          24 23          16 15           8 7            0
+--------------+--------------+--------------+--------------+--------------+
| class = 0x6  | opcode       | D/C base     | A base       | B base       |
+--------------+--------------+--------------+--------------+--------------+
~~~

No extension word is used by the baseline matrix opcodes.

The destination field names the tied C/D accumulator group. Source 0 names the A fragment and source 1 names the B fragment.

A malformed Matrix instruction is illegal when any of these conditions is true:

- the opcode is not \x600x0\x60 through \x600x6\x60;
- D/C is not aligned to an 8-register boundary;
- A or B is not aligned to a 4-register boundary;
- any register group extends beyond VGPR 255;
- D/C overlaps A or B;
- the instruction is issued with fewer than 32 active lanes.

## Execution pipeline

The architectural timing target for each matrix engine is:

| Stage | Cycles | Function |
|---|---:|---|
| Decode/dispatch | 1 | Validate opcode, register groups, active mask, and scoreboard dependencies |
| Fragment capture | 8 | Read A, B, and C/D from the SIMD partition's VGPR file into engine staging |
| Execute | 16 | Perform K reduction in the 16 × 16 matrix datapath |
| Writeback | 8 | Return the eight 32-bit D elements per lane to VGPRs |

The first result is visible **33 cycles after issue**.

Each engine has one input staging slot and one output staging slot in addition to the active execution state. This permits operand capture for the next operation during the final execution cycles of the current operation and result writeback while the following operation executes.

The architecture target is therefore one accepted matrix instruction per engine every **16 cycles**.

The register interface budget implied by this schedule is two 32-bit VGPR reads per lane per capture cycle and one 32-bit VGPR write per lane per writeback cycle.

This timing model is frozen as an architecture target. RTL timing closure, register-file banking, physical routing, area, power, and achievable clock frequency remain unvalidated.

## Physical reduction order

The previous numeric definition left K reduction order open until the physical datapath was chosen. The baseline per-instruction order is now fixed.

### FP16 and BF16

Each output element uses one FP32 accumulator chain.

Starting from C, K is processed in increasing order from 0 through 15:

\x60acc = fma(A[m,k], B[k,n], acc)\x60

Each step uses FP32 fused multiply-add semantics.

### FP8

Each output element has two FP32 accumulator chains so that two K terms are processed per execution cycle.

The even-K chain starts from C. The odd-K chain starts from +0.

For execution cycle \x60p = 0..15\x60:

\x60even = fma(A[m,2p], B[2p,n], even)\x60

\x60odd = fma(A[m,2p+1], B[2p+1,n], odd)\x60

After cycle 15:

\x60D = even + odd\x60

The final addition is an FP32 addition.

This fixes the reduction order for one CGX 1 matrix instruction. It does not require a larger GEMM, which may contain many matrix instructions, to use one globally deterministic tiling or scheduling order.

### INT8

INT8 uses the same even-K and odd-K split, with signed INT32 accumulation. Each product is exact in INT32. Each chain and the final combine use two's-complement modulo \x602^32\x60 arithmetic.

## Floating-point format behavior

FP16 uses IEEE 754 binary16 representation and special-value behavior.

BF16 uses one sign bit, eight exponent bits, and seven fraction bits. FP32 to BF16 conversion uses round to nearest, ties to even. BF16 retains FP32-style exponent range behavior, including infinities, NaNs, signed zero, and subnormal encodings. NaN payload preservation is not an architecture requirement.

FP16, BF16, and FP8 matrix operands widen exactly to FP32 before accumulation because every finite value in those source formats is exactly representable in FP32.

Implementations may use different internal circuit structures only when the architecturally visible result is equivalent to the reduction order and FP32 operations defined above.

Matrix floating-point operations do not create synchronous traps for ordinary NaN, infinity, underflow, or overflow data values. Invalid instruction use remains an architectural instruction fault.

## OCP FP8

CGX 1 uses the Open Compute Project OFP8 Revision 1.0 definitions.

**E4M3** uses one sign bit, four exponent bits, and three fraction bits. Its maximum finite magnitude is **448**. It represents NaN but not infinity.

**E5M2** uses one sign bit, five exponent bits, and two fraction bits. Its maximum finite magnitude is **57,344**. It represents both infinity and NaN.

Both formats retain their defined subnormal range. Conversion from a wider floating-point format supports round to nearest, ties to even and both OCP saturation modes:

| Conversion mode | E4M3 overflow or infinity input | E5M2 overflow or infinity input |
|---|---|---|
| Saturating | signed maximum finite | signed maximum finite |
| Non-saturating | NaN | signed infinity |

NaN converts to an FP8 NaN. NaN payload and sign propagation are not guaranteed.

## Dense arithmetic-rate targets

Dense matrix arithmetic counts one multiply and one add for every inner-product term:

\x60operations = 2 × M × N × K\x60

The 16-cycle issue interval gives:

| Profile | Operations/instruction | Operations/engine/cycle |
|---|---:|---:|
| FP16/BF16 M16N16K16 | 8,192 | 512 |
| FP8/INT8 M16N16K32 | 16,384 | 1,024 |

With four engines per compute unit and 200 compute units, the architecture target contains 800 matrix engines.

| Profile | At 2.65 GHz sustained-clock target | At 2.80 GHz peak-clock target |
|---|---:|---:|
| FP16 | 1,085.44 TFLOPS | 1,146.88 TFLOPS |
| BF16 | 1,085.44 TFLOPS | 1,146.88 TFLOPS |
| FP8 | 2,170.88 TFLOPS | 2,293.76 TFLOPS |
| signed INT8 | 2,170.88 TOPS | 2,293.76 TOPS |

These are theoretical dense arithmetic targets derived directly from the frozen engine count, tile work, issue interval, and clock targets. They are not measured silicon throughput or application performance.

No structured-sparsity multiplier is applied. The repository still does not publish an independent AI TOPS benchmark figure.

## Capability discovery and compiler contract

A driver reports supported matrix tuples rather than exposing combinations the implementation cannot execute.

The baseline tuples now have fixed dimensions:

- FP16 × FP16 → FP32: M16N16K16;
- BF16 × BF16 → FP32: M16N16K16;
- all four OCP FP8 E4M3/E5M2 input pairings → FP32: M16N16K32;
- signed INT8 × signed INT8 → signed INT32: M16N16K32.

The matrix instruction itself consumes canonical in-register fragments. Memory row/column layout, transpose requests, and API-specific cooperative matrix layouts are compiler/runtime concerns and must lower into the canonical fragment mapping before the matrix opcode executes.

## Scoreboarding and dependencies

Issue logic tracks the entire D/C destination range as pending until writeback completes.

A later instruction that reads or writes any pending destination VGPR stalls until the matrix result is available. A and B are captured during the eight-cycle capture stage; once capture completes, later instructions may overwrite those source registers without affecting the in-flight matrix operation.

Independent waves and independent instructions may make progress while a matrix result is pending, subject to normal SIMD and register-file scheduling constraints.

## MX formats

OCP MX remains future work. Ordinary OFP8 support does not establish MX support.

Adding MX requires a defined shared block-scale storage and delivery path, block sizes, instruction operands, compiler lowering, conversion rules, executable validation, and a revised datapath contract.

## Executable references

[source/matrix/cgx1_matrix.hpp](../source/matrix/cgx1_matrix.hpp) and [source/matrix/tests.cpp](../source/matrix/tests.cpp) validate numeric formats and conversion behavior.

[source/matrix/cgx1_matrix_architecture.hpp](../source/matrix/cgx1_matrix_architecture.hpp) and [source/matrix/architecture_tests.cpp](../source/matrix/architecture_tests.cpp) validate:

- physical M/N/K shapes for all seven baseline opcodes;
- exact lane ownership of every A, B, and D element;
- 8-bit and 16-bit packing locations;
- fixed VGPR group sizes, alignment, range, and overlap rules;
- base ISA Matrix opcode validation;
- capture, execution, writeback, issue-interval, and latency constants;
- per-instruction floating-point and integer reduction order;
- dense arithmetic operation counts and device-level rate calculations.

The executable model is an architecture reference. It is not matrix RTL, timing closure, area estimation, power characterization, or measured hardware performance.

## Remaining implementation work

The next implementation boundary is matrix RTL and feasibility closure:

- design the register-file banking and cross-lane delivery network required by the capture budget;
- implement the 16 × 16 product/accumulator datapath and dual 8-bit paths;
- implement input and output staging plus scoreboard integration;
- verify exact instruction behavior against the executable reference;
- synthesize the matrix engine on the selected process assumptions;
- measure timing, area, and power against the compute-unit budget;
- revise the architectural timing target if physical evidence shows it cannot close;
- add compiler lowering and API capability exposure;
- build matrix conformance workloads;
- validate fabricated silicon before reporting measured performance.

See [Public Sources](SOURCES.md) for IEEE 754, BF16, OCP FP8, OCP MX, Vulkan cooperative matrix, and public wave-matrix references.
