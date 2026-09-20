# CGX 1 Matrix Engine Architecture

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [ISA](ISA.md) · [Software stack](SOFTWARE_STACK.md) · [Validation](VALIDATION.md)

This document defines the current CGX 1 matrix-engine architecture target. It covers numeric formats, physical tile dimensions, wave32 fragment ownership, register use, instruction encoding, issue timing, reduction order, and theoretical dense arithmetic rates.

The design is still pre-silicon. The rates in this document are architecture targets derived from the frozen execution model. They are not measured performance, and the current repository does not claim matrix RTL has closed timing, area, or power.

## Engine placement and cooperative scope

Each compute unit contains four SIMD32 partitions and four matrix engines. One matrix engine is paired with each SIMD32 partition.

A resident wave32 issues matrix work to the matrix engine paired with its SIMD32 partition. A matrix instruction is cooperative across all 32 lanes and requires a full active-lane mask. Compilers and runtimes must reconverge the wave before issuing a matrix instruction.

The logical operation is:

`D = A × B + C`

The base ISA uses a tied accumulator form, so the destination register group contains `C` on input and receives `D` on completion.

## Baseline precision profiles and tile shapes

| Opcode | A operand | B operand | Accumulator/result | Tile |
|---:|---|---|---|---|
| `0x0` | IEEE binary16 (FP16) | IEEE binary16 (FP16) | FP32 | M16N16K16 |
| `0x1` | BF16 | BF16 | FP32 | M16N16K16 |
| `0x2` | OCP FP8 E4M3 | OCP FP8 E4M3 | FP32 | M16N16K32 |
| `0x3` | OCP FP8 E4M3 | OCP FP8 E5M2 | FP32 | M16N16K32 |
| `0x4` | OCP FP8 E5M2 | OCP FP8 E4M3 | FP32 | M16N16K32 |
| `0x5` | OCP FP8 E5M2 | OCP FP8 E5M2 | FP32 | M16N16K32 |
| `0x6` | signed INT8 | signed INT8 | signed INT32 | M16N16K32 |

Opcodes `0x7` through `0xF` in the Matrix instruction class are reserved in this architecture revision.

FP32 input matrix acceleration, FP64 matrix acceleration, TF32, OCP MX block-scaled formats, unsigned or mixed-sign integer profiles, and structured sparsity acceleration are not part of the baseline.

The 16 × 16 output tile divides cleanly across wave32 while keeping eight 32-bit accumulator elements per lane. The deeper K dimension for 8-bit inputs keeps the source register footprint unchanged while allowing two 8-bit products per output element per execution cycle.

Public AMD/Clang WMMA documentation provides an external precedent for wave32 cooperative 16 × 16 matrix operations and eight FP32 accumulator elements per lane. CGX 1 does not use AMD's fragment layout or instruction semantics; its mapping is defined below and validated by the repository's executable model. See [Public Sources](SOURCES.md).

## Wave32 fragment ownership

The physical fragment mapping is part of the architecture contract.

### Accumulator/result fragment

Each lane owns eight elements of the 16 × 16 output tile.

For lane `L` and local output element `e`, where `0 <= L < 32` and `0 <= e < 8`:

`row = floor(L / 2)`

`column = (L mod 2) × 8 + e`

Therefore lanes 0 and 1 own output row 0, lanes 2 and 3 own output row 1, and so on. The even lane owns columns 0 through 7 and the odd lane owns columns 8 through 15.

### FP16/BF16 A fragment

A is a 16 × 16 matrix.

Each lane owns eight 16-bit A elements:

`row = floor(L / 2)`

`k = (L mod 2) × 8 + e`

The eight values are packed two per 32-bit VGPR, low half first, for four VGPRs per lane.

### FP16/BF16 B fragment

B is a 16 × 16 matrix.

Each lane owns eight 16-bit B elements:

`k = floor(L / 2)`

`column = (L mod 2) × 8 + e`

The eight values are packed two per 32-bit VGPR, low half first, for four VGPRs per lane.

### FP8/INT8 A fragment

A is a 16 × 32 matrix.

Each lane owns sixteen 8-bit A elements:

`row = floor(L / 2)`

`k = (L mod 2) × 16 + e`

The sixteen values are packed four per 32-bit VGPR in increasing byte order for four VGPRs per lane.

### FP8/INT8 B fragment

B is a 32 × 16 matrix.

Lane `L` owns all sixteen columns for `k = L`:

`k = L`

`column = e`

The sixteen values are packed four per 32-bit VGPR in increasing byte order for four VGPRs per lane.

The executable architecture test proves that every required A, B, and D element is owned exactly once by the 32-lane wave for each supported tile shape.

## Register contract

Every baseline matrix opcode uses the same VGPR group sizes per lane:

| Fragment | VGPRs per lane | Alignment |
|---|---:|---:|
| A | 4 | base register congruent to 0 modulo 8 |
| B | 4 | base register congruent to 4 modulo 8 when distinct from A; exact A alias allowed |
| C/D | 8 | base register congruent to 0 modulo 8 |

The instruction fields name the base register of each group.

The C/D group is read and written by the matrix instruction. It must not overlap either source group. A and B are read-only. They may be exact aliases; otherwise their required modulo-8 base classes keep the two source reads in different register bank classes.

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

- the opcode is not `0x0` through `0x6`;
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

The register interface budget implied by this schedule is two whole-wave VGPR reads per capture cycle and one whole-wave VGPR write per writeback cycle. A wave32 VGPR read or write transfers 32 × 32-bit lane words, or 1,024 bits. The matrix path therefore consumes 2,048 read bits per capture cycle or 1,024 write bits per writeback cycle.

This timing model is frozen as an architecture target. RTL timing closure, register-file banking, physical routing, area, power, and achievable clock frequency remain unvalidated.

### Register-file capture schedule

The baseline matrix interface reuses the SIMD partition's logical vector-register bandwidth rather than assuming an additional unverified matrix-only register file port.

The eight capture cycles are fixed:

| Capture cycle | Read port 0 | Read port 1 |
|---:|---|---|
| 0 | A register offset 0 | B register offset 0 |
| 1 | A register offset 1 | B register offset 1 |
| 2 | A register offset 2 | B register offset 2 |
| 3 | A register offset 3 | B register offset 3 |
| 4 | C/D register offset 0 | C/D register offset 1 |
| 5 | C/D register offset 2 | C/D register offset 3 |
| 6 | C/D register offset 4 | C/D register offset 5 |
| 7 | C/D register offset 6 | C/D register offset 7 |

Writeback uses one whole-wave VGPR write per cycle for destination offsets 0 through 7.

With matrix instructions issued every 16 cycles, the capture window of one operation and the writeback window of the preceding operation do **not** overlap. The matrix path therefore does not require simultaneous matrix read and write access to the SIMD partition's VGPR interface. This statement is about the logical schedule; the physical bank organization is still an RTL implementation choice.

The 2,048-byte input staging requirement is exact for every baseline profile:

- 512 bytes for A;
- 512 bytes for B;
- 1,024 bytes for C/D.

### Double-buffered operand storage

The 16-cycle issue interval overlaps the next instruction's capture with the current instruction's execution. The 2,048-byte capture buffer therefore cannot also be the only execution operand store.

Each engine has a separate **2,048-byte active-execution operand set**. On capture cycle 7, the completed capture buffer commits into the active set. The following instruction may then begin overwriting the capture buffer while the executing instruction continues to use the active set.

The logical per-engine pipeline storage target is:

| Storage role | Bytes |
|---|---:|
| Capture buffer | 2,048 |
| Active execution operands | 2,048 |
| Output result slot | 1,024 |
| **Logical total per engine** | **5,120** |
| **Logical total per CU, four engines** | **20,480** |

The 1,024-byte output result slot now has an executable reference model and synthesizable staging RTL. It accepts one completed eight-register wave result set, presents one 1,024-bit wave register per writeback cycle in offsets 0 through 7, rejects overwrite while occupied, and releases the slot after writeback cycle 7. The matrix pipeline controller exposes the authoritative writeback-cycle index used by this contract.

The input/active and output staging blocks use synthesizable registers as reference implementations. They do not select or validate physical SRAM/register-file macros, routing, timing, area, or power. The arithmetic datapath that produces the completed result set is still not implemented.

The matrix pipeline controller exposes its capture-cycle index so the staging block receives the same authoritative cycle position used for register-address generation.

### Register bank classes

The architecture now defines an eight-class register banking rule for matrix transfers:

`bank = VGPR index mod 8`

This is a logical bank-class contract, not a claim about the number, dimensions, or circuit implementation of physical SRAM/register-file macros.

A uses base register class 0. A distinct B uses base register class 4. C/D uses an 8-register-aligned base and therefore starts in class 0.

For A/B capture cycles 0 through 3, source offsets are identical, so the two distinct source addresses land in bank classes `0..3` and `4..7` respectively. For C/D capture cycles 4 through 7, the two adjacent C/D registers land in different classes. Writeback uses one destination register per cycle.

An exact A/B register alias is also legal. In that case the same physical register value can be read once and routed to both deterministic staging destinations. This is a broadcast case, not two accesses to the same bank.

The executable banking test exhaustively enumerates every valid destination/A/B base-register combination in the 256-entry VGPR namespace and verifies that every capture cycle is conflict-free under a single-matrix-access-per-bank-class rule.

Physical storage depth, macro partitioning, wiring, clock closure, area, and power remain unvalidated. Those require RTL and implementation evidence.

The canonical fragment mapping makes the lane-to-staging destination deterministic from lane ID, register offset, and packed element position. No software-visible dynamic permutation selector is part of the architecture.

During capture, a following instruction that would overwrite A or B must wait until the eight capture cycles finish. The C/D destination remains pending until the end of writeback. Vector instructions in the same SIMD partition that require conflicting VGPR ports stall while matrix capture or writeback owns those ports. These are scheduler rules, not measured performance claims.

## Physical reduction order

The previous numeric definition left K reduction order open until the physical datapath was chosen. The baseline per-instruction order is now fixed.

### FP16 and BF16

Each output element uses one FP32 accumulator chain.

Starting from C, K is processed in increasing order from 0 through 15:

`acc = fma(A[m,k], B[k,n], acc)`

Each step uses FP32 fused multiply-add semantics.

### FP8

Each output element has two FP32 accumulator chains so that two K terms are processed per execution cycle.

The even-K chain starts from C. The odd-K chain starts from +0.

For execution cycle `p = 0..15`:

`even = fma(A[m,2p], B[2p,n], even)`

`odd = fma(A[m,2p+1], B[2p+1,n], odd)`

After cycle 15:

`D = even + odd`

The final addition is an FP32 addition.

This fixes the reduction order for one CGX 1 matrix instruction. It does not require a larger GEMM, which may contain many matrix instructions, to use one globally deterministic tiling or scheduling order.

### INT8

INT8 uses the same even-K and odd-K split, with signed INT32 accumulation. Each product is exact in INT32. Each chain and the final combine use two's-complement modulo `2^32` arithmetic.

### INT8 execution RTL

The signed INT8 M16N16K32 path now has an executable reference implementation and a SystemVerilog arithmetic implementation.

The implementation consumes the canonical 4-register A fragment, 4-register B fragment, and 8-register signed INT32 C fragment already defined by this architecture. Over the 16 execution cycles, each output processes two K terms per cycle:

- the even-K chain starts from C;
- the odd-K chain starts from zero;
- both chains use exact signed 8 × 8 products represented in signed INT32;
- all accumulator additions wrap modulo `2^32`;
- execution cycle 15 combines the two chains modulo `2^32` and produces the canonical eight-register result fragment.

The reference and RTL tests cover full-tile patterned data, signed extreme inputs, canonical fragment packing, execution-cycle ordering, result-valid timing, and explicit 32-bit wraparound.

This is functional arithmetic RTL only. It does not establish achievable clock frequency, physical multiplier organization, area, power, or the 2.65/2.80 GHz clock targets. FP16, BF16, and FP8 arithmetic RTL remain unimplemented because their frozen contract requires FP32 fused multiply-add semantics; those paths will not be represented by a non-fused multiply/add substitute.

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

`operations = 2 × M × N × K`

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

The matrix pipeline controller performs matrix-to-matrix dependency checks against every older in-flight matrix destination. A new matrix instruction stalls when either source range overlaps an older pending D/C range (RAW) or when its tied C/D range overlaps an older pending D/C range (WAW plus the tied-accumulator read dependency). A dependency stall is not an illegal-instruction fault; issue resumes after the older destination completes.

Matrix-to-matrix WAR does not require a separate interlock at the frozen minimum issue interval because A/B capture ends after 8 cycles while another matrix instruction cannot issue sooner than 16 cycles.

A separate per-wave VGPR scoreboard now tracks matrix source reservations until source release and matrix destination reservations until destination completion. For an ordinary VGPR instruction in the same wave, it reports:

- RAW when an ordinary read overlaps a pending matrix destination;
- WAW when an ordinary write overlaps a pending matrix destination;
- WAR when an ordinary write overlaps a matrix source that is still being captured;
- read-port conflict while matrix capture owns the two whole-wave read ports;
- write-port conflict while matrix writeback owns the whole-wave write port.

An ordinary read of an unrelated register is not blocked merely because matrix writeback is active, and an unrelated write is not blocked merely because matrix capture is active. The scoreboard reports only the data or port conflicts defined above.

The scoreboard block is scoped to one wave context. Its reservation event uses the matrix controller's registered acceptance pulse together with controller-latched D/A/B register bases, so the producer may change the live issue payload after the handshake without changing the reservation. Resident-wave identity, arbitration among multiple wave contexts, and connection to a real ordinary vector issue pipeline remain future compute-unit integration work.

A and B are captured during the eight-cycle capture stage; once source release has been recorded, later non-matrix instructions may overwrite those source registers without affecting the in-flight matrix operation.

Independent waves and independent instructions may make progress while a matrix result is pending, subject to the future multi-wave scheduler and register-file arbitration rules.

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

[source/matrix/cgx1_matrix_pipeline.hpp](../source/matrix/cgx1_matrix_pipeline.hpp) and [source/matrix/pipeline_tests.cpp](../source/matrix/pipeline_tests.cpp) validate the exact capture/writeback register schedule, 2,048-byte input staging budget, whole-wave register interface demand, source/destination hazard lifetimes, matrix-to-matrix pending-destination dependency detection, and steady-state 16-cycle overlap without simultaneous matrix read/write demand. The dependency test exhaustively checks every legal non-aliased matrix register layout against every aligned pending D/C range.

[source/matrix/cgx1_matrix_banking.hpp](../source/matrix/cgx1_matrix_banking.hpp) and [source/matrix/banking_tests.cpp](../source/matrix/banking_tests.cpp) validate modulo-8 bank selection, source base-class rules, exact-alias broadcast behavior, and exhaustive conflict freedom for every valid matrix register layout.

[source/rtl/cgx1_matrix_pipeline_control.sv](../source/rtl/cgx1_matrix_pipeline_control.sv) and its SystemVerilog testbench implement and simulate matrix instruction legality, capture/execute/writeback control, bank-safe VGPR addresses, 16-cycle reissue control, source-release and destination-complete events, and matrix-to-matrix RAW/WAW stalling against older pending destinations. The controller is control RTL only; it does not implement the arithmetic datapath, physical VGPR macros, or the general compute-unit scoreboard.

[source/matrix/cgx1_matrix_staging.hpp](../source/matrix/cgx1_matrix_staging.hpp) and [source/matrix/staging_tests.cpp](../source/matrix/staging_tests.cpp) validate capture ordering, the 2 KB capture buffer, the separate 2 KB active operand set, commit on capture cycle 7, and preservation of active operands while the next capture is in progress.

[source/rtl/cgx1_matrix_operand_staging.sv](../source/rtl/cgx1_matrix_operand_staging.sv) and its SystemVerilog testbench implement and simulate the same capture-to-active transfer. The output-result slot, arithmetic datapath, and physical storage macro implementation remain open work.

[source/matrix/cgx1_matrix_scoreboard.hpp](../source/matrix/cgx1_matrix_scoreboard.hpp) and [source/matrix/scoreboard_tests.cpp](../source/matrix/scoreboard_tests.cpp) validate the 256-VGPR per-wave reservation model, exhaustive single-register ordinary RAW/WAW/WAR behavior, source release, destination completion, multiple independent pending matrix destinations, and matrix read/write-port conflicts.

[source/rtl/cgx1_matrix_wave_scoreboard.sv](../source/rtl/cgx1_matrix_wave_scoreboard.sv) and its integration testbench connect the scoreboard to the existing matrix pipeline controller events and simulate the same-wave ordinary issue decisions. The test does not implement an ordinary vector execution pipe or multi-wave scheduler.

[source/matrix/cgx1_matrix_result_staging.hpp](../source/matrix/cgx1_matrix_result_staging.hpp) and [source/matrix/result_staging_tests.cpp](../source/matrix/result_staging_tests.cpp) validate the 1,024-byte output slot, occupied-slot rejection, ordered writeback consumption, cycle-7 release, and reuse after drain.

[source/rtl/cgx1_matrix_result_staging.sv](../source/rtl/cgx1_matrix_result_staging.sv) and its SystemVerilog testbench implement and simulate the same eight-register result slot and ordered writeback data selection. Result generation remains outside this block.

[source/matrix/cgx1_matrix_int8_execution.hpp](../source/matrix/cgx1_matrix_int8_execution.hpp) and [source/matrix/int8_execution_tests.cpp](../source/matrix/int8_execution_tests.cpp) implement and validate the signed INT8 M16N16K32 execution contract, canonical operand/result mapping, 16-cycle even/odd reduction, and modulo-`2^32` behavior.

[source/rtl/cgx1_matrix_int8_execution.sv](../source/rtl/cgx1_matrix_int8_execution.sv) and its SystemVerilog testbench implement the same functional INT8 arithmetic boundary. Until the exact revision passes the RTL simulation gate, the machine-readable architecture file records simulation evidence separately from implementation status.

The executable model is an architecture reference. It is not matrix RTL, timing closure, area estimation, power characterization, or measured hardware performance.

## Remaining implementation work

The next implementation boundary is matrix RTL and feasibility closure:

- implement the physical VGPR storage/macros behind the validated eight bank classes and two-read/one-write logical schedule;
- implement the fixed lane/register-offset routing from whole-wave reads into the 2,048-byte engine-local staging structures;
- complete FP16/BF16/FP8 arithmetic datapaths with the frozen FP32-FMA semantics; the signed INT8 arithmetic boundary is implemented functionally;
- integrate the implemented input/active and output-result staging with the arithmetic datapath; connect the validated per-wave VGPR scoreboard to real ordinary vector issue and resident-wave identity/arbitration;
- verify exact instruction behavior against the executable reference;
- synthesize the matrix engine on the selected process assumptions;
- measure timing, area, and power against the compute-unit budget;
- revise the architectural timing target if physical evidence shows it cannot close;
- add compiler lowering and API capability exposure;
- build matrix conformance workloads;
- validate fabricated silicon before reporting measured performance.

See [Public Sources](SOURCES.md) for IEEE 754, BF16, OCP FP8, OCP MX, Vulkan cooperative matrix, and public wave-matrix references.
