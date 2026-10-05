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

struct Policy
{
    std::uint32_t limit = 4U;
    std::uint32_t burst = 0U;
    bool pending = false;

    bool Allow(bool vector, bool restore) const
    {
        return !(pending && (vector || restore));
    }

    void Tick(bool matrix, bool vector, bool vectorAccepted,
        bool restore, bool restoreAccepted)
    {
        const bool clientPresent = vector || restore;
        const bool progress = vectorAccepted || restoreAccepted;
        if (!clientPresent)
        {
            burst = 0U;
            pending = false;
        }
        else if (pending)
        {
            if (progress)
            {
                burst = 0U;
                pending = false;
            }
        }
        else if (matrix && ++burst >= limit)
        {
            pending = true;
        }
    }
};

int main()
{
    Policy policy;
    for (int cycle = 0; cycle < 4; ++cycle)
    {
        CHECK(policy.Allow(true, false));
        policy.Tick(true, true, false, false, false);
    }
    CHECK(!policy.Allow(true, false));
    for (int cycle = 0; cycle < 100; ++cycle)
    {
        policy.Tick(false, true, false, false, false);
        CHECK(!policy.Allow(true, false));
    }
    policy.Tick(false, true, true, false, false);
    CHECK(policy.Allow(true, false));
    for (int cycle = 0; cycle < 4; ++cycle)
        policy.Tick(true, false, false, true, false);
    CHECK(!policy.Allow(false, true));
    policy.Tick(false, false, false, true, true);
    CHECK(policy.Allow(false, true));

    constexpr std::uint32_t seed = 0xFA17C0DEU;
    std::mt19937 random(seed);
    Policy randomized;
    for (std::uint32_t iteration = 0U; iteration < 100000U; ++iteration)
    {
        const bool vector = (random() & 1U) != 0U;
        const bool restore = (random() & 1U) != 0U;
        const bool vectorAccepted = vector && ((random() & 15U) == 0U);
        const bool restoreAccepted = restore && ((random() & 15U) == 0U);
        const bool matrixAccepted = randomized.Allow(vector, restore)
            && ((random() & 3U) == 0U);
        const std::uint64_t state =
            (static_cast<std::uint64_t>(randomized.pending) << 4U)
            | (static_cast<std::uint64_t>(vector) << 3U)
            | (static_cast<std::uint64_t>(restore) << 2U)
            | (static_cast<std::uint64_t>(vectorAccepted) << 1U)
            | static_cast<std::uint64_t>(restoreAccepted);
        ::cgx1::testing::SetRandomTestFailureContext(
            "ComputeMixedServicePolicyRandomized", seed, iteration, state);

        if (randomized.pending && (vector || restore)
            && !(vectorAccepted || restoreAccepted))
            CHECK(!randomized.Allow(vector, restore));
        randomized.Tick(matrixAccepted, vector, vectorAccepted,
            restore, restoreAccepted);
    }
    ::cgx1::testing::ClearRandomTestFailureContext();

    std::cout << "[pass] compute mixed-service progress policy checks passed.\n";
    return 0;
}
