// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_matrix_result_staging.hpp"

#include <cassert>
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
    assert(!state.valid);
    assert(state.generation == 0U);

    const MatrixResultSet first = MakeResultSet(0x100U);
    LoadMatrixResult(state, first);
    assert(state.valid);
    assert(state.generation == 1U);
    assert(state.expectedWritebackCycle == 0U);

    bool rejectedOccupiedLoad = false;
    try
    {
        LoadMatrixResult(state, MakeResultSet(0x200U));
    }
    catch (const std::logic_error&)
    {
        rejectedOccupiedLoad = true;
    }
    assert(rejectedOccupiedLoad);

    for (std::uint32_t cycle = 0U; cycle < kMatrixWritebackCycles; ++cycle)
    {
        const MatrixWaveRegister wave =
            ConsumeMatrixResultWritebackCycle(state, cycle);
        assert(wave == first[cycle]);
        assert(state.valid == (cycle != kMatrixWritebackCycles - 1U));
    }

    assert(!state.valid);
    assert(state.expectedWritebackCycle == 0U);

    const MatrixResultSet second = MakeResultSet(0x200U);
    LoadMatrixResult(state, second);
    assert(state.generation == 2U);

    bool rejectedOutOfOrder = false;
    try
    {
        (void)ConsumeMatrixResultWritebackCycle(state, 1U);
    }
    catch (const std::invalid_argument&)
    {
        rejectedOutOfOrder = true;
    }
    assert(rejectedOutOfOrder);

    for (std::uint32_t cycle = 0U; cycle < kMatrixWritebackCycles; ++cycle)
    {
        assert(ConsumeMatrixResultWritebackCycle(state, cycle)
            == second[cycle]);
    }
    assert(!state.valid);

    bool rejectedEmpty = false;
    try
    {
        (void)ConsumeMatrixResultWritebackCycle(state, 0U);
    }
    catch (const std::logic_error&)
    {
        rejectedEmpty = true;
    }
    assert(rejectedEmpty);

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
    assert(rejectedRange);

    return 0;
}
