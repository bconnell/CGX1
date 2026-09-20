# Texture and Lossless Surface Compression

[Documentation index](README.md) · [Graphics pipeline](GRAPHICS_PIPELINE.md) · [Engineering specification](ENGINEERING_SPEC.md)

## Texture subsystem

CGX 1 targets **25 texture blocks per compute tile**, or **100 blocks total**. One block is shared by two compute units.

Each texture block targets four bilinear sample results per cycle under a simple cache-resident case. At the 2.80 GHz peak clock, the arithmetic ceiling is:

```text
100 blocks x 4 bilinear samples/cycle x 2.80 GHz
= 1,120 Gsamples/s
```

That number is a sampler arithmetic target. It is not a guaranteed texture rate and does not predict frame rate.

## Filtering

Target filtering modes:

- point;
- bilinear;
- trilinear;
- anisotropic filtering through 16x;
- gather;
- explicit LOD and gradients;
- normalized and unnormalized coordinates where the API requires them.

Format decode targets include BC1-BC7, ETC2/EAC and ASTC LDR. Final API conformance determines the complete required format table.

Each texture block uses a read-only sampler cache backed by the tile L2. Sampler-cache capacity and associativity are physical-design parameters and are not frozen yet; the tile-L2 target is 16 MB per compute tile.

## Lossless surface compression

CGX uses a lossless surface-compression layer between tile L2 and the package cache/HBM path.

Compression is defined in **256-byte surface blocks**. Color blocks may be stored as:

- raw/uncompressed;
- constant-color;
- lossless delta-coded data.

Depth/stencil surfaces have a separate lossless representation suited to hierarchical Z/stencil state.

Fast clears may be represented as metadata without immediately writing every pixel value.

## Correctness rules

Compression must be invisible to shaders, host software and display/media consumers.

There is **no guaranteed compression ratio**. A block that cannot be represented profitably or safely is stored raw.

Operations whose atomicity or byte-addressability is incompatible with a compressed representation force the affected block to a correctness-preserving raw state before the operation completes.

Compression metadata participates in cache coherence. A consumer may not observe stale metadata paired with newer surface data or the reverse.

## Why compression is part of the architecture

HBM4 bandwidth is large but not free. Avoiding unnecessary HBM transfers reduces energy, package-fabric pressure and contention between graphics, compute, media and display traffic.

The purpose of compression is therefore bandwidth and power efficiency, not a headline multiplier.
