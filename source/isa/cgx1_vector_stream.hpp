// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "cgx1_vector_semantics.hpp"

#include <cstddef>
#include <cstdint>
#include <span>

namespace cgx1::isa {

enum class VectorStreamStepStatus : std::uint8_t
{
    Executed,
    FetchFault,
    NotVectorInstruction,
    IllegalOpcode
};

// Fetches and executes one base word from an immutable instruction image.
// This is a bounded software reference; it does not model RTL fetch timing.
inline VectorStreamStepStatus StepVectorInstructionStream(
    std::span<const std::uint32_t> words,
    std::uint64_t image_base,
    std::uint64_t& pc,
    VectorRegisterFile& registers,
    std::uint32_t active_lane_mask)
{
    constexpr std::uint64_t address_limit = std::uint64_t{1U} << 57U;
    constexpr std::uint64_t instruction_bytes = sizeof(std::uint32_t);

    if ((image_base & (instruction_bytes - 1U)) != 0U
        || image_base >= address_limit
        || (pc & (instruction_bytes - 1U)) != 0U
        || pc >= address_limit
        || pc < image_base)
    {
        return VectorStreamStepStatus::FetchFault;
    }

    const std::uint64_t word_index = (pc - image_base) / instruction_bytes;
    if (word_index >= words.size())
    {
        return VectorStreamStepStatus::FetchFault;
    }

    switch (ExecuteVectorBaseInstruction(
        words[static_cast<std::size_t>(word_index)], registers, active_lane_mask))
    {
        case VectorInstructionStatus::Executed:
            pc += instruction_bytes;
            return VectorStreamStepStatus::Executed;
        case VectorInstructionStatus::NotVectorInstruction:
            return VectorStreamStepStatus::NotVectorInstruction;
        case VectorInstructionStatus::IllegalOpcode:
            return VectorStreamStepStatus::IllegalOpcode;
    }

    return VectorStreamStepStatus::IllegalOpcode;
}

} // namespace cgx1::isa
