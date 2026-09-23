// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include <array>
#include <bit>
#include <cstdint>
#include <iostream>
#include <random>

#define CHECK(x) do { if (!(x)) { std::cerr << "[fail] " #x " line " << __LINE__ << '\n'; return 1; } } while (false)

enum class Op : std::uint8_t { Add, Sub, And, Or, Xor, Shl, Lsr, Asr };

std::uint32_t Alu(Op op, std::uint32_t a, std::uint32_t b)
{
    switch (op)
    {
        case Op::Add: return a + b;
        case Op::Sub: return a - b;
        case Op::And: return a & b;
        case Op::Or: return a | b;
        case Op::Xor: return a ^ b;
        case Op::Shl: return a << (b & 31U);
        case Op::Lsr: return a >> (b & 31U);
        case Op::Asr:
            return std::bit_cast<std::uint32_t>(
                std::bit_cast<std::int32_t>(a) >> (b & 31U));
    }
    return 0U;
}

std::uint32_t Expected(Op op, std::uint32_t a, std::uint32_t b)
{
    switch (op)
    {
        case Op::Add: return static_cast<std::uint32_t>(a + b);
        case Op::Sub: return static_cast<std::uint32_t>(a - b);
        case Op::And: return static_cast<std::uint32_t>(a & b);
        case Op::Or: return static_cast<std::uint32_t>(a | b);
        case Op::Xor: return static_cast<std::uint32_t>(a ^ b);
        case Op::Shl: return static_cast<std::uint32_t>(a << (b & 31U));
        case Op::Lsr: return static_cast<std::uint32_t>(a >> (b & 31U));
        case Op::Asr:
        {
            const auto signedA = std::bit_cast<std::int32_t>(a);
            return std::bit_cast<std::uint32_t>(
                static_cast<std::int32_t>(signedA >> (b & 31U)));
        }
    }
    return 0U;
}

bool Overlap(
    std::uint32_t leftBase,
    std::uint32_t leftCount,
    std::uint32_t rightBase,
    std::uint32_t rightCount)
{
    return leftBase < rightBase + rightCount
        && rightBase < leftBase + leftCount;
}

struct Hazard { bool raw; bool waw; bool war; };

Hazard CheckHazard(
    bool sameWave,
    std::uint32_t d,
    std::uint32_t a,
    std::uint32_t b,
    std::uint32_t source0,
    std::uint32_t source1,
    std::uint32_t vectorDestination,
    bool sourceLocksLive,
    bool destinationLockLive)
{
    if (!sameWave)
        return {};

    Hazard hazard{};

    if (destinationLockLive)
    {
        hazard.raw =
            Overlap(a, 4U, vectorDestination, 1U)
            || Overlap(b, 4U, vectorDestination, 1U)
            || Overlap(d, 8U, vectorDestination, 1U);

        hazard.waw =
            Overlap(d, 8U, vectorDestination, 1U);
    }

    if (sourceLocksLive)
    {
        hazard.war =
            Overlap(d, 8U, source0, 1U)
            || Overlap(d, 8U, source1, 1U);
    }

    return hazard;
}

struct Scheduler { std::uint32_t next = 0U; };

int Select(
    Scheduler& scheduler,
    const std::array<bool, 8>& valid,
    const std::array<bool, 8>& dependencyReady)
{
    for (std::uint32_t offset = 0U; offset < 8U; ++offset)
    {
        const std::uint32_t slot =
            (scheduler.next + offset) % 8U;

        if (valid[slot] && dependencyReady[slot])
        {
            scheduler.next = (slot + 1U) % 8U;
            return static_cast<int>(slot);
        }
    }

    return -1;
}

struct IssueResult { bool matrixAccept; bool vectorAccept; };

IssueResult ArbitrateIssue(
    bool matrixValid,
    bool matrixReady,
    bool matrixServiceWindow,
    bool vectorValid,
    bool vectorReady)
{
    IssueResult result{};
    const bool matrixEligible =
        matrixValid && matrixReady && !matrixServiceWindow;

    if (matrixEligible)
        result.matrixAccept = true;
    else if (vectorValid && vectorReady)
        result.vectorAccept = true;

    return result;
}

int main()
{
    CHECK(Alu(Op::Add, 0xFFFFFFFFU, 1U) == 0U);
    CHECK(Alu(Op::Sub, 0U, 1U) == 0xFFFFFFFFU);
    CHECK(Alu(Op::Asr, 0x80000000U, 1U) == 0xC0000000U);
    CHECK(Alu(Op::Shl, 1U, 33U) == 2U);

    std::mt19937 random(0x51A6E5U);

    for (std::uint32_t iteration = 0U; iteration < 100000U; ++iteration)
    {
        const std::uint32_t a =
            static_cast<std::uint32_t>(random());
        const std::uint32_t b =
            static_cast<std::uint32_t>(random());
        const auto op =
            static_cast<Op>(random() % 8U);

        CHECK(Alu(op, a, b) == Expected(op, a, b));
    }

    const auto directed =
        CheckHazard(true, 32U, 64U, 68U, 32U, 10U, 64U, true, true);
    CHECK(directed.raw);
    CHECK(directed.war);
    CHECK(!directed.waw);

    for (std::uint32_t iteration = 0U; iteration < 100000U; ++iteration)
    {
        const bool sameWave = (random() & 1U) != 0U;
        const bool sourceLive = (random() & 1U) != 0U;
        const bool destinationLive = (random() & 1U) != 0U;

        const auto hazard = CheckHazard(
            sameWave,
            (random() % 32U) * 8U,
            (random() % 32U) * 8U,
            (random() % 64U) * 4U,
            random() % 256U,
            random() % 256U,
            random() % 256U,
            sourceLive,
            destinationLive);

        if (!sameWave)
            CHECK(!hazard.raw && !hazard.waw && !hazard.war);
        if (!destinationLive)
            CHECK(!hazard.raw && !hazard.waw);
        if (!sourceLive)
            CHECK(!hazard.war);
    }

    Scheduler scheduler{};
    std::array<bool, 8> valid{};
    std::array<bool, 8> dependencyReady{};
    valid.fill(true);
    dependencyReady.fill(true);

    for (int iteration = 0; iteration < 16; ++iteration)
        CHECK(Select(scheduler, valid, dependencyReady) == iteration % 8);

    dependencyReady[2] = false;
    scheduler.next = 2U;
    CHECK(Select(scheduler, valid, dependencyReady) == 3);

    for (std::uint32_t iteration = 0U; iteration < 100000U; ++iteration)
    {
        const bool matrixValid = (random() & 1U) != 0U;
        const bool matrixReady = (random() & 1U) != 0U;
        const bool serviceWindow = (random() & 1U) != 0U;
        const bool vectorValid = (random() & 1U) != 0U;
        const bool vectorReady = (random() & 1U) != 0U;

        const auto result = ArbitrateIssue(
            matrixValid,
            matrixReady,
            serviceWindow,
            vectorValid,
            vectorReady);

        CHECK(!(result.matrixAccept && result.vectorAccept));

        if (matrixValid && matrixReady && !serviceWindow)
            CHECK(result.matrixAccept && !result.vectorAccept);
        else if (vectorValid && vectorReady)
            CHECK(!result.matrixAccept && result.vectorAccept);
    }

    std::cout
        << "[pass] vector execution, hazard, issue-arbitration, "
        << "and resident scheduling reference checks passed.\n";
    return 0;
}
