// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_matrix_scoreboard.hpp"

#include <cassert>
#include <cstdint>
#include <stdexcept>

int main()
{
    using namespace cgx1::matrix;

    static_assert(kMatrixScoreboardRegisterCount == 256U);
    static_assert(kMatrixIssueIntervalCycles > kMatrixRegisterCaptureCycles);

    MatrixWaveScoreboardState state{};
    assert(!MatrixMaskAny(state.sourcePending));
    assert(!MatrixMaskAny(state.destinationPending));

    ReserveMatrixWaveScoreboard(state, 32U, 64U, 68U);

    for (std::uint32_t reg = 0U; reg < kMatrixScoreboardRegisterCount; ++reg)
    {
        const bool expectedSource = reg >= 64U && reg < 72U;
        const bool expectedDestination = reg >= 32U && reg < 40U;
        assert(state.sourcePending[reg] == expectedSource);
        assert(state.destinationPending[reg] == expectedDestination);

        MatrixOrdinaryIssueRequest read{};
        read.readMask[reg] = true;
        read.usesReadPorts = true;
        const MatrixOrdinaryIssueStatus readStatus =
            EvaluateOrdinaryIssueAgainstMatrix(
                state,
                read,
                false,
                false);
        assert(readStatus.rawHazard == expectedDestination);
        assert(!readStatus.wawHazard);
        assert(!readStatus.warHazard);
        assert(readStatus.Ready() == !expectedDestination);

        MatrixOrdinaryIssueRequest write{};
        write.writeMask[reg] = true;
        write.usesWritePort = true;
        const MatrixOrdinaryIssueStatus writeStatus =
            EvaluateOrdinaryIssueAgainstMatrix(
                state,
                write,
                false,
                false);
        assert(!writeStatus.rawHazard);
        assert(writeStatus.wawHazard == expectedDestination);
        assert(writeStatus.warHazard == expectedSource);
        assert(writeStatus.Ready()
            == !(expectedDestination || expectedSource));
    }

    MatrixOrdinaryIssueRequest unrelatedRead{};
    unrelatedRead.readMask[80U] = true;
    unrelatedRead.usesReadPorts = true;
    MatrixOrdinaryIssueStatus status =
        EvaluateOrdinaryIssueAgainstMatrix(
            state,
            unrelatedRead,
            true,
            false);
    assert(status.readPortConflict);
    assert(!status.writePortConflict);
    assert(!status.Ready());

    MatrixOrdinaryIssueRequest unrelatedWrite{};
    unrelatedWrite.writeMask[80U] = true;
    unrelatedWrite.usesWritePort = true;
    status = EvaluateOrdinaryIssueAgainstMatrix(
        state,
        unrelatedWrite,
        true,
        false);
    assert(!status.readPortConflict);
    assert(!status.writePortConflict);
    assert(status.Ready());

    status = EvaluateOrdinaryIssueAgainstMatrix(
        state,
        unrelatedWrite,
        false,
        true);
    assert(status.writePortConflict);
    assert(!status.Ready());

    ReleaseMatrixWaveSources(state, 64U, 68U);
    assert(!MatrixMaskAny(state.sourcePending));

    MatrixOrdinaryIssueRequest sourceWriteAfterRelease{};
    sourceWriteAfterRelease.writeMask[64U] = true;
    sourceWriteAfterRelease.usesWritePort = true;
    status = EvaluateOrdinaryIssueAgainstMatrix(
        state,
        sourceWriteAfterRelease,
        false,
        false);
    assert(status.Ready());

    // Keep the first destination pending while a second independent matrix
    // operation reserves a different destination.
    ReserveMatrixWaveScoreboard(state, 48U, 80U, 84U);
    for (std::uint32_t reg = 0U; reg < kMatrixScoreboardRegisterCount; ++reg)
    {
        const bool expectedDestination =
            (reg >= 32U && reg < 40U)
            || (reg >= 48U && reg < 56U);
        assert(state.destinationPending[reg] == expectedDestination);
    }

    ReleaseMatrixWaveSources(state, 80U, 84U);

    bool rejectedRaw = false;
    try
    {
        ReserveMatrixWaveScoreboard(state, 72U, 32U, 92U);
    }
    catch (const std::logic_error&)
    {
        rejectedRaw = true;
    }
    assert(rejectedRaw);

    bool rejectedWaw = false;
    try
    {
        ReserveMatrixWaveScoreboard(state, 32U, 96U, 100U);
    }
    catch (const std::logic_error&)
    {
        rejectedWaw = true;
    }
    assert(rejectedWaw);

    CompleteMatrixWaveDestination(state, 32U);
    for (std::uint32_t reg = 32U; reg < 40U; ++reg)
    {
        assert(!state.destinationPending[reg]);
    }
    for (std::uint32_t reg = 48U; reg < 56U; ++reg)
    {
        assert(state.destinationPending[reg]);
    }

    CompleteMatrixWaveDestination(state, 48U);
    assert(!MatrixMaskAny(state.destinationPending));

    // Exact A/B aliasing reserves only the same four logical source registers.
    ReserveMatrixWaveScoreboard(state, 32U, 64U, 64U);
    for (std::uint32_t reg = 0U; reg < kMatrixScoreboardRegisterCount; ++reg)
    {
        const bool expectedSource = reg >= 64U && reg < 68U;
        assert(state.sourcePending[reg] == expectedSource);
    }
    ReleaseMatrixWaveSources(state, 64U, 64U);
    CompleteMatrixWaveDestination(state, 32U);

    bool rejectedRange = false;
    try
    {
        (void)MatrixRegisterRangeMask(252U, 8U);
    }
    catch (const std::invalid_argument&)
    {
        rejectedRange = true;
    }
    assert(rejectedRange);

    return 0;
}
