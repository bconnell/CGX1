// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "cgx1_matrix_pipeline.hpp"

#include <array>
#include <cstdint>
#include <stdexcept>

namespace cgx1::matrix {

inline constexpr std::uint32_t kMatrixScoreboardRegisterCount = 256U;

using MatrixRegisterMask =
    std::array<bool, kMatrixScoreboardRegisterCount>;

struct MatrixWaveScoreboardState
{
    MatrixRegisterMask sourcePending{};
    MatrixRegisterMask destinationPending{};
};

struct MatrixOrdinaryIssueRequest
{
    MatrixRegisterMask readMask{};
    MatrixRegisterMask writeMask{};
    bool usesReadPorts = false;
    bool usesWritePort = false;
};

struct MatrixOrdinaryIssueStatus
{
    bool rawHazard = false;
    bool wawHazard = false;
    bool warHazard = false;
    bool readPortConflict = false;
    bool writePortConflict = false;

    constexpr bool Ready() const
    {
        return !rawHazard
            && !wawHazard
            && !warHazard
            && !readPortConflict
            && !writePortConflict;
    }
};

inline MatrixRegisterMask MatrixRegisterRangeMask(
    std::uint8_t base,
    std::uint32_t count)
{
    if (count == 0U
        || static_cast<std::uint32_t>(base) + count
            > kMatrixScoreboardRegisterCount)
    {
        throw std::invalid_argument("matrix scoreboard register range is invalid");
    }

    MatrixRegisterMask mask{};
    for (std::uint32_t offset = 0U; offset < count; ++offset)
    {
        mask[static_cast<std::uint32_t>(base) + offset] = true;
    }
    return mask;
}

inline bool MatrixMaskAny(const MatrixRegisterMask& mask)
{
    for (bool bit : mask)
    {
        if (bit)
        {
            return true;
        }
    }
    return false;
}

inline bool MatrixMasksOverlap(
    const MatrixRegisterMask& left,
    const MatrixRegisterMask& right)
{
    for (std::uint32_t index = 0U;
         index < kMatrixScoreboardRegisterCount;
         ++index)
    {
        if (left[index] && right[index])
        {
            return true;
        }
    }
    return false;
}

inline void MatrixMaskSet(
    MatrixRegisterMask& destination,
    const MatrixRegisterMask& source)
{
    for (std::uint32_t index = 0U;
         index < kMatrixScoreboardRegisterCount;
         ++index)
    {
        destination[index] = destination[index] || source[index];
    }
}

inline void MatrixMaskClear(
    MatrixRegisterMask& destination,
    const MatrixRegisterMask& source)
{
    for (std::uint32_t index = 0U;
         index < kMatrixScoreboardRegisterCount;
         ++index)
    {
        if (source[index])
        {
            destination[index] = false;
        }
    }
}

inline void ReserveMatrixWaveScoreboard(
    MatrixWaveScoreboardState& state,
    std::uint8_t destinationBase,
    std::uint8_t sourceABase,
    std::uint8_t sourceBBase)
{
    if (!IsValidMatrixRegisterLayout(
            destinationBase,
            sourceABase,
            sourceBBase))
    {
        throw std::invalid_argument("matrix scoreboard issue layout is invalid");
    }

    if (MatrixMaskAny(state.sourcePending))
    {
        throw std::logic_error(
            "matrix scoreboard source capture is already active");
    }


    const MatrixRegisterMask sourceA =
        MatrixRegisterRangeMask(
            sourceABase,
            kMatrixSourceRegistersPerLane);
    const MatrixRegisterMask sourceB =
        MatrixRegisterRangeMask(
            sourceBBase,
            kMatrixSourceRegistersPerLane);
    const MatrixRegisterMask destination =
        MatrixRegisterRangeMask(
            destinationBase,
            kMatrixAccumulatorRegistersPerLane);

    if (MatrixMasksOverlap(sourceA, state.destinationPending)
        || MatrixMasksOverlap(sourceB, state.destinationPending)
        || MatrixMasksOverlap(destination, state.destinationPending))
    {
        throw std::logic_error(
            "matrix scoreboard issue depends on a pending destination");
    }

    MatrixMaskSet(state.sourcePending, sourceA);
    MatrixMaskSet(state.sourcePending, sourceB);
    MatrixMaskSet(state.destinationPending, destination);
}

inline void ReleaseMatrixWaveSources(
    MatrixWaveScoreboardState& state,
    std::uint8_t sourceABase,
    std::uint8_t sourceBBase)
{
    MatrixMaskClear(
        state.sourcePending,
        MatrixRegisterRangeMask(
            sourceABase,
            kMatrixSourceRegistersPerLane));
    MatrixMaskClear(
        state.sourcePending,
        MatrixRegisterRangeMask(
            sourceBBase,
            kMatrixSourceRegistersPerLane));
}

inline void CompleteMatrixWaveDestination(
    MatrixWaveScoreboardState& state,
    std::uint8_t destinationBase)
{
    MatrixMaskClear(
        state.destinationPending,
        MatrixRegisterRangeMask(
            destinationBase,
            kMatrixAccumulatorRegistersPerLane));
}

inline MatrixOrdinaryIssueStatus EvaluateOrdinaryIssueAgainstMatrix(
    const MatrixWaveScoreboardState& state,
    const MatrixOrdinaryIssueRequest& request,
    bool matrixReadPortsOwned,
    bool matrixWritePortOwned)
{
    MatrixOrdinaryIssueStatus status{};
    status.rawHazard =
        MatrixMasksOverlap(request.readMask, state.destinationPending);
    status.wawHazard =
        MatrixMasksOverlap(request.writeMask, state.destinationPending);
    status.warHazard =
        MatrixMasksOverlap(request.writeMask, state.sourcePending);
    status.readPortConflict =
        request.usesReadPorts && matrixReadPortsOwned;
    status.writePortConflict =
        request.usesWritePort && matrixWritePortOwned;
    return status;
}

} // namespace cgx1::matrix
