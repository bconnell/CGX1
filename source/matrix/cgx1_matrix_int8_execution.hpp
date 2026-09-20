// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "cgx1_matrix_result_staging.hpp"

#include <array>
#include <bit>
#include <cstdint>
#include <stdexcept>

namespace cgx1::matrix {

struct MatrixInt8ExecutionState
{
    std::array<std::uint32_t, kMatrixTileM * kMatrixTileN> even{};
    std::array<std::uint32_t, kMatrixTileM * kMatrixTileN> odd{};
    std::uint8_t expectedCycle = 0U;
    bool active = false;
};

inline std::uint32_t MatrixWaveWord(
    const MatrixWaveRegister& wave,
    std::uint32_t lane)
{
    if (lane >= kNativeWaveSize)
    {
        throw std::invalid_argument("matrix lane is out of range");
    }
    return wave[lane];
}

inline std::int8_t MatrixInt8AElement(
    const MatrixOperandSet& operands,
    std::uint32_t row,
    std::uint32_t k)
{
    if (row >= kMatrixTileM || k >= kFp8Int8TileK)
    {
        throw std::invalid_argument("matrix INT8 A coordinate is out of range");
    }

    const std::uint32_t lane = row * 2U + (k / 16U);
    const std::uint32_t element = k % 16U;
    const std::uint32_t reg = element / 4U;
    const std::uint32_t byte = element % 4U;
    const std::uint32_t word = MatrixWaveWord(operands.a[reg], lane);
    return std::bit_cast<std::int8_t>(
        static_cast<std::uint8_t>((word >> (byte * 8U)) & 0xffU));
}

inline std::int8_t MatrixInt8BElement(
    const MatrixOperandSet& operands,
    std::uint32_t k,
    std::uint32_t column)
{
    if (k >= kFp8Int8TileK || column >= kMatrixTileN)
    {
        throw std::invalid_argument("matrix INT8 B coordinate is out of range");
    }

    const std::uint32_t lane = k;
    const std::uint32_t reg = column / 4U;
    const std::uint32_t byte = column % 4U;
    const std::uint32_t word = MatrixWaveWord(operands.b[reg], lane);
    return static_cast<std::int8_t>(
        static_cast<std::uint8_t>((word >> (byte * 8U)) & 0xffU));
}

inline std::int32_t MatrixInt32CElement(
    const MatrixOperandSet& operands,
    std::uint32_t row,
    std::uint32_t column)
{
    if (row >= kMatrixTileM || column >= kMatrixTileN)
    {
        throw std::invalid_argument("matrix INT32 C coordinate is out of range");
    }

    const std::uint32_t lane = row * 2U + (column / 8U);
    const std::uint32_t reg = column % 8U;
    return std::bit_cast<std::int32_t>(
        MatrixWaveWord(operands.c[reg], lane));
}

inline void MatrixSetInt8AElement(
    MatrixOperandSet& operands,
    std::uint32_t row,
    std::uint32_t k,
    std::int8_t value)
{
    if (row >= kMatrixTileM || k >= kFp8Int8TileK)
    {
        throw std::invalid_argument("matrix INT8 A coordinate is out of range");
    }

    const std::uint32_t lane = row * 2U + (k / 16U);
    const std::uint32_t element = k % 16U;
    const std::uint32_t reg = element / 4U;
    const std::uint32_t byte = element % 4U;
    const std::uint32_t shift = byte * 8U;
    const std::uint32_t mask = 0xffU << shift;
    std::uint32_t& word = operands.a[reg][lane];
    word = (word & ~mask)
        | (static_cast<std::uint32_t>(
               static_cast<std::uint8_t>(value))
            << shift);
}

inline void MatrixSetInt8BElement(
    MatrixOperandSet& operands,
    std::uint32_t k,
    std::uint32_t column,
    std::int8_t value)
{
    if (k >= kFp8Int8TileK || column >= kMatrixTileN)
    {
        throw std::invalid_argument("matrix INT8 B coordinate is out of range");
    }

    const std::uint32_t lane = k;
    const std::uint32_t reg = column / 4U;
    const std::uint32_t byte = column % 4U;
    const std::uint32_t shift = byte * 8U;
    const std::uint32_t mask = 0xffU << shift;
    std::uint32_t& word = operands.b[reg][lane];
    word = (word & ~mask)
        | (static_cast<std::uint32_t>(
               static_cast<std::uint8_t>(value))
            << shift);
}

inline void MatrixSetInt32CElement(
    MatrixOperandSet& operands,
    std::uint32_t row,
    std::uint32_t column,
    std::int32_t value)
{
    if (row >= kMatrixTileM || column >= kMatrixTileN)
    {
        throw std::invalid_argument("matrix INT32 C coordinate is out of range");
    }

    const std::uint32_t lane = row * 2U + (column / 8U);
    const std::uint32_t reg = column % 8U;
    operands.c[reg][lane] = std::bit_cast<std::uint32_t>(value);
}

inline std::int32_t MatrixResultInt32Element(
    const MatrixResultSet& result,
    std::uint32_t row,
    std::uint32_t column)
{
    if (row >= kMatrixTileM || column >= kMatrixTileN)
    {
        throw std::invalid_argument("matrix INT32 result coordinate is out of range");
    }

    const std::uint32_t lane = row * 2U + (column / 8U);
    const std::uint32_t reg = column % 8U;
    return std::bit_cast<std::int32_t>(result[reg][lane]);
}

inline std::uint32_t MatrixInt8ProductBits(
    std::int8_t left,
    std::int8_t right)
{
    const std::int32_t product =
        static_cast<std::int32_t>(left)
        * static_cast<std::int32_t>(right);
    return std::bit_cast<std::uint32_t>(product);
}

inline MatrixResultSet ExecuteMatrixInt8Cycle(
    MatrixInt8ExecutionState& state,
    const MatrixOperandSet& operands,
    std::uint32_t cycle)
{
    if (cycle >= kMatrixExecutionCycles)
    {
        throw std::invalid_argument("matrix INT8 execution cycle is out of range");
    }
    if (state.active && cycle != state.expectedCycle)
    {
        throw std::invalid_argument("matrix INT8 execution cycles must arrive in order");
    }
    if (!state.active && cycle != 0U)
    {
        throw std::invalid_argument("matrix INT8 execution must start at cycle zero");
    }

    if (!state.active)
    {
        state.active = true;
        state.expectedCycle = 0U;
        for (std::uint32_t row = 0U; row < kMatrixTileM; ++row)
        {
            for (std::uint32_t column = 0U; column < kMatrixTileN; ++column)
            {
                const std::uint32_t index = row * kMatrixTileN + column;
                state.even[index] = std::bit_cast<std::uint32_t>(
                    MatrixInt32CElement(operands, row, column));
                state.odd[index] = 0U;
            }
        }
    }

    const std::uint32_t evenK = cycle * 2U;
    const std::uint32_t oddK = evenK + 1U;
    MatrixResultSet result{};

    for (std::uint32_t row = 0U; row < kMatrixTileM; ++row)
    {
        for (std::uint32_t column = 0U; column < kMatrixTileN; ++column)
        {
            const std::uint32_t index = row * kMatrixTileN + column;

            const std::uint32_t nextEven =
                state.even[index]
                + MatrixInt8ProductBits(
                    MatrixInt8AElement(operands, row, evenK),
                    MatrixInt8BElement(operands, evenK, column));
            const std::uint32_t nextOdd =
                state.odd[index]
                + MatrixInt8ProductBits(
                    MatrixInt8AElement(operands, row, oddK),
                    MatrixInt8BElement(operands, oddK, column));

            state.even[index] = nextEven;
            state.odd[index] = nextOdd;

            if (cycle == kMatrixExecutionCycles - 1U)
            {
                const std::uint32_t combined = nextEven + nextOdd;
                const std::uint32_t lane =
                    row * 2U + (column / 8U);
                const std::uint32_t reg = column % 8U;
                result[reg][lane] = combined;
            }
        }
    }

    if (cycle == kMatrixExecutionCycles - 1U)
    {
        state.active = false;
        state.expectedCycle = 0U;
    }
    else
    {
        state.expectedCycle =
            static_cast<std::uint8_t>(cycle + 1U);
    }

    return result;
}

} // namespace cgx1::matrix
