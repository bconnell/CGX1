// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "model.hpp"

#include <cassert>
#include <cmath>
#include <iostream>
#include <stdexcept>

int main()
{
    using namespace cgx1;

    const CardGeometry card{167.5, 68.5, 39.5};
    assert(FitsTargetEnvelope(card));
    assert(!FitsTargetEnvelope(CardGeometry{167.6, 68.5, 39.5}));

    const double fp32 = Fp32PeakTflops(25600.0, 2.80);
    assert(std::abs(fp32 - 143.36) < 0.001);

    const double rise = CoolantRiseC(360.0, 1.5);
    assert(rise > 3.3 && rise < 3.6);

    const ThermalInputs thermal{360.0, 1.5, 35.0, 0.085, 0.040};
    const double junction = EstimatedJunctionC(thermal);
    assert(junction > 81.0 && junction < 82.5);
    assert(junction < 85.0);

    const double fp32PerWatt = PeakFp32PerWatt(143.36, 360.0);
    assert(fp32PerWatt > 0.398 && fp32PerWatt < 0.399);

    static_assert(kSimdPartitionsPerCu * kLanesPerSimdPartition == 128);
    static_assert(kNativeWaveSize == 32);
    static_assert(kTextureBlocksPerTile * kComputeTiles == kTextureBlocksTotal);
    static_assert(kResidentHardwareQueueContexts == 64);
    static_assert(kSchedulerPriorityLevels == 8);
    static_assert(kPreferredVramPageBytes == 65536);

    const double texturePeak = TexturePeakGtex(
        kTextureBlocksTotal,
        kBilinearSamplesPerTextureBlockPerCycle,
        kTargetPeakClockGhz);
    assert(std::abs(texturePeak - 1120.0) < 0.001);

    assert(TotalRasterPartitions(kComputeTiles, kRasterPartitionsPerTile) == 16);
    assert(TotalRopLanes(kComputeTiles, kRopLanesPerTile) == 256);

    const double fabricHeadroom = FabricReadHeadroom(kFabricAggregateReadTbps, kTargetMemoryTbps);
    assert(fabricHeadroom > 1.09 && fabricHeadroom < 1.10);

    bool rejectedZeroFlow = false;
    try
    {
        (void)CoolantRiseC(360.0, 0.0);
    }
    catch (const std::invalid_argument&)
    {
        rejectedZeroFlow = true;
    }
    assert(rejectedZeroFlow);

    bool rejectedZeroPower = false;
    try
    {
        (void)PeakFp32PerWatt(143.36, 0.0);
    }
    catch (const std::invalid_argument&)
    {
        rejectedZeroPower = true;
    }
    assert(rejectedZeroPower);

    std::cout << "CGX 1 analytical model checks passed.\n";
    return 0;
}
