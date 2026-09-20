# CGX 1 Graphics Pipeline

[Documentation index](README.md) · [ISA and execution model](ISA.md) · [Texture and compression](TEXTURE_COMPRESSION.md) · [Chiplet fabric](CHIPLET_FABRIC.md)

CGX 1 presents **one logical GPU**. The four compute tiles are not exposed as AFR or four independent adapters.

## Work flow

```text
command queues
    |
global command/queue manager
    |
task / mesh / legacy geometry work on compute units
    |
primitive setup and screen-space binning
    |
dynamic 32 x 32 pixel macro-tile ownership
    |
tile-local rasterization
    |
fragment shading / texture
    |
depth-stencil / color back end
    |
lossless surface compression
    |
tile L2 -> package cache -> HBM4
```

Legacy vertex, tessellation, and geometry stages lower into the same programmable execution model used by mesh/task paths. Mesh/task shading is a first-class target.

## Tile organization

Each of four compute tiles contains:

- 50 compute units;
- 25 texture blocks;
- 4 raster partitions;
- 64 aggregate color/depth result lanes;
- a 16 MB tile L2 slice.

Tile-L2 capacity is intentionally not frozen yet. Device totals are therefore:

- 200 compute units;
- 100 texture blocks;
- 16 raster partitions;
- 256 color/depth result lanes;

A result lane is an architectural back-end lane, not a frame-rate claim. Actual rate depends on format, blending, depth/stencil state, compression, samples, cache behavior and memory traffic.

## Screen-space ownership

Raster work is divided into **32 x 32 pixel macro-tiles**. A macro-tile is owned by one compute tile while its color/depth updates are active. Ownership may be assigned dynamically to balance load.

Primitives that overlap more than one macro-tile are binned to each required owner. Final color/depth blending for an owned macro-tile remains local to the owning tile until the result is written through L2.

This avoids treating the device as four separately rendered frame regions and reduces cross-tile read/modify/write traffic for render targets.

## Raster and depth path

The raster target includes:

- triangle and line setup;
- hierarchical Z/stencil rejection;
- early and late depth/stencil operation;
- sample coverage and centroid/sample interpolation;
- 1x, 2x, 4x and 8x MSAA targets;
- programmable fragment shading-rate state;
- ordered color blending within a render target ownership region.

Raster partitions may feed any local compute-unit group through the tile scheduler. The final physical partition-to-CU wiring remains a layout decision.

## Cross-tile resources

Read-mostly resources may be cached by multiple tiles. Writable resources use the package coherence directory and normal memory ordering rules.

Render-target ownership is a performance policy, not an isolation boundary. Storage images, atomics, queues and general compute data remain globally addressable.

## Presentation

Display engines remain on the central I/O die. Completed scanout surfaces become visible to display only after required device-scope ordering is complete.

The graphics pipeline is designed so display timing does not depend on one specific compute tile remaining active.
