// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_matrix_int8_execution.hpp"

#include <cassert>
#include <cstdint>

int main()
{
    using namespace cgx1::matrix;

    MatrixOperandSet source{};
    for (std::uint32_t row = 0U; row < kMatrixTileM; ++row)
    {
        for (std::uint32_t k = 0U; k < kFp8Int8TileK; ++k)
        {
            MatrixSetInt8AElement(source, row, k, 1);
        }
    }
    for (std::uint32_t k = 0U; k < kFp8Int8TileK; ++k)
    {
        for (std::uint32_t column = 0U; column < kMatrixTileN; ++column)
        {
            MatrixSetInt8BElement(source, k, column, 1);
        }
    }
    for (std::uint32_t row = 0U; row < kMatrixTileM; ++row)
    {
        for (std::uint32_t column = 0U; column < kMatrixTileN; ++column)
        {
            MatrixSetInt32CElement(
                source,
                row,
                column,
                static_cast<std::int32_t>(row * 100U + column));
        }
    }

    MatrixOperandStagingState operands{};
    for (std::uint32_t cycle = 0U;
         cycle < kMatrixRegisterCaptureCycles;
         ++cycle)
    {
        MatrixWaveRegister read0{};
        MatrixWaveRegister read1{};

        if (cycle < kMatrixSourceRegistersPerLane)
        {
            read0 = source.a[cycle];
            read1 = source.b[cycle];
        }
        else
        {
            const std::uint32_t pair =
                (cycle - kMatrixSourceRegistersPerLane) * 2U;
            read0 = source.c[pair];
            read1 = source.c[pair + 1U];
        }

        const bool committed =
            CaptureMatrixOperandCycle(
                operands,
                cycle,
                read0,
                read1);
        assert(committed
            == (cycle == kMatrixRegisterCaptureCycles - 1U));
    }
    assert(operands.activeValid);

    MatrixInt8ExecutionState execution{};
    MatrixResultSet result{};
    for (std::uint32_t cycle = 0U;
         cycle < kMatrixExecutionCycles;
         ++cycle)
    {
        result = ExecuteMatrixInt8Cycle(
            execution,
            operands.active,
            cycle);
    }

    MatrixResultStagingState output{};
    assert(LoadAndConsumeMatrixResultCycleZero(output, result)
        == result[0]);

    for (std::uint32_t cycle = 1U;
         cycle < kMatrixWritebackCycles;
         ++cycle)
    {
        assert(ConsumeMatrixResultWritebackCycle(output, cycle)
            == result[cycle]);
    }
    assert(!output.valid);

    for (std::uint32_t row = 0U; row < kMatrixTileM; ++row)
    {
        for (std::uint32_t column = 0U; column < kMatrixTileN; ++column)
        {
            const std::int32_t expected =
                static_cast<std::int32_t>(row * 100U + column + 32U);
            assert(MatrixResultInt32Element(
                result,
                row,
                column) == expected);
        }
    }

    return 0;
}
