// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_matrix_banking.hpp"

#include <array>
#include <cassert>
#include <cstdint>

int main()
{
    using namespace cgx1::matrix;

    static_assert(kMatrixRegisterBankClasses == 8U);
    static_assert(kMatrixRegisterBankMask == 7U);
    static_assert(kMatrixSourceABaseModulo == 0U);
    static_assert(kMatrixSourceBBaseModulo == 4U);
    static_assert(kMatrixAliasedSourceBroadcastAllowed);

    for (std::uint32_t reg = 0U; reg < 256U; ++reg)
    {
        const auto r = static_cast<std::uint8_t>(reg);
        assert(MatrixRegisterBank(r) == reg % 8U);
        assert(MatrixRegisterBankRow(r) == reg / 8U);
    }

    // Canonical non-aliased placement uses opposite 4-register halves
    // of the eight bank classes.
    for (std::uint32_t offset = 0U; offset < 4U; ++offset)
    {
        assert(MatrixRegisterBank(static_cast<std::uint8_t>(64U + offset))
            == offset);
        assert(MatrixRegisterBank(static_cast<std::uint8_t>(68U + offset))
            == offset + 4U);
    }

    // C/D capture always reads adjacent register offsets, which land in
    // distinct modulo-8 bank classes.
    for (std::uint32_t pair = 0U; pair < 4U; ++pair)
    {
        const auto r0 = static_cast<std::uint8_t>(32U + pair * 2U);
        const auto r1 = static_cast<std::uint8_t>(r0 + 1U);
        assert(MatrixRegisterBank(r0) != MatrixRegisterBank(r1));
    }

    std::uint32_t validLayouts = 0U;
    for (std::uint32_t d = 0U; d < 256U; ++d)
    {
        for (std::uint32_t a = 0U; a < 256U; ++a)
        {
            for (std::uint32_t b = 0U; b < 256U; ++b)
            {
                const auto db = static_cast<std::uint8_t>(d);
                const auto ab = static_cast<std::uint8_t>(a);
                const auto bb = static_cast<std::uint8_t>(b);

                if (!IsValidMatrixRegisterLayout(db, ab, bb))
                {
                    continue;
                }

                ++validLayouts;
                assert(MatrixBankClassPlacementMatchesContract(ab, bb));
                assert(MatrixRegisterLayoutBankCompatible(db, ab, bb));

                for (std::uint32_t cycle = 0U;
                     cycle < kMatrixRegisterCaptureCycles;
                     ++cycle)
                {
                    const MatrixCaptureCycle schedule =
                        MatrixCaptureSchedule(cycle, ab, bb, db);

                    if (schedule.read0.architecturalRegister
                        == schedule.read1.architecturalRegister)
                    {
                        assert(cycle < 4U);
                        assert(ab == bb);
                    }
                    else
                    {
                        assert(MatrixRegisterBank(
                                   schedule.read0.architecturalRegister)
                            != MatrixRegisterBank(
                                   schedule.read1.architecturalRegister));
                    }
                }
            }
        }
    }

    assert(validLayouts > 0U);

    // A source base in bank class 4 is deliberately rejected even though
    // it is 4-register aligned. This prevents a general two-read bank conflict
    // from being hidden behind the older alignment-only rule.
    static_assert(!IsValidMatrixRegisterLayout(32U, 68U, 72U));

    // B uses bank class 4 when distinct from A.
    static_assert(IsValidMatrixRegisterLayout(32U, 64U, 68U));

    // Exact A/B aliasing remains legal because a single physical read can
    // be broadcast into both deterministic staging permutations.
    static_assert(IsValidMatrixRegisterLayout(32U, 64U, 64U));
    static_assert(MatrixReadPairBankCompatible(64U, 64U));

    // Distinct registers in the same bank class are not compatible with
    // the single-access-per-bank-class target.
    static_assert(!MatrixReadPairBankCompatible(64U, 72U));

    return 0;
}
