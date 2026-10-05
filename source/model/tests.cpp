// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_check.h"
#include "model.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>

int main()
{
    using namespace cgx1;

    const CardGeometry card{167.5, 68.5, 39.5};
    CGX1_TEST_CHECK(FitsTargetEnvelope(card));
    CGX1_TEST_CHECK(!FitsTargetEnvelope(CardGeometry{167.6, 68.5, 39.5}));

    const double fp32 = Fp32PeakTflops(25600.0, 2.80);
    CGX1_TEST_CHECK(std::abs(fp32 - 143.36) < 0.001);

    const double rise = CoolantRiseC(360.0, 1.5);
    CGX1_TEST_CHECK(rise > 3.3 && rise < 3.6);

    const ThermalInputs thermal{360.0, 1.5, 35.0, 0.085, 0.040};
    const double junction = EstimatedJunctionC(thermal);
    CGX1_TEST_CHECK(junction > 81.0 && junction < 82.5);
    CGX1_TEST_CHECK(junction < 85.0);

    const double fp32PerWatt = PeakFp32PerWatt(143.36, 360.0);
    CGX1_TEST_CHECK(fp32PerWatt > 0.398 && fp32PerWatt < 0.399);

    static_assert(kSimdPartitionsPerCu * kLanesPerSimdPartition == 128);
    static_assert(kNativeWaveSize == 32);
    static_assert(kTextureBlocksPerTile * kComputeTiles == kTextureBlocksTotal);
    static_assert(kResidentHardwareQueueContexts == 64);
    static_assert(kSchedulerPriorityLevels == 8);
    static_assert(kPreferredVramPageBytes == 65536);
    static_assert(kL1SharedKbPerComputeUnit == 128);
    static_assert(kL2MbPerTile * kComputeTiles == kL2TotalMb);
    static_assert(kPackageCacheMb == 512);

    const double texturePeak = TexturePeakGtex(
        kTextureBlocksTotal,
        kBilinearSamplesPerTextureBlockPerCycle,
        kTargetPeakClockGhz);
    CGX1_TEST_CHECK(std::abs(texturePeak - 1120.0) < 0.001);

    CGX1_TEST_CHECK(TotalRasterPartitions(kComputeTiles, kRasterPartitionsPerTile) == 16);
    CGX1_TEST_CHECK(TotalRopLanes(kComputeTiles, kRopLanesPerTile) == 256);

    const double fabricHeadroom = FabricReadHeadroom(kFabricAggregateReadTbps, kTargetMemoryTbps);
    CGX1_TEST_CHECK(fabricHeadroom > 1.09 && fabricHeadroom < 1.10);

    bool rejectedZeroFlow = false;
    try
    {
        (void)CoolantRiseC(360.0, 0.0);
    }
    catch (const std::invalid_argument&)
    {
        rejectedZeroFlow = true;
    }
    CGX1_TEST_CHECK(rejectedZeroFlow);

    bool rejectedZeroPower = false;
    try
    {
        (void)PeakFp32PerWatt(143.36, 0.0);
    }
    catch (const std::invalid_argument&)
    {
        rejectedZeroPower = true;
    }
    CGX1_TEST_CHECK(rejectedZeroPower);

    std::cout << "CGX 1 analytical model checks passed.\n";
    return 0;
}
