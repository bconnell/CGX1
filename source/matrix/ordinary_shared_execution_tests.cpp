// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_context.hpp"

#include <cstdint>
#include <iostream>
#include <random>

#define CHECK(expression) \
    do { \
        if (!(expression)) { \
            std::cerr << "[fail] " #expression " line " << __LINE__; \
            ::cgx1::testing::WriteRandomTestFailureContext(std::cerr); \
            std::cerr << '\n'; \
            return 1; \
        } \
    } while (false)

struct Address
{
    std::uint32_t row;
    std::uint32_t bank;
    bool valid;
};

Address Map(
    std::uint32_t base,
    std::uint32_t registerCount,
    std::uint32_t reg,
    std::uint32_t rows)
{
    const auto row = base + reg / 8U;
    return {row, reg % 8U, registerCount > 0U && reg < registerCount && row < rows};
}

enum class Mode { Invalid, Alias, Parallel, Split };

Mode Classify(
    const Address& a,
    const Address& b,
    std::uint32_t regA,
    std::uint32_t regB)
{
    if (!a.valid || !b.valid)
        return Mode::Invalid;
    if (regA == regB && a.row == b.row && a.bank == b.bank)
        return Mode::Alias;
    if (a.bank == b.bank)
        return Mode::Split;
    return Mode::Parallel;
}

struct Arbiter
{
    bool preferRestore = false;
};

enum class Grant { None, MatrixRead, MatrixWrite, OrdinaryRead, OrdinaryWrite, Restore };

Grant Pick(
    Arbiter& state,
    bool matrixRead,
    bool matrixWrite,
    bool ordinaryRead,
    bool ordinaryWrite,
    bool restore)
{
    if (matrixRead && matrixWrite)
        return Grant::None;
    if (matrixRead)
        return Grant::MatrixRead;
    if (matrixWrite)
        return Grant::MatrixWrite;
    const bool ordinary = ordinaryRead || ordinaryWrite;
    if (ordinary && restore)
    {
        const auto grant = state.preferRestore
            ? Grant::Restore
            : (ordinaryRead ? Grant::OrdinaryRead : Grant::OrdinaryWrite);
        state.preferRestore = !state.preferRestore;
        return grant;
    }
    if (ordinaryRead)
        return Grant::OrdinaryRead;
    if (ordinaryWrite)
        return Grant::OrdinaryWrite;
    if (restore)
        return Grant::Restore;
    return Grant::None;
}

bool ReleaseSafe(
    bool quiescent,
    bool matrixBusy,
    bool vectorBusy,
    bool matrixReadFlight,
    bool vectorReadFlight,
    bool splitAccess,
    bool restore)
{
    return quiescent && !matrixBusy && !vectorBusy && !matrixReadFlight
        && !vectorReadFlight && !splitAccess && !restore;
}

int main()
{
    const auto a = Map(3U, 9U, 8U, 64U);
    const auto b = Map(3U, 9U, 9U, 64U);
    CHECK(a.valid && !b.valid && a.row == 4U && a.bank == 0U);

    const auto x = Map(2U, 72U, 64U, 128U);
    const auto y = Map(2U, 72U, 56U, 128U);
    CHECK(Classify(x, y, 64U, 56U) == Mode::Split);
    CHECK(Classify(x, x, 64U, 64U) == Mode::Alias);

    Arbiter arbitration{};
    CHECK(Pick(arbitration, true, false, true, false, true) == Grant::MatrixRead);
    int ordinaryGrants = 0;
    int restoreGrants = 0;
    for (int cycle = 0; cycle < 1000; ++cycle)
    {
        const auto grant = Pick(arbitration, false, false, true, false, true);
        ordinaryGrants += grant == Grant::OrdinaryRead;
        restoreGrants += grant == Grant::Restore;
    }
    CHECK(ordinaryGrants == 500 && restoreGrants == 500);
    CHECK(!ReleaseSafe(true, true, false, false, false, false, false));
    CHECK(ReleaseSafe(true, false, false, false, false, false, false));

    constexpr std::uint32_t seed = 0xC6A12026U;
    std::mt19937 random(seed);
    for (std::uint32_t iteration = 0U; iteration < 100000U; ++iteration)
    {
        const auto count = 1U + (random() % 256U);
        const auto base = random() % 64U;
        const auto regA = random() % 256U;
        const auto regB = random() % 256U;
        const auto first = Map(base, count, regA, 128U);
        const auto second = Map(base, count, regB, 128U);
        const auto mode = Classify(first, second, regA, regB);
        const std::uint64_t state =
            (static_cast<std::uint64_t>(count) << 32U)
            | (static_cast<std::uint64_t>(base) << 24U)
            | (static_cast<std::uint64_t>(regA) << 12U)
            | regB;
        ::cgx1::testing::SetRandomTestFailureContext(
            "OrdinarySharedVgprMappingRandomized", seed, iteration, state);

        if (regA >= count || regB >= count || first.row >= 128U || second.row >= 128U)
            CHECK(mode == Mode::Invalid);
        else if (regA == regB)
            CHECK(mode == Mode::Alias);
        else if ((regA % 8U) == (regB % 8U))
            CHECK(mode == Mode::Split);
        else
            CHECK(mode == Mode::Parallel);
    }
    ::cgx1::testing::ClearRandomTestFailureContext();

    std::cout << "[pass] ordinary/shared pooled VGPR reference checks passed.\n";
    return 0;
}
