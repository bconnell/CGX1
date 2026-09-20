// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_isa.hpp"

#include <cassert>
#include <cstdint>
#include <iostream>
#include <stdexcept>

int main()
{
    using namespace cgx1::isa;

    constexpr BaseInstruction source{
        InstructionClass::Vector,
        0x3U,
        200U,
        17U,
        255U
    };

    constexpr std::uint32_t encoded = EncodeBase(source);
    constexpr BaseInstruction decoded = DecodeBase(encoded);

    static_assert(decoded.instructionClass == InstructionClass::Vector);
    static_assert(decoded.opcode == 0x3U);
    static_assert(decoded.destination == 200U);
    static_assert(decoded.source0 == 17U);
    static_assert(decoded.source1 == 255U);

    static_assert(IsDefinedClass(InstructionClass::Scalar));
    static_assert(IsDefinedClass(InstructionClass::Extended));
    static_assert(!IsDefinedClass(static_cast<InstructionClass>(0xEU)));
    static_assert(IsValidOpcode(15U));
    static_assert(!IsValidOpcode(16U));

    static_assert(IsValidScalarRegister(127U));
    static_assert(!IsValidScalarRegister(128U));
    static_assert(IsValidVectorRegister(255U));
    static_assert(!IsValidVectorRegister(256U));

    bool rejectedInvalidOpcode = false;
    try
    {
        (void)EncodeBase(BaseInstruction{
            InstructionClass::Vector,
            16U,
            0U,
            0U,
            0U
        });
    }
    catch (const std::invalid_argument&)
    {
        rejectedInvalidOpcode = true;
    }
    assert(rejectedInvalidOpcode);

    bool rejectedUndefinedClass = false;
    try
    {
        (void)EncodeBase(BaseInstruction{
            static_cast<InstructionClass>(0xEU),
            0U,
            0U,
            0U,
            0U
        });
    }
    catch (const std::invalid_argument&)
    {
        rejectedUndefinedClass = true;
    }
    assert(rejectedUndefinedClass);

    std::cout << "CGX 1 ISA base encoding checks passed.\n";
    return 0;
}
