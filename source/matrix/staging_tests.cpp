// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_check.h"
#include "cgx1_matrix_staging.hpp"

#include <cstdint>
#include <stdexcept>

namespace {

cgx1::matrix::MatrixWaveRegister MakeWave(std::uint32_t tag)
{
    cgx1::matrix::MatrixWaveRegister wave{};
    for (std::uint32_t lane = 0U; lane < wave.size(); ++lane)
    {
        wave[lane] = (tag << 8U) | lane;
    }
    return wave;
}

void CaptureOperation(
    cgx1::matrix::MatrixOperandStagingState& state,
    std::uint32_t tagBase)
{
    using namespace cgx1::matrix;

    for (std::uint32_t cycle = 0U; cycle < kMatrixRegisterCaptureCycles; ++cycle)
    {
        MatrixWaveRegister read0{};
        MatrixWaveRegister read1{};

        if (cycle < kMatrixSourceRegistersPerLane)
        {
            read0 = MakeWave(tagBase + 0x10U + cycle);
            read1 = MakeWave(tagBase + 0x20U + cycle);
        }
        else
        {
            const std::uint32_t pair =
                (cycle - kMatrixSourceRegistersPerLane) * 2U;
            read0 = MakeWave(tagBase + 0x30U + pair);
            read1 = MakeWave(tagBase + 0x30U + pair + 1U);
        }

        const bool committed =
            CaptureMatrixOperandCycle(state, cycle, read0, read1);
        CGX1_TEST_CHECK(committed == (cycle == kMatrixRegisterCaptureCycles - 1U));
    }
}

void CheckActive(
    const cgx1::matrix::MatrixOperandStagingState& state,
    std::uint32_t tagBase)
{
    using namespace cgx1::matrix;

    CGX1_TEST_CHECK(state.activeValid);

    for (std::uint32_t reg = 0U; reg < kMatrixSourceRegistersPerLane; ++reg)
    {
        const MatrixWaveRegister expectedA =
            MakeWave(tagBase + 0x10U + reg);
        const MatrixWaveRegister expectedB =
            MakeWave(tagBase + 0x20U + reg);

        CGX1_TEST_CHECK(state.active.a[reg] == expectedA);
        CGX1_TEST_CHECK(state.active.b[reg] == expectedB);
    }

    for (std::uint32_t reg = 0U; reg < kMatrixAccumulatorRegistersPerLane; ++reg)
    {
        const MatrixWaveRegister expectedC =
            MakeWave(tagBase + 0x30U + reg);
        CGX1_TEST_CHECK(state.active.c[reg] == expectedC);
    }
}

} // namespace

int main()
{
    using namespace cgx1::matrix;

    static_assert(sizeof(std::uint32_t) == 4U);
    static_assert(sizeof(MatrixWaveRegister) == kWaveRegisterBytes);
    static_assert(sizeof(MatrixOperandSet) == kMatrixInputStageBytes);
    static_assert(kMatrixActiveExecutionOperandBytes == 2048U);
    static_assert(kMatrixOutputStageBytes == 1024U);
    static_assert(kMatrixLogicalPipelineStorageBytesPerEngine == 5120U);
    static_assert(kMatrixLogicalPipelineStorageBytesPerComputeUnit == 20480U);

    MatrixOperandStagingState state{};
    CGX1_TEST_CHECK(!state.activeValid);
    CGX1_TEST_CHECK(state.activeGeneration == 0U);

    CaptureOperation(state, 0x100U);
    CGX1_TEST_CHECK(state.activeGeneration == 1U);
    CheckActive(state, 0x100U);

    // The next capture buffer may be overwritten while the current active
    // execution operands remain stable. The active set changes only when the
    // eighth capture cycle commits the next operation.
    for (std::uint32_t cycle = 0U; cycle < 7U; ++cycle)
    {
        MatrixWaveRegister read0{};
        MatrixWaveRegister read1{};

        if (cycle < kMatrixSourceRegistersPerLane)
        {
            read0 = MakeWave(0x200U + 0x10U + cycle);
            read1 = MakeWave(0x200U + 0x20U + cycle);
        }
        else
        {
            const std::uint32_t pair =
                (cycle - kMatrixSourceRegistersPerLane) * 2U;
            read0 = MakeWave(0x200U + 0x30U + pair);
            read1 = MakeWave(0x200U + 0x30U + pair + 1U);
        }

        const bool unexpectedCapture =
            CaptureMatrixOperandCycle(state, cycle, read0, read1);
        CGX1_TEST_CHECK(!unexpectedCapture);
        CheckActive(state, 0x100U);
        CGX1_TEST_CHECK(state.activeGeneration == 1U);
    }

    const MatrixWaveRegister final0 = MakeWave(0x200U + 0x36U);
    const MatrixWaveRegister final1 = MakeWave(0x200U + 0x37U);
    const bool capturedFinalCycle =
        CaptureMatrixOperandCycle(state, 7U, final0, final1);
    CGX1_TEST_CHECK(capturedFinalCycle);
    CGX1_TEST_CHECK(state.activeGeneration == 2U);
    CheckActive(state, 0x200U);

    bool rejectedOutOfOrder = false;
    try
    {
        MatrixOperandStagingState invalid{};
        (void)CaptureMatrixOperandCycle(
            invalid, 1U, MakeWave(1U), MakeWave(2U));
    }
    catch (const std::invalid_argument&)
    {
        rejectedOutOfOrder = true;
    }
    CGX1_TEST_CHECK(rejectedOutOfOrder);

    bool rejectedRange = false;
    try
    {
        MatrixOperandStagingState invalid{};
        (void)CaptureMatrixOperandCycle(
            invalid, 8U, MakeWave(1U), MakeWave(2U));
    }
    catch (const std::invalid_argument&)
    {
        rejectedRange = true;
    }
    CGX1_TEST_CHECK(rejectedRange);

    return 0;
}
