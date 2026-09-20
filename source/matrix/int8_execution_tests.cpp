// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_matrix_int8_execution.hpp"

#include <cassert>
#include <cstdint>
#include <limits>
#include <stdexcept>

namespace {

cgx1::matrix::MatrixResultSet Run(
    const cgx1::matrix::MatrixOperandSet& operands)
{
    cgx1::matrix::MatrixInt8ExecutionState state{};
    cgx1::matrix::MatrixResultSet result{};

    for (std::uint32_t cycle = 0U;
         cycle < cgx1::matrix::kMatrixExecutionCycles;
         ++cycle)
    {
        result =
            cgx1::matrix::ExecuteMatrixInt8Cycle(
                state,
                operands,
                cycle);
        assert(state.active
            == (cycle != cgx1::matrix::kMatrixExecutionCycles - 1U));
    }

    return result;
}

std::int32_t ScalarExpected(
    const cgx1::matrix::MatrixOperandSet& operands,
    std::uint32_t row,
    std::uint32_t column)
{
    using namespace cgx1::matrix;

    std::uint32_t even = std::bit_cast<std::uint32_t>(
        MatrixInt32CElement(operands, row, column));
    std::uint32_t odd = 0U;

    for (std::uint32_t k = 0U; k < kFp8Int8TileK; k += 2U)
    {
        even += MatrixInt8ProductBits(
            MatrixInt8AElement(operands, row, k),
            MatrixInt8BElement(operands, k, column));
        odd += MatrixInt8ProductBits(
            MatrixInt8AElement(operands, row, k + 1U),
            MatrixInt8BElement(operands, k + 1U, column));
    }

    return std::bit_cast<std::int32_t>(even + odd);
}

} // namespace

int main()
{
    using namespace cgx1::matrix;

    static_assert(kMatrixExecutionCycles == 16U);
    static_assert(kFp8Int8TileK == 32U);

    MatrixOperandSet ones{};
    for (std::uint32_t row = 0U; row < kMatrixTileM; ++row)
    {
        for (std::uint32_t k = 0U; k < kFp8Int8TileK; ++k)
        {
            MatrixSetInt8AElement(ones, row, k, 1);
        }
    }
    for (std::uint32_t k = 0U; k < kFp8Int8TileK; ++k)
    {
        for (std::uint32_t column = 0U; column < kMatrixTileN; ++column)
        {
            MatrixSetInt8BElement(ones, k, column, 1);
        }
    }

    const MatrixResultSet onesResult = Run(ones);
    for (std::uint32_t row = 0U; row < kMatrixTileM; ++row)
    {
        for (std::uint32_t column = 0U; column < kMatrixTileN; ++column)
        {
            assert(MatrixResultInt32Element(
                onesResult, row, column) == 32);
        }
    }

    MatrixOperandSet patterned{};
    for (std::uint32_t row = 0U; row < kMatrixTileM; ++row)
    {
        for (std::uint32_t k = 0U; k < kFp8Int8TileK; ++k)
        {
            const auto value = static_cast<std::int8_t>(
                static_cast<int>((row * 7U + k * 3U) % 17U) - 8);
            MatrixSetInt8AElement(patterned, row, k, value);
        }
    }
    for (std::uint32_t k = 0U; k < kFp8Int8TileK; ++k)
    {
        for (std::uint32_t column = 0U; column < kMatrixTileN; ++column)
        {
            const auto value = static_cast<std::int8_t>(
                static_cast<int>((k * 5U + column * 11U) % 19U) - 9);
            MatrixSetInt8BElement(patterned, k, column, value);
        }
    }
    for (std::uint32_t row = 0U; row < kMatrixTileM; ++row)
    {
        for (std::uint32_t column = 0U; column < kMatrixTileN; ++column)
        {
            const std::int32_t c =
                (row == column)
                ? (std::numeric_limits<std::int32_t>::max() - 5000)
                : static_cast<std::int32_t>(
                    row * 1000U + column * 13U);
            MatrixSetInt32CElement(patterned, row, column, c);
        }
    }

    const MatrixResultSet patternedResult = Run(patterned);
    for (std::uint32_t row = 0U; row < kMatrixTileM; ++row)
    {
        for (std::uint32_t column = 0U; column < kMatrixTileN; ++column)
        {
            assert(MatrixResultInt32Element(
                patternedResult, row, column)
                == ScalarExpected(patterned, row, column));
        }
    }

    MatrixOperandSet overflow{};
    for (std::uint32_t row = 0U; row < kMatrixTileM; ++row)
    {
        for (std::uint32_t k = 0U; k < kFp8Int8TileK; ++k)
        {
            MatrixSetInt8AElement(overflow, row, k, 127);
        }
    }
    for (std::uint32_t k = 0U; k < kFp8Int8TileK; ++k)
    {
        for (std::uint32_t column = 0U; column < kMatrixTileN; ++column)
        {
            MatrixSetInt8BElement(overflow, k, column, 127);
        }
    }
    for (std::uint32_t row = 0U; row < kMatrixTileM; ++row)
    {
        for (std::uint32_t column = 0U; column < kMatrixTileN; ++column)
        {
            MatrixSetInt32CElement(
                overflow,
                row,
                column,
                std::bit_cast<std::int32_t>(0x7ffff000U));
        }
    }

    std::uint32_t overflowExpected = 0x7ffff000U;
    for (std::uint32_t k = 0U; k < kFp8Int8TileK; ++k)
    {
        overflowExpected += 127U * 127U;
    }

    const MatrixResultSet overflowResult = Run(overflow);
    for (std::uint32_t row = 0U; row < kMatrixTileM; ++row)
    {
        for (std::uint32_t column = 0U; column < kMatrixTileN; ++column)
        {
            assert(std::bit_cast<std::uint32_t>(
                MatrixResultInt32Element(
                    overflowResult, row, column))
                == overflowExpected);
        }
    }

    MatrixInt8ExecutionState invalid{};
    bool rejectedStart = false;
    try
    {
        (void)ExecuteMatrixInt8Cycle(invalid, patterned, 1U);
    }
    catch (const std::invalid_argument&)
    {
        rejectedStart = true;
    }
    assert(rejectedStart);

    MatrixInt8ExecutionState order{};
    (void)ExecuteMatrixInt8Cycle(order, patterned, 0U);
    bool rejectedOrder = false;
    try
    {
        (void)ExecuteMatrixInt8Cycle(order, patterned, 2U);
    }
    catch (const std::invalid_argument&)
    {
        rejectedOrder = true;
    }
    assert(rejectedOrder);

    return 0;
}
