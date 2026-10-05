// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_context.hpp"

#include <array>
#include <bitset>
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

struct Hazards
{
    bool raw;
    bool waw;
    bool war;

    bool Ready() const { return !(raw || waw || war); }
};

Hazards Dependencies(
    const std::bitset<256>& sourcePending,
    const std::bitset<256>& destinationPending,
    std::uint8_t source0,
    std::uint8_t source1,
    std::uint8_t destination)
{
    return {
        destinationPending.test(source0) || destinationPending.test(source1),
        destinationPending.test(destination),
        sourcePending.test(destination)
    };
}

struct Scheduler
{
    std::uint32_t next = 0U;
};

int Pick(
    Scheduler& scheduler,
    const std::array<bool, 8>& valid,
    const std::array<bool, 8>& ready,
    bool accept)
{
    for (std::uint32_t offset = 0U; offset < valid.size(); ++offset)
    {
        const auto index = (scheduler.next + offset) % valid.size();
        if (valid[index] && ready[index])
        {
            if (accept)
                scheduler.next = (index + 1U) % valid.size();
            return static_cast<int>(index);
        }
    }
    return -1;
}

int main()
{
    std::bitset<256> sourcePending;
    std::bitset<256> destinationPending;
    sourcePending.set(64U);
    destinationPending.set(32U);
    CHECK(Dependencies(sourcePending, destinationPending, 32U, 7U, 9U).raw);
    CHECK(Dependencies(sourcePending, destinationPending, 7U, 8U, 64U).war);

    std::array<bool, 8> valid{};
    std::array<bool, 8> ready{};
    valid[0] = true;
    valid[5] = true;
    ready[5] = true;
    Scheduler scheduler{};
    CHECK(Pick(scheduler, valid, ready, false) == 5);
    CHECK(scheduler.next == 0U);
    CHECK(Pick(scheduler, valid, ready, true) == 5);
    CHECK(scheduler.next == 6U);

    constexpr std::uint32_t seed = 0x5C4ED123U;
    std::mt19937 random(seed);
    for (std::uint32_t iteration = 0U; iteration < 100000U; ++iteration)
    {
        sourcePending.reset();
        destinationPending.reset();
        for (std::uint32_t bit = 0U; bit < 256U; ++bit)
        {
            if ((random() & 31U) == 0U)
                sourcePending.set(bit);
            if ((random() & 31U) == 0U)
                destinationPending.set(bit);
        }
        const auto source0 = static_cast<std::uint8_t>(random());
        const auto source1 = static_cast<std::uint8_t>(random());
        const auto destination = static_cast<std::uint8_t>(random());
        const std::uint64_t state =
            (static_cast<std::uint64_t>(source0) << 16U)
            | (static_cast<std::uint64_t>(source1) << 8U)
            | destination;
        ::cgx1::testing::SetRandomTestFailureContext(
            "VectorDependencyRandomized", seed, iteration, state);
        const auto hazards = Dependencies(sourcePending,
            destinationPending, source0, source1, destination);
        CHECK(hazards.raw == (destinationPending.test(source0)
            || destinationPending.test(source1)));
        CHECK(hazards.waw == destinationPending.test(destination));
        CHECK(hazards.war == sourcePending.test(destination));
    }
    ::cgx1::testing::ClearRandomTestFailureContext();

    std::cout << "[pass] per-wave vector dependency scheduler checks passed.\n";
    return 0;
}
