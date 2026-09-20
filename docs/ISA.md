# CGX 1 Instruction Set and Execution Model

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [Matrix engine precision](MATRIX_ENGINE.md) · [Virtual memory](VIRTUAL_MEMORY.md) · [Scheduling and preemption](SCHEDULING_PREEMPTION.md)

This document defines the first software-visible execution contract for CGX 1. It is an architecture target, not fabricated silicon behavior.

## Compute-unit organization

Each compute unit contains **four SIMD32 execution partitions**. Each partition operates on one native 32-lane wave, giving **128 FP32 lanes per compute unit** and preserving the existing 25,600-lane device target.

Native subgroup width is **32 lanes**. A 64-lane programming model may be implemented by pairing two native waves when an API or compiler requires it. Wave64 is therefore a compiler/runtime composition mode rather than a separate physical SIMD width.

A wave carries:

- a program counter;
- a 32-bit active-lane mask;
- scalar registers shared by the wave;
- vector registers addressed per lane;
- predicate/mask state;
- exception and memory-fault state.

## Register model

| Register class | Architectural count | Width/use |
|---|---:|---|
| Vector registers | 256 per thread | 32-bit elements; adjacent registers may form wider values |
| Scalar registers | 128 per wave | 32-bit values shared by all active lanes |
| Predicate registers | 16 per wave | masks and control predicates |
| Special registers | implementation defined set | PC, lane ID, wave ID, workgroup IDs, dispatch IDs, fault state |

The architectural register namespace does not require every register to be physically resident at the same time. The final implementation may bank, compress, rename, or spill state provided architectural behavior is preserved.

## Instruction encoding

CGX ISA v1 uses a **32-bit base instruction**. Instructions that require a larger immediate, additional modifiers, or extended operand metadata consume one following 32-bit extension word.

Base word:

```text
31          28 27          24 23          16 15           8 7            0
+--------------+--------------+--------------+--------------+--------------+
| class (4)    | opcode (4)   | destination  | source 0     | source 1     |
+--------------+--------------+--------------+--------------+--------------+
```

The three 8-bit operand fields can address the 256-entry vector namespace directly. Scalar formats validate the operand against the smaller scalar namespace. Control, branch, immediate, and memory formats reinterpret operand fields as specified by their instruction class.

The 4-bit opcode is a major opcode within its class. Class value 15 is reserved for encodings that need an expanded opcode space or other extended format. The base encoder rejects undefined classes and opcode values outside 0-15 rather than silently aliasing them. The public executable encoder/decoder in [`source/isa/cgx1_isa.hpp`](../source/isa/cgx1_isa.hpp) implements this base field contract.

## Instruction classes

| Class | Purpose |
|---|---|
| Scalar | Wave-uniform integer, floating-point, bit, compare, and address operations |
| Vector | Per-lane arithmetic, compare, select, permutation, and conversion |
| Memory | Global, local/shared, constant, image/texture address, load/store and prefetch |
| Control | Branch, call, return, mask manipulation, loop and termination |
| Sync/atomic | Barriers, fences, integer atomics and supported floating-point atomics |
| Texture | Sample, gather, query and filtered image access |
| Matrix | Cooperative wave32 matrix operations; tied C/D accumulator; opcodes 0x0-0x6 select the frozen baseline profiles and tile shapes |
| Ray | Traversal/intersection operations; detailed RT datapath remains future RTL work |
| Conversion | Pack, unpack and numeric format conversion |
| System | Queue, fault, debug, timing and privileged operations |

Unsupported or reserved opcode combinations raise an illegal-instruction fault; they must not execute as an undocumented alias.

## Divergence and reconvergence

Branches may change the active-lane mask. Divergent paths execute under masks and reconverge at compiler/runtime-defined reconvergence points.

Software must not assume inactive lanes make forward progress. Synchronization that requires all lanes must use subgroup or workgroup primitives rather than relying on branch timing.

## Memory model

The default ordering model is relaxed. Acquire, release, acquire-release, and sequentially consistent operations are available at these scopes:

- subgroup;
- workgroup;
- device;
- system.

The system scope is the only scope intended to order GPU accesses against coherent host-visible mappings.

Required integer atomics cover 32-bit and 64-bit compare/exchange, exchange, add/subtract, min/max and bitwise operations. FP32 atomic add is an architecture target. Additional floating-point atomics are added only when their exact numerical behavior is specified.

## Faults

Architectural faults include:

- illegal instruction;
- address/protection violation;
- replayable page fault;
- poisoned/ECC-failed data;
- watchdog or execution timeout.

A recoverable memory fault is reported to the queue/context that caused it. A queue fault must not require a whole-device reset unless lower reset levels fail.

## Numerical behavior

FP32 arithmetic follows IEEE 754 behavior where the selected operation and mode require it. Flush-to-zero and denormal handling are explicit instruction/compiler modes rather than silent device-wide behavior.

FP16, BF16, FP64 and packed integer formats may share execution hardware, but their final throughput ratios are not asserted by this document. Matrix numeric behavior, physical tile shapes, fragment mapping, opcode assignments, register grouping, issue interval, result latency, and theoretical dense rates are defined in [Matrix Engine Architecture](MATRIX_ENGINE.md). RTL timing, area, power, compiler integration, and measured hardware performance remain future validation work.
