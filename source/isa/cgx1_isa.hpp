// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include <cstdint>
#include <stdexcept>

namespace cgx1::isa {

enum class InstructionClass : std::uint8_t
{
    Scalar = 0x0,
    Vector = 0x1,
    Memory = 0x2,
    Control = 0x3,
    SyncAtomic = 0x4,
    Texture = 0x5,
    Matrix = 0x6,
    Ray = 0x7,
    Conversion = 0x8,
    System = 0x9,
    Extended = 0xF
};

struct BaseInstruction
{
    InstructionClass instructionClass;
    std::uint8_t opcode;
    std::uint8_t destination;
    std::uint8_t source0;
    std::uint8_t source1;
};

inline constexpr std::uint32_t EncodeBase(const BaseInstruction& instruction)
{
    return (static_cast<std::uint32_t>(instruction.instructionClass) << 28U)
        | ((static_cast<std::uint32_t>(instruction.opcode) & 0x0FU) << 24U)
        | (static_cast<std::uint32_t>(instruction.destination) << 16U)
        | (static_cast<std::uint32_t>(instruction.source0) << 8U)
        | static_cast<std::uint32_t>(instruction.source1);
}

inline constexpr BaseInstruction DecodeBase(std::uint32_t word)
{
    return BaseInstruction{
        static_cast<InstructionClass>((word >> 28U) & 0x0FU),
        static_cast<std::uint8_t>((word >> 24U) & 0x0FU),
        static_cast<std::uint8_t>((word >> 16U) & 0xFFU),
        static_cast<std::uint8_t>((word >> 8U) & 0xFFU),
        static_cast<std::uint8_t>(word & 0xFFU)
    };
}

inline constexpr bool IsDefinedClass(InstructionClass value)
{
    const auto raw = static_cast<std::uint8_t>(value);
    return raw <= static_cast<std::uint8_t>(InstructionClass::System)
        || value == InstructionClass::Extended;
}

inline constexpr bool IsValidScalarRegister(std::uint8_t index)
{
    return index < 128U;
}

inline constexpr bool IsValidVectorRegister(std::uint8_t)
{
    return true;
}

} // namespace cgx1::isa
