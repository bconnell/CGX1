// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_check.h"
#include "cgx1_matrix_result_staging.hpp"

#include <cstdint>
#include <stdexcept>

namespace {

cgx1::matrix::MatrixWaveRegister MakeResultWave(std::uint32_t tag)
{
    cgx1::matrix::MatrixWaveRegister wave{};
    for (std::uint32_t lane = 0U; lane < wave.size(); ++lane)
    {
        wave[lane] = (tag << 8U) | lane;
    }
    return wave;
}

cgx1::matrix::MatrixResultSet MakeResultSet(std::uint32_t tagBase)
{
    cgx1::matrix::MatrixResultSet result{};
    for (std::uint32_t reg = 0U; reg < result.size(); ++reg)
    {
        result[reg] = MakeResultWave(tagBase + reg);
    }
    return result;
}

} // namespace

int main()
{
    using namespace cgx1::matrix;

    static_assert(sizeof(MatrixResultSet) == kMatrixOutputStageBytes);
    static_assert(kMatrixOutputStageBytes == 1024U);
    static_assert(kMatrixWritebackCycles == kMatrixAccumulatorRegistersPerLane);

    MatrixResultStagingState state{};
    CGX1_TEST_CHECK(!state.valid);
    CGX1_TEST_CHECK(state.generation == 0U);

    const MatrixResultSet first = MakeResultSet(0x100U);
    LoadMatrixResult(state, first);
    CGX1_TEST_CHECK(state.valid);
    CGX1_TEST_CHECK(state.generation == 1U);
    CGX1_TEST_CHECK(state.expectedWritebackCycle == 0U);

    bool rejectedOccupiedLoad = false;
    try
    {
        LoadMatrixResult(state, MakeResultSet(0x200U));
    }
    catch (const std::logic_error&)
    {
        rejectedOccupiedLoad = true;
    }
    CGX1_TEST_CHECK(rejectedOccupiedLoad);

    for (std::uint32_t cycle = 0U; cycle < kMatrixWritebackCycles; ++cycle)
    {
        const MatrixWaveRegister wave =
            ConsumeMatrixResultWritebackCycle(state, cycle);
        CGX1_TEST_CHECK(wave == first[cycle]);
        CGX1_TEST_CHECK(state.valid == (cycle != kMatrixWritebackCycles - 1U));
    }

    CGX1_TEST_CHECK(!state.valid);
    CGX1_TEST_CHECK(state.expectedWritebackCycle == 0U);

    const MatrixResultSet second = MakeResultSet(0x200U);
    LoadMatrixResult(state, second);
    CGX1_TEST_CHECK(state.generation == 2U);

    bool rejectedOutOfOrder = false;
    try
    {
        (void)ConsumeMatrixResultWritebackCycle(state, 1U);
    }
    catch (const std::invalid_argument&)
    {
        rejectedOutOfOrder = true;
    }
    CGX1_TEST_CHECK(rejectedOutOfOrder);

    for (std::uint32_t cycle = 0U; cycle < kMatrixWritebackCycles; ++cycle)
    {
        const MatrixWaveRegister consumed =
            ConsumeMatrixResultWritebackCycle(state, cycle);
        CGX1_TEST_CHECK(consumed == second[cycle]);
    }
    CGX1_TEST_CHECK(!state.valid);

    bool rejectedEmpty = false;
    try
    {
        (void)ConsumeMatrixResultWritebackCycle(state, 0U);
    }
    catch (const std::logic_error&)
    {
        rejectedEmpty = true;
    }
    CGX1_TEST_CHECK(rejectedEmpty);

    MatrixResultStagingState bypassState{};
    const MatrixResultSet bypass = MakeResultSet(0x400U);
    const MatrixWaveRegister bypassCycleZero =
        LoadAndConsumeMatrixResultCycleZero(bypassState, bypass);
    CGX1_TEST_CHECK(bypassCycleZero == bypass[0]);
    CGX1_TEST_CHECK(bypassState.valid);
    CGX1_TEST_CHECK(bypassState.expectedWritebackCycle == 1U);
    CGX1_TEST_CHECK(bypassState.generation == 1U);

    for (std::uint32_t cycle = 1U;
         cycle < kMatrixWritebackCycles;
         ++cycle)
    {
        const MatrixWaveRegister consumed =
            ConsumeMatrixResultWritebackCycle(bypassState, cycle);
        CGX1_TEST_CHECK(consumed == bypass[cycle]);
    }
    CGX1_TEST_CHECK(!bypassState.valid);

    bool rejectedBypassOverwrite = false;
    MatrixResultStagingState occupiedBypass{};
    LoadMatrixResult(occupiedBypass, MakeResultSet(0x500U));
    try
    {
        (void)LoadAndConsumeMatrixResultCycleZero(
            occupiedBypass,
            MakeResultSet(0x600U));
    }
    catch (const std::logic_error&)
    {
        rejectedBypassOverwrite = true;
    }
    CGX1_TEST_CHECK(rejectedBypassOverwrite);

    MatrixResultStagingState rangeState{};
    LoadMatrixResult(rangeState, MakeResultSet(0x300U));
    bool rejectedRange = false;
    try
    {
        (void)ConsumeMatrixResultWritebackCycle(
            rangeState,
            kMatrixWritebackCycles);
    }
    catch (const std::invalid_argument&)
    {
        rejectedRange = true;
    }
    CGX1_TEST_CHECK(rejectedRange);

    return 0;
}
