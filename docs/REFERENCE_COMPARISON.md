# Reference GPU Comparison

[Documentation index](README.md) · [Engineering specification](ENGINEERING_SPEC.md) · [Public sources](SOURCES.md)

**Reference date:** September 20, 2026

CGX 1 has no fabricated silicon. CGX figures below are architecture targets and arithmetic values, not benchmark measurements.

## Primary workstation reference

The primary shipping reference is NVIDIA RTX PRO 6000 Blackwell Workstation Edition.

| Specification | CGX 1 target | NVIDIA RTX PRO 6000 Blackwell Workstation Edition | Notes |
|---|---:|---:|---|
| Status | Engineering design | Shipping product | CGX has no fabricated ASIC |
| FP32 | 143.36 TFLOPS target | 125 TFLOPS published product figure | See NVIDIA product datasheet |
| GPU memory | 72 GB HBM4 baseline | 96 GB GDDR7 ECC | Different memory technologies |
| Future capacity target | 96 GB HBM4 | 96 GB GDDR7 ECC | CGX future target depends on 48 GB HBM4 stacks |
| Peak memory bandwidth | 6.6 TB/s target | 1.792 TB/s | Peak interface figures |
| Board power | 360 W nominal target | 600 W | Application efficiency is not implied |
| Card length | 167.5 mm target | 304.8 mm | CGX excludes external dock size |
| Card height | 68.5 mm target | 137.2 mm | CGX low profile board target |
| Slot class | Dual slot target | Dual slot | RTX PRO is extended height |
| Media engines | 4 encode + 4 decode target | 4 NVENC + 4 NVDEC | CGX media block is not implemented |
| Independent AI throughput | Not frozen | 4,000 FP4 AI TOPS published | No CGX TOPS claim |
| Independent RT throughput | Not frozen | 380 RT TFLOPS published | No CGX RT TFLOPS claim |

Arithmetic based on the published 125 TFLOPS product figure:

- CGX FP32 target is approximately **14.7% higher**.
- CGX peak memory bandwidth target is approximately **3.68×** the published 1.792 TB/s figure.
- CGX nominal board power target is **40% lower**.
- Peak FP32/W arithmetic is approximately **1.91×** the product specification ratio.
- CGX card length target is approximately **45% shorter**.
- CGX card height target is approximately **50% lower**.
- The rectangular card length × height envelope is approximately **27.4%** of the workstation card face envelope.

Those ratios do not predict frame rate, renderer time, local model performance, media throughput, compiler quality, driver maturity, or application performance.

### NVIDIA source discrepancy

NVIDIA currently publishes two official arithmetic presentations for this product. The workstation **product datasheet** lists **125 TFLOPS FP32 and 380 RT TFLOPS**. NVIDIA's RTX Blackwell architecture document lists **126.0 TFLOPS FP32 and 381.8 RT TFLOPS** for the same workstation configuration.

This repository uses the product datasheet figures in the comparison table so the baseline matches NVIDIA's product specification. Both official references are linked in [Public Sources](SOURCES.md).

## Secondary gaming reference

NVIDIA GeForce RTX 5090 remains a gaming reference. NVIDIA publishes:

- 21,760 CUDA cores;
- 32 GB GDDR7;
- 575 W total graphics power;
- 304 × 137 × 61 mm Founders Edition dimensions;
- approximately 104.8 TFLOPS peak FP32 in the RTX Blackwell architecture document.

The CGX target has more baseline memory, a higher peak memory bandwidth target, a lower nominal board power target, and a smaller card envelope. Actual gaming performance is unknown until a complete CGX graphics implementation, driver stack, and physical device exist.

## Software matters

Arithmetic throughput is only one part of GPU performance. A competitive implementation also requires compiler optimization, graphics APIs, shader compilation, scheduling, memory management, application compatibility, driver recovery, conformance, and workload specific tuning.

The implementation plan is documented in [Software Stack](SOFTWARE_STACK.md).
