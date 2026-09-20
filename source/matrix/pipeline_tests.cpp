// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_matrix_pipeline.hpp"

#include <array>
#include <cassert>
#include <cstdint>
#include <stdexcept>

int main()
{
    using namespace cgx1::matrix;

    static_assert(kWaveRegisterBits == 1024U);
    static_assert(kWaveRegisterBytes == 128U);
    static_assert(kMatrixAStageBytes == 512U);
    static_assert(kMatrixBStageBytes == 512U);
    static_assert(kMatrixAccumulatorStageBytes == 1024U);
    static_assert(kMatrixInputStageBytes == 2048U);

    static_assert(kMatrixCaptureWaveReadPorts == 2U);
    static_assert(kMatrixWritebackWaveWritePorts == 1U);
    static_assert(!kMatrixSimultaneousReadWriteRequired);
    static_assert(MatrixRegisterFileReadBitsPerCaptureCycle() == 2048U);
    static_assert(MatrixRegisterFileWriteBitsPerWritebackCycle() == 1024U);

    static_assert(MatrixStageAtAge(0U) == MatrixPipelineStage::Decode);
    static_assert(MatrixStageAtAge(1U) == MatrixPipelineStage::Capture);
    static_assert(MatrixStageAtAge(8U) == MatrixPipelineStage::Capture);
    static_assert(MatrixStageAtAge(9U) == MatrixPipelineStage::Execute);
    static_assert(MatrixStageAtAge(24U) == MatrixPipelineStage::Execute);
    static_assert(MatrixStageAtAge(25U) == MatrixPipelineStage::Writeback);
    static_assert(MatrixStageAtAge(32U) == MatrixPipelineStage::Writeback);
    static_assert(MatrixStageAtAge(33U) == MatrixPipelineStage::Complete);

    static_assert(MatrixSourceCapturePending(0U));
    static_assert(MatrixSourceCapturePending(8U));
    static_assert(!MatrixSourceCapturePending(9U));
    static_assert(MatrixDestinationPending(0U));
    static_assert(MatrixDestinationPending(32U));
    static_assert(!MatrixDestinationPending(33U));

    static_assert(MatrixRegisterRangesOverlap(32U, 8U, 32U, 8U));
    static_assert(MatrixRegisterRangesOverlap(32U, 8U, 39U, 1U));
    static_assert(!MatrixRegisterRangesOverlap(32U, 8U, 40U, 1U));

    // RAW through source A.
    static_assert(MatrixDependsOnPendingDestination(48U, 32U, 84U, 32U));
    // RAW through source B.
    static_assert(MatrixDependsOnPendingDestination(48U, 80U, 36U, 32U));
    // WAW and tied C/D dependency.
    static_assert(MatrixDependsOnPendingDestination(32U, 80U, 84U, 32U));
    // Independent register groups.
    static_assert(!MatrixDependsOnPendingDestination(48U, 80U, 84U, 32U));

    static_assert(kMatrixIssueIntervalCycles > kMatrixRegisterCaptureCycles);

    for (std::uint32_t oldD = 0U; oldD <= 248U; oldD += 8U)
    {
        for (std::uint32_t newD = 0U; newD <= 248U; newD += 8U)
        {
            for (std::uint32_t newA = 0U; newA <= 248U; newA += 8U)
            {
                for (std::uint32_t newB = 4U; newB <= 252U; newB += 8U)
                {
                    if (!IsValidMatrixRegisterLayout(
                            static_cast<std::uint8_t>(newD),
                            static_cast<std::uint8_t>(newA),
                            static_cast<std::uint8_t>(newB)))
                    {
                        continue;
                    }

                    bool expected = false;
                    for (std::uint32_t offset = 0U;
                         offset < kMatrixSourceRegistersPerLane;
                         ++offset)
                    {
                        const std::uint32_t aRegister = newA + offset;
                        const std::uint32_t bRegister = newB + offset;
                        expected = expected
                            || (aRegister >= oldD
                                && aRegister < oldD + kMatrixAccumulatorRegistersPerLane)
                            || (bRegister >= oldD
                                && bRegister < oldD + kMatrixAccumulatorRegistersPerLane);
                    }
                    for (std::uint32_t offset = 0U;
                         offset < kMatrixAccumulatorRegistersPerLane;
                         ++offset)
                    {
                        const std::uint32_t dRegister = newD + offset;
                        expected = expected
                            || (dRegister >= oldD
                                && dRegister < oldD + kMatrixAccumulatorRegistersPerLane);
                    }

                    assert(MatrixDependsOnPendingDestination(
                        static_cast<std::uint8_t>(newD),
                        static_cast<std::uint8_t>(newA),
                        static_cast<std::uint8_t>(newB),
                        static_cast<std::uint8_t>(oldD)) == expected);
                }
            }
        }
    }

    constexpr std::uint8_t dBase = 32U;
    constexpr std::uint8_t aBase = 64U;
    constexpr std::uint8_t bBase = 68U;

    std::array<bool, kMatrixSourceRegistersPerLane> seenA{};
    std::array<bool, kMatrixSourceRegistersPerLane> seenB{};
    std::array<bool, kMatrixAccumulatorRegistersPerLane> seenC{};

    for (std::uint32_t cycle = 0U; cycle < kMatrixRegisterCaptureCycles; ++cycle)
    {
        const MatrixCaptureCycle schedule =
            MatrixCaptureSchedule(cycle, aBase, bBase, dBase);

        const std::array reads{schedule.read0, schedule.read1};
        for (const MatrixCaptureRead read : reads)
        {
            switch (read.fragment)
            {
                case MatrixCaptureFragment::A:
                    assert(read.registerOffset < seenA.size());
                    assert(!seenA[read.registerOffset]);
                    seenA[read.registerOffset] = true;
                    assert(read.architecturalRegister
                        == static_cast<std::uint8_t>(aBase + read.registerOffset));
                    break;
                case MatrixCaptureFragment::B:
                    assert(read.registerOffset < seenB.size());
                    assert(!seenB[read.registerOffset]);
                    seenB[read.registerOffset] = true;
                    assert(read.architecturalRegister
                        == static_cast<std::uint8_t>(bBase + read.registerOffset));
                    break;
                case MatrixCaptureFragment::Accumulator:
                    assert(read.registerOffset < seenC.size());
                    assert(!seenC[read.registerOffset]);
                    seenC[read.registerOffset] = true;
                    assert(read.architecturalRegister
                        == static_cast<std::uint8_t>(dBase + read.registerOffset));
                    break;
            }
        }
    }

    for (bool value : seenA) { assert(value); }
    for (bool value : seenB) { assert(value); }
    for (bool value : seenC) { assert(value); }

    for (std::uint32_t cycle = 0U; cycle < kMatrixWritebackCycles; ++cycle)
    {
        assert(MatrixWritebackRegister(cycle, dBase)
            == static_cast<std::uint8_t>(dBase + cycle));
    }

    for (std::uint32_t i = 0U; i < 32U; ++i)
    {
        assert(MatrixIssueCycle(i) == i * 16U);
    }

    static_assert(MatrixSteadyStatePortBudgetHolds(1U));
    static_assert(MatrixSteadyStatePortBudgetHolds(2U));
    static_assert(MatrixSteadyStatePortBudgetHolds(64U));

    for (std::uint32_t cycle = 0U; cycle < 160U; ++cycle)
    {
        const MatrixPortDemand demand = MatrixCombinedPortDemand(cycle, 10U);
        assert(demand.waveReads <= 2U);
        assert(demand.waveWrites <= 1U);
        assert(!(demand.waveReads != 0U && demand.waveWrites != 0U));
    }

    // A and B may alias. One physical read may be broadcast as an implementation
    // optimization, but the architectural schedule remains valid with two logical reads.
    for (std::uint32_t cycle = 0U; cycle < 4U; ++cycle)
    {
        const MatrixCaptureCycle aliased =
            MatrixCaptureSchedule(cycle, 64U, 64U, 32U);
        assert(aliased.read0.architecturalRegister
            == aliased.read1.architecturalRegister);
    }

    bool rejectedCaptureCycle = false;
    try
    {
        (void)MatrixCaptureSchedule(8U, aBase, bBase, dBase);
    }
    catch (const std::invalid_argument&)
    {
        rejectedCaptureCycle = true;
    }
    assert(rejectedCaptureCycle);

    bool rejectedLayout = false;
    try
    {
        (void)MatrixCaptureSchedule(0U, 65U, bBase, dBase);
    }
    catch (const std::invalid_argument&)
    {
        rejectedLayout = true;
    }
    assert(rejectedLayout);

    bool rejectedWriteback = false;
    try
    {
        (void)MatrixWritebackRegister(8U, dBase);
    }
    catch (const std::invalid_argument&)
    {
        rejectedWriteback = true;
    }
    assert(rejectedWriteback);

    return 0;
}
