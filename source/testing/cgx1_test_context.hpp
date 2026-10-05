// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include <cstdint>
#include <iomanip>
#include <ostream>

namespace cgx1::testing {

struct RandomTestFailureContext
{
    const char* testName = nullptr;
    std::uint64_t seed = 0U;
    std::uint64_t iteration = 0U;
    std::uint64_t state = 0U;
};

inline thread_local RandomTestFailureContext gRandomTestFailureContext{};

inline void SetRandomTestFailureContext(
    const char* testName,
    std::uint64_t seed,
    std::uint64_t iteration,
    std::uint64_t state = 0U)
{
    gRandomTestFailureContext = {testName, seed, iteration, state};
}

inline void ClearRandomTestFailureContext()
{
    gRandomTestFailureContext = {};
}

inline void WriteRandomTestFailureContext(std::ostream& output)
{
    const auto& context = gRandomTestFailureContext;
    if (context.testName == nullptr)
        return;

    output << " [random test=" << context.testName
        << " seed=0x" << std::hex << context.seed << std::dec
        << " iteration=" << context.iteration
        << " state=0x" << std::hex << context.state << std::dec << ']';
}

} // namespace cgx1::testing
