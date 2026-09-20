# Roadmap

[Documentation index](README.md) · [Project status](STATUS.md) · [Prototype build](PROTOTYPE_BUILD.md)

## Current design package

- architecture specification and machine readable target file;
- revised card and thermal dock envelopes;
- selected prototype fan, radiator, and pump/reservoir references;
- analytical thermal, power, fit, and FP32 model;
- reference power state firmware;
- top level RTL state scaffold;
- prototype procurement and cost planning;
- software implementation plan;
- validation and repository integrity checks.

## P0 manufacturing package

- dimensioned heater locations matching planned package heat regions;
- copper spreader and cold plate machining drawing;
- rear power and coolant connector drawing;
- low profile and full height bracket drawings;
- detailed dock internal arrangement and hose/fitting clearance;
- 48 V low voltage harness drawing;
- control PCB schematic;
- control PCB layout, drill files, and manufacturing outputs;
- instrumented 360 W thermal procedure.

## P0 physical validation

- fabricate card carrier and revised dock;
- validate selected 50 mm fan fit;
- validate radiator, radiator fans, and pump/reservoir packing;
- validate actual loop flow;
- validate coolant rise and component temperatures;
- validate connector heating and 48 V delivery;
- validate P3/P4 dock loss fallback to P0;
- measure card and dock dimensions;
- revise mechanical and thermal targets from measured results.

## P1 programmable bench

- integrate one shared HBM programmable accelerator;
- prototype command, telemetry, memory movement, and selected RTL blocks;
- establish reproducible host software tests;
- keep surrogate results labeled as surrogate measurements.

## Custom silicon

- define ISA and shader execution model;
- complete compute, raster, ray, cache, fabric, memory, display, media, security, and debug RTL;
- complete verification and FPGA/emulation work;
- select licensed PHY and codec IP;
- complete physical design and package engineering;
- fabricate validation silicon;
- develop Linux and Windows drivers;
- complete graphics, compute, media, and application conformance;
- characterize production silicon and publish measured performance separately from design targets.
