// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "cgx1_matrix_pipeline.hpp"

#include <array>
#include <cstdint>
#include <stdexcept>

namespace cgx1::matrix {

using MatrixWaveRegister =
    std::array<std::uint32_t, kNativeWaveSize>;

struct MatrixOperandSet
{
    std::array<MatrixWaveRegister, kMatrixSourceRegistersPerLane> a{};
    std::array<MatrixWaveRegister, kMatrixSourceRegistersPerLane> b{};
    std::array<MatrixWaveRegister, kMatrixAccumulatorRegistersPerLane> c{};
};

struct MatrixOperandStagingState
{
    MatrixOperandSet capture{};
    MatrixOperandSet active{};
    std::uint8_t expectedCaptureCycle = 0U;
    bool activeValid = false;
    std::uint64_t activeGeneration = 0U;
};

inline constexpr std::uint32_t kMatrixActiveExecutionOperandBytes =
    kMatrixInputStageBytes;
inline constexpr std::uint32_t kMatrixOutputStageBytes =
    kMatrixFragmentWriteBytesPerWave;
inline constexpr std::uint32_t kMatrixLogicalPipelineStorageBytesPerEngine =
    kMatrixInputStageBytes
    + kMatrixActiveExecutionOperandBytes
    + kMatrixOutputStageBytes;
inline constexpr std::uint32_t kMatrixLogicalPipelineStorageBytesPerComputeUnit =
    kMatrixLogicalPipelineStorageBytesPerEngine
    * kMatrixEnginesPerComputeUnit;

inline bool CaptureMatrixOperandCycle(
    MatrixOperandStagingState& state,
    std::uint32_t captureCycle,
    const MatrixWaveRegister& read0,
    const MatrixWaveRegister& read1)
{
    if (captureCycle >= kMatrixRegisterCaptureCycles)
    {
        throw std::invalid_argument("matrix capture cycle is out of range");
    }
    if (captureCycle != state.expectedCaptureCycle)
    {
        throw std::invalid_argument("matrix capture cycles must arrive in order");
    }

    if (captureCycle < kMatrixSourceRegistersPerLane)
    {
        state.capture.a[captureCycle] = read0;
        state.capture.b[captureCycle] = read1;
    }
    else
    {
        const std::uint32_t accumulatorPair =
            (captureCycle - kMatrixSourceRegistersPerLane) * 2U;
        state.capture.c[accumulatorPair] = read0;
        state.capture.c[accumulatorPair + 1U] = read1;
    }

    const bool committed = captureCycle == kMatrixRegisterCaptureCycles - 1U;
    if (committed)
    {
        state.active = state.capture;
        state.activeValid = true;
        ++state.activeGeneration;
        state.expectedCaptureCycle = 0U;
    }
    else
    {
        ++state.expectedCaptureCycle;
    }

    return committed;
}

} // namespace cgx1::matrix
