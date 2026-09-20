// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "cgx1_matrix_staging.hpp"

#include <array>
#include <cstdint>
#include <stdexcept>

namespace cgx1::matrix {

using MatrixResultSet =
    std::array<MatrixWaveRegister, kMatrixAccumulatorRegistersPerLane>;

struct MatrixResultStagingState
{
    MatrixResultSet result{};
    std::uint8_t expectedWritebackCycle = 0U;
    bool valid = false;
    std::uint64_t generation = 0U;
};

inline void LoadMatrixResult(
    MatrixResultStagingState& state,
    const MatrixResultSet& result)
{
    if (state.valid)
    {
        throw std::logic_error(
            "matrix output-result staging slot is already occupied");
    }

    state.result = result;
    state.expectedWritebackCycle = 0U;
    state.valid = true;
    ++state.generation;
}

inline MatrixWaveRegister LoadAndConsumeMatrixResultCycleZero(
    MatrixResultStagingState& state,
    const MatrixResultSet& result)
{
    if (state.valid)
    {
        throw std::logic_error(
            "matrix output-result staging slot is already occupied");
    }

    state.result = result;
    state.expectedWritebackCycle = 1U;
    state.valid = true;
    ++state.generation;
    return result[0];
}

inline MatrixWaveRegister ConsumeMatrixResultWritebackCycle(
    MatrixResultStagingState& state,
    std::uint32_t writebackCycle)
{
    if (!state.valid)
    {
        throw std::logic_error(
            "matrix output-result staging slot is empty");
    }
    if (writebackCycle >= kMatrixWritebackCycles)
    {
        throw std::invalid_argument(
            "matrix output-result writeback cycle is out of range");
    }
    if (writebackCycle != state.expectedWritebackCycle)
    {
        throw std::invalid_argument(
            "matrix output-result writeback cycles must arrive in order");
    }

    const MatrixWaveRegister wave = state.result[writebackCycle];

    if (writebackCycle == kMatrixWritebackCycles - 1U)
    {
        state.valid = false;
        state.expectedWritebackCycle = 0U;
    }
    else
    {
        ++state.expectedWritebackCycle;
    }

    return wave;
}

} // namespace cgx1::matrix
