# CGX 1 Matrix Engine Precision and Semantics

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [ISA](ISA.md) · [Software stack](SOFTWARE_STACK.md) · [Validation](VALIDATION.md)

This document defines the numeric contract for the dedicated matrix engines targeted by CGX 1. It does not claim implemented matrix RTL, a physical matrix tile shape, an issue rate, an AI TOPS figure, or measured silicon performance.

## Architecture boundary

Each compute unit retains the existing target of **four matrix engines**. Matrix work is cooperative across one native **wave32** subgroup. Matrix fragments are distributed across participating lanes, but the physical fragment to lane mapping is implementation defined and software must not depend on it.

The logical operation is a cooperative matrix multiply add:

`D = A × B + C`

The driver and compiler expose only matrix type and dimension combinations reported as supported by the implementation. Physical `M`, `N`, and `K` tile dimensions are not frozen in this architecture revision. This follows the same capability discovery model used by Vulkan cooperative matrices, where supported component types and dimensions are queried from the device.

## Baseline precision profiles

The initial CGX 1 matrix target defines these numeric profiles:

| A operand | B operand | Accumulator | Result |
|---|---|---|---|
| IEEE binary16 (FP16) | IEEE binary16 (FP16) | FP32 | FP32 |
| BF16 | BF16 | FP32 | FP32 |
| OCP FP8 E4M3 | OCP FP8 E4M3 | FP32 | FP32 |
| OCP FP8 E4M3 | OCP FP8 E5M2 | FP32 | FP32 |
| OCP FP8 E5M2 | OCP FP8 E4M3 | FP32 | FP32 |
| OCP FP8 E5M2 | OCP FP8 E5M2 | FP32 | FP32 |
| signed INT8 | signed INT8 | signed INT32 | signed INT32 |

No implicit narrowing of the accumulator is permitted for these profiles. A lower precision output requires an explicit conversion after the matrix operation.

FP32 input matrix acceleration, FP64 matrix acceleration, TF32, OCP MX block scaled formats, unsigned or mixed sign integer profiles, and structured sparsity acceleration are not part of this baseline. They may be added only with explicit numeric, instruction, compiler, and validation contracts.

## FP16 and BF16

FP16 uses IEEE 754 binary16 representation and special value behavior.

BF16 uses one sign bit, eight exponent bits, and seven fraction bits. FP32 to BF16 conversion uses round to nearest, ties to even. BF16 retains FP32 style exponent range behavior, including infinities, NaNs, signed zero, and subnormal encodings. NaN payload preservation is not an architecture requirement.

FP16 and BF16 matrix products accumulate into FP32. Matrix floating point operations do not create synchronous traps for ordinary NaN, infinity, underflow, or overflow data values. Invalid instruction or unsupported profile use is still an architectural instruction fault.

## OCP FP8

CGX 1 uses the Open Compute Project OFP8 Revision 1.0 definitions rather than a vendor specific FP8 variant.

**E4M3** uses one sign bit, four exponent bits, and three fraction bits. Its maximum finite magnitude is **448**. It represents NaN but not infinity.

**E5M2** uses one sign bit, five exponent bits, and two fraction bits. Its maximum finite magnitude is **57,344**. It represents both infinity and NaN.

Both formats retain their defined subnormal range. Conversion from a wider floating point format must support round to nearest, ties to even and both OCP saturation modes:

| Conversion mode | E4M3 overflow or infinity input | E5M2 overflow or infinity input |
|---|---|---|
| Saturate | signed maximum finite | signed maximum finite |
| Non saturating | NaN | signed infinity |

NaN converts to an FP8 NaN. NaN payload and sign propagation are not guaranteed.

Software may request an explicit flush to zero mode where a later ISA revision defines it. CGX 1 must not silently apply a device wide flush to zero policy to matrix inputs.

## Floating point accumulation

FP16, BF16, and FP8 matrix profiles use an FP32 accumulator and FP32 result. Every finite FP16, BF16, E4M3, and E5M2 operand value is exactly representable in FP32, so operand widening to FP32 introduces no additional rounding. Each reference multiply add step uses FP32 fused multiply add semantics with one rounding of the product plus accumulator. Implementations may use wider internal precision only when the architecturally visible result remains within the conformance contract.

The product reduction order across `K` is not frozen. Parallel implementations may therefore differ in the least significant result bits for mathematically equivalent floating point operations. CGX 1 does not currently promise bitwise equivalence to a scalar left to right FP32 FMA loop or a deterministic matrix reduction mode.

The implementation must not silently reduce accumulator precision below FP32. A conformance tolerance for non exact floating point matrix reductions is frozen with the physical matrix datapath and instruction semantics, not inferred from this document.

## INT8 accumulation

The baseline integer matrix profile is signed INT8 multiplied into a signed INT32 accumulator and result.

Each INT8 product is exact in INT32. Accumulator overflow follows two's complement modulo `2^32` behavior. It does not saturate and does not trap. Saturating accumulation, unsigned INT8, and mixed signedness require separately advertised profiles if they are added.

## Capability discovery and software contract

A driver must report supported matrix tuples rather than exposing a generic matrix capability that accepts combinations the hardware cannot execute. A reported tuple includes at least:

* A component type;
* B component type;
* accumulator type;
* result type;
* cooperative scope;
* supported `M`, `N`, and `K` dimensions or granularities;
* supported layout and transpose rules;
* supported conversion and accumulation modifiers.

The native target scope is subgroup wave32. API lowering may map Vulkan cooperative matrix operations or another supported compute API onto these tuples only when the requested combination is reported as supported.

## Throughput accounting

No matrix throughput number is frozen in this phase.

When a physical matrix operation rate is eventually established, a dense matrix multiply add over dimensions `M × N × K` counts `2 × M × N × K` arithmetic operations: one multiply and one add per inner product term. Format conversion, loads, stores, scaling, and address work are not counted as matrix arithmetic operations.

CGX 1 does not apply a structured sparsity multiplier to headline throughput. No independent AI TOPS value is published until matrix RTL, instruction scheduling, clock behavior, compiler lowering, and measured silicon establish a defensible rate.

## MX formats

OCP MX is relevant to future lower precision work, but it is not a CGX 1 baseline capability today. MX adds shared block scale semantics and additional element formats. Claiming MX support therefore requires a defined scale storage and delivery path, block size contract, matrix instruction operands, compiler lowering, conversion rules, and executable validation.

The current design reserves that work rather than treating ordinary OCP FP8 support as proof of MX support.

## Executable reference

[`source/matrix/cgx1_matrix.hpp`](../source/matrix/cgx1_matrix.hpp) and its tests provide a software reference for the precision contract. The reference covers:

* supported and rejected matrix precision tuples;
* FP16, BF16, E4M3, and E5M2 format metadata;
* OCP FP8 decoding, special values, subnormals, round to nearest ties to even conversion, and saturating/non-saturating modes;
* exhaustive finite FP8 encode and decode round trips;
* BF16 round to nearest ties to even conversion;
* FP32 fused multiply add reference behavior;
* signed INT8 to INT32 accumulation and modulo overflow behavior.

This reference validates numeric semantics. It is not a cycle model, compiler, shader core, matrix RTL implementation, or matrix performance benchmark.

## Remaining implementation work

Before a matrix engine can be called implemented, the project still needs physical tile shapes, operand fragment mapping, register and instruction encoding, issue and dependency behavior, RTL, timing and area analysis, power characterization, compiler lowering, API capability exposure, conformance tests, and measured hardware results.

See [Public Sources](SOURCES.md) for IEEE 754, BF16, OCP FP8, OCP MX, and Vulkan cooperative matrix references.
