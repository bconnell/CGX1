// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "cgx1_matrix_pipeline.hpp"

#include <cstdint>
#include <stdexcept>

namespace cgx1::matrix {

inline constexpr std::uint32_t kMatrixRegisterBankMask =
    kMatrixRegisterBankClasses - 1U;

inline constexpr bool IsPowerOfTwo(std::uint32_t value)
{
    return value != 0U && (value & (value - 1U)) == 0U;
}

inline constexpr std::uint8_t MatrixRegisterBank(std::uint8_t registerIndex)
{
    static_assert(IsPowerOfTwo(kMatrixRegisterBankClasses));
    return static_cast<std::uint8_t>(
        static_cast<std::uint32_t>(registerIndex) & kMatrixRegisterBankMask);
}

inline constexpr std::uint8_t MatrixRegisterBankRow(std::uint8_t registerIndex)
{
    static_assert(IsPowerOfTwo(kMatrixRegisterBankClasses));
    return static_cast<std::uint8_t>(
        static_cast<std::uint32_t>(registerIndex) / kMatrixRegisterBankClasses);
}

inline constexpr bool MatrixReadPairBankCompatible(
    std::uint8_t register0,
    std::uint8_t register1)
{
    if (register0 == register1)
    {
        return kMatrixAliasedSourceBroadcastAllowed;
    }

    return MatrixRegisterBank(register0) != MatrixRegisterBank(register1);
}

inline constexpr bool MatrixCaptureCycleBankCompatible(
    std::uint32_t captureCycle,
    std::uint8_t sourceABase,
    std::uint8_t sourceBBase,
    std::uint8_t accumulatorBase)
{
    const MatrixCaptureCycle schedule =
        MatrixCaptureSchedule(captureCycle, sourceABase, sourceBBase, accumulatorBase);

    return MatrixReadPairBankCompatible(
        schedule.read0.architecturalRegister,
        schedule.read1.architecturalRegister);
}

inline constexpr bool MatrixRegisterLayoutBankCompatible(
    std::uint8_t destinationBase,
    std::uint8_t sourceABase,
    std::uint8_t sourceBBase)
{
    if (!IsValidMatrixRegisterLayout(destinationBase, sourceABase, sourceBBase))
    {
        return false;
    }

    for (std::uint32_t cycle = 0U; cycle < kMatrixRegisterCaptureCycles; ++cycle)
    {
        if (!MatrixCaptureCycleBankCompatible(
                cycle, sourceABase, sourceBBase, destinationBase))
        {
            return false;
        }
    }

    return true;
}

inline constexpr bool MatrixBankClassPlacementMatchesContract(
    std::uint8_t sourceABase,
    std::uint8_t sourceBBase)
{
    const bool aClass =
        MatrixRegisterBank(sourceABase) == kMatrixSourceABaseModulo;
    const bool bClass =
        sourceBBase == sourceABase
        ? kMatrixAliasedSourceBroadcastAllowed
        : MatrixRegisterBank(sourceBBase) == kMatrixSourceBBaseModulo;

    return aClass && bClass;
}

} // namespace cgx1::matrix
