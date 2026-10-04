// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "cgx1_isa.hpp"

#include <array>
#include <cstddef>
#include <cstdint>

namespace cgx1::isa {

using VectorRegister = std::array<std::uint32_t, 32U>;
using VectorRegisterFile = std::array<VectorRegister, 256U>;

enum class VectorInstructionStatus : std::uint8_t
{
    Executed,
    NotVectorInstruction,
    IllegalOpcode
};

namespace detail {

inline constexpr std::uint32_t ArithmeticShiftRight(std::uint32_t value, unsigned amount)
{
    if (amount == 0U)
    {
        return value;
    }

    std::uint32_t result = value >> amount;
    if ((value & 0x80000000U) != 0U)
    {
        result |= 0xffffffffU << (32U - amount);
    }
    return result;
}

} // namespace detail

// This executes the current RTL's provisional INT32 vector subset only. It
// neither assigns semantics to other classes nor advances a wave PC.
inline VectorInstructionStatus ExecuteVectorBaseInstruction(
    std::uint32_t word,
    VectorRegisterFile& registers,
    std::uint32_t active_lane_mask)
{
    const BaseInstruction instruction = DecodeBase(word);
    if (instruction.instructionClass != InstructionClass::Vector)
    {
        return VectorInstructionStatus::NotVectorInstruction;
    }
    if (instruction.opcode > 7U)
    {
        return VectorInstructionStatus::IllegalOpcode;
    }

    // Snapshot both sources so all legal destination aliases see pre-issue state.
    const VectorRegister source0 = registers[instruction.source0];
    const VectorRegister source1 = registers[instruction.source1];
    VectorRegister& destination = registers[instruction.destination];

    for (std::size_t lane = 0; lane < 32U; ++lane)
    {
        if (((active_lane_mask >> lane) & 1U) == 0U)
        {
            continue;
        }

        const std::uint32_t a = source0[lane];
        const std::uint32_t b = source1[lane];
        const unsigned shift = static_cast<unsigned>(b & 0x1fU);
        std::uint32_t result = 0U;
        switch (instruction.opcode)
        {
            case 0U: result = a + b; break;
            case 1U: result = a - b; break;
            case 2U: result = a & b; break;
            case 3U: result = a | b; break;
            case 4U: result = a ^ b; break;
            case 5U: result = a << shift; break;
            case 6U: result = a >> shift; break;
            case 7U: result = detail::ArithmeticShiftRight(a, shift); break;
            default: return VectorInstructionStatus::IllegalOpcode;
        }
        destination[lane] = result;
    }

    return VectorInstructionStatus::Executed;
}

} // namespace cgx1::isa
