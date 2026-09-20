// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "cgx1_matrix_architecture.hpp"

#include <array>
#include <cstdint>
#include <stdexcept>

namespace cgx1::matrix {

inline constexpr std::uint32_t kWaveRegisterWordBits = 32U;
inline constexpr std::uint32_t kWaveRegisterBits =
    kNativeWaveSize * kWaveRegisterWordBits;
inline constexpr std::uint32_t kWaveRegisterBytes =
    kWaveRegisterBits / 8U;

inline constexpr std::uint32_t kMatrixAStageBytes = 512U;
inline constexpr std::uint32_t kMatrixBStageBytes = 512U;
inline constexpr std::uint32_t kMatrixAccumulatorStageBytes = 1024U;
inline constexpr std::uint32_t kMatrixInputStageBytes =
    kMatrixAStageBytes + kMatrixBStageBytes + kMatrixAccumulatorStageBytes;

inline constexpr std::uint32_t kMatrixCaptureWaveReadPorts = kMatrixWaveRegisterReadsPerCaptureCycle;
inline constexpr std::uint32_t kMatrixWritebackWaveWritePorts = kMatrixWaveRegisterWritesPerWritebackCycle;
inline constexpr bool kMatrixSimultaneousReadWriteRequired = false;

enum class MatrixPipelineStage : std::uint8_t
{
    Decode = 0,
    Capture,
    Execute,
    Writeback,
    Complete
};

enum class MatrixCaptureFragment : std::uint8_t
{
    A = 0,
    B,
    Accumulator
};

struct MatrixCaptureRead
{
    MatrixCaptureFragment fragment;
    std::uint8_t registerOffset;
    std::uint8_t architecturalRegister;
};

struct MatrixCaptureCycle
{
    MatrixCaptureRead read0;
    MatrixCaptureRead read1;
};

struct MatrixPortDemand
{
    std::uint8_t waveReads;
    std::uint8_t waveWrites;
};

inline constexpr MatrixPipelineStage MatrixStageAtAge(std::uint32_t age)
{
    if (age == 0U)
    {
        return MatrixPipelineStage::Decode;
    }
    if (age <= kMatrixRegisterCaptureCycles)
    {
        return MatrixPipelineStage::Capture;
    }
    if (age <= kMatrixRegisterCaptureCycles + kMatrixExecutionCycles)
    {
        return MatrixPipelineStage::Execute;
    }
    if (age < kMatrixResultLatencyCycles)
    {
        return MatrixPipelineStage::Writeback;
    }
    return MatrixPipelineStage::Complete;
}

inline constexpr MatrixPortDemand MatrixPortDemandAtAge(std::uint32_t age)
{
    switch (MatrixStageAtAge(age))
    {
        case MatrixPipelineStage::Capture:
            return MatrixPortDemand{
                static_cast<std::uint8_t>(kMatrixCaptureWaveReadPorts), 0U};
        case MatrixPipelineStage::Writeback:
            return MatrixPortDemand{
                0U, static_cast<std::uint8_t>(kMatrixWritebackWaveWritePorts)};
        default:
            return MatrixPortDemand{0U, 0U};
    }
}

inline constexpr bool MatrixSourceCapturePending(std::uint32_t age)
{
    return age <= kMatrixRegisterCaptureCycles;
}

inline constexpr bool MatrixDestinationPending(std::uint32_t age)
{
    return age < kMatrixResultLatencyCycles;
}

inline constexpr bool MatrixRegisterRangesOverlap(
    std::uint8_t leftBase,
    std::uint32_t leftCount,
    std::uint8_t rightBase,
    std::uint32_t rightCount)
{
    const std::uint32_t leftStart = leftBase;
    const std::uint32_t rightStart = rightBase;
    const std::uint32_t leftEnd = leftStart + leftCount;
    const std::uint32_t rightEnd = rightStart + rightCount;

    return leftStart < rightEnd && rightStart < leftEnd;
}

inline constexpr bool MatrixDependsOnPendingDestination(
    std::uint8_t newDestinationBase,
    std::uint8_t newSourceABase,
    std::uint8_t newSourceBBase,
    std::uint8_t olderDestinationBase)
{
    return MatrixRegisterRangesOverlap(
               newSourceABase,
               kMatrixSourceRegistersPerLane,
               olderDestinationBase,
               kMatrixAccumulatorRegistersPerLane)
        || MatrixRegisterRangesOverlap(
               newSourceBBase,
               kMatrixSourceRegistersPerLane,
               olderDestinationBase,
               kMatrixAccumulatorRegistersPerLane)
        || MatrixRegisterRangesOverlap(
               newDestinationBase,
               kMatrixAccumulatorRegistersPerLane,
               olderDestinationBase,
               kMatrixAccumulatorRegistersPerLane);
}

inline constexpr MatrixCaptureCycle MatrixCaptureSchedule(
    std::uint32_t captureCycle,
    std::uint8_t sourceABase,
    std::uint8_t sourceBBase,
    std::uint8_t accumulatorBase)
{
    if (captureCycle >= kMatrixRegisterCaptureCycles)
    {
        throw std::invalid_argument("matrix capture cycle is out of range");
    }
    if (!IsValidMatrixRegisterLayout(accumulatorBase, sourceABase, sourceBBase))
    {
        throw std::invalid_argument("matrix register layout is invalid");
    }

    if (captureCycle < kMatrixSourceRegistersPerLane)
    {
        const auto offset = static_cast<std::uint8_t>(captureCycle);
        return MatrixCaptureCycle{
            MatrixCaptureRead{
                MatrixCaptureFragment::A,
                offset,
                static_cast<std::uint8_t>(sourceABase + offset)},
            MatrixCaptureRead{
                MatrixCaptureFragment::B,
                offset,
                static_cast<std::uint8_t>(sourceBBase + offset)}
        };
    }

    const std::uint8_t accumulatorPair =
        static_cast<std::uint8_t>((captureCycle - kMatrixSourceRegistersPerLane) * 2U);
    return MatrixCaptureCycle{
        MatrixCaptureRead{
            MatrixCaptureFragment::Accumulator,
            accumulatorPair,
            static_cast<std::uint8_t>(accumulatorBase + accumulatorPair)},
        MatrixCaptureRead{
            MatrixCaptureFragment::Accumulator,
            static_cast<std::uint8_t>(accumulatorPair + 1U),
            static_cast<std::uint8_t>(accumulatorBase + accumulatorPair + 1U)}
    };
}

inline constexpr std::uint8_t MatrixWritebackRegister(
    std::uint32_t writebackCycle,
    std::uint8_t destinationBase)
{
    if (writebackCycle >= kMatrixWritebackCycles)
    {
        throw std::invalid_argument("matrix writeback cycle is out of range");
    }
    if ((destinationBase % kMatrixAccumulatorRegistersPerLane) != 0U
        || static_cast<std::uint32_t>(destinationBase)
            + kMatrixAccumulatorRegistersPerLane > 256U)
    {
        throw std::invalid_argument("matrix destination register group is invalid");
    }

    return static_cast<std::uint8_t>(destinationBase + writebackCycle);
}

inline constexpr std::uint32_t MatrixIssueCycle(std::uint32_t sequenceIndex)
{
    return sequenceIndex * kMatrixIssueIntervalCycles;
}

inline constexpr MatrixPortDemand MatrixCombinedPortDemand(
    std::uint32_t globalCycle,
    std::uint32_t issuedOperations)
{
    std::uint32_t reads = 0U;
    std::uint32_t writes = 0U;

    for (std::uint32_t index = 0U; index < issuedOperations; ++index)
    {
        const std::uint32_t issueCycle = MatrixIssueCycle(index);
        if (globalCycle < issueCycle)
        {
            continue;
        }

        const MatrixPortDemand demand =
            MatrixPortDemandAtAge(globalCycle - issueCycle);
        reads += demand.waveReads;
        writes += demand.waveWrites;
    }

    return MatrixPortDemand{
        static_cast<std::uint8_t>(reads),
        static_cast<std::uint8_t>(writes)
    };
}

inline constexpr bool MatrixSteadyStatePortBudgetHolds(
    std::uint32_t issuedOperations)
{
    if (issuedOperations == 0U)
    {
        return true;
    }

    const std::uint32_t finalCycle =
        MatrixIssueCycle(issuedOperations - 1U) + kMatrixResultLatencyCycles;

    for (std::uint32_t cycle = 0U; cycle <= finalCycle; ++cycle)
    {
        const MatrixPortDemand demand =
            MatrixCombinedPortDemand(cycle, issuedOperations);

        if (demand.waveReads > kMatrixCaptureWaveReadPorts
            || demand.waveWrites > kMatrixWritebackWaveWritePorts)
        {
            return false;
        }

        if (!kMatrixSimultaneousReadWriteRequired
            && demand.waveReads != 0U
            && demand.waveWrites != 0U)
        {
            return false;
        }
    }

    return true;
}

inline constexpr std::uint32_t MatrixRegisterFileReadBitsPerCaptureCycle()
{
    return kMatrixCaptureWaveReadPorts * kWaveRegisterBits;
}

inline constexpr std::uint32_t MatrixRegisterFileWriteBitsPerWritebackCycle()
{
    return kMatrixWritebackWaveWritePorts * kWaveRegisterBits;
}

} // namespace cgx1::matrix
