// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_isa.hpp"
#include "cgx1_vector_semantics.hpp"
#include "cgx1_vector_stream.hpp"

#include <array>
#include <cassert>
#include <cstdint>
#include <initializer_list>
#include <iostream>
#include <stdexcept>

namespace {

void Require(bool condition, const char* message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}

void TestVectorOpcodeResults()
{
    using namespace cgx1::isa;

    VectorRegisterFile registers{};
    registers[1].fill(0x80000000U);
    registers[2].fill(1U);
    constexpr std::array<std::uint32_t, 8U> expected{
        0x80000001U, 0x7fffffffU, 0x00000000U, 0x80000001U,
        0x80000001U, 0x00000000U, 0x40000000U, 0xc0000000U
    };

    for (std::uint8_t opcode = 0; opcode < expected.size(); ++opcode)
    {
        registers[3].fill(0xdeadbeefU);
        const auto word = EncodeBase(BaseInstruction{
            InstructionClass::Vector, opcode, 3U, 1U, 2U
        });
        Require(ExecuteVectorBaseInstruction(word, registers, 0xffffffffU)
                == VectorInstructionStatus::Executed,
            "supported vector opcode did not execute");
        for (const auto lane : registers[3])
        {
            Require(lane == expected[opcode], "vector opcode produced the wrong lane result");
        }
    }
}

void TestVectorOpcodesUseEachLaneOperands()
{
    using namespace cgx1::isa;

    VectorRegisterFile registers{};
    registers[1].fill(0x80000000U);
    registers[2].fill(1U);
    registers[1][1] = 0x7fffffffU;
    registers[2][1] = 2U;
    registers[1][2] = 0xffffffffU;
    registers[2][2] = 3U;

    constexpr std::array<std::array<std::uint32_t, 3U>, 8U> expected{{
        {{0x80000001U, 0x80000001U, 0x00000002U}},
        {{0x7fffffffU, 0x7ffffffdU, 0xfffffffcU}},
        {{0x00000000U, 0x00000002U, 0x00000003U}},
        {{0x80000001U, 0x7fffffffU, 0xffffffffU}},
        {{0x80000001U, 0x7ffffffdU, 0xfffffffcU}},
        {{0x00000000U, 0xfffffffcU, 0xfffffff8U}},
        {{0x40000000U, 0x1fffffffU, 0x1fffffffU}},
        {{0xc0000000U, 0x1fffffffU, 0xffffffffU}}
    }};

    for (std::uint8_t opcode = 0; opcode < expected.size(); ++opcode)
    {
        const auto word = EncodeBase(BaseInstruction{
            InstructionClass::Vector, opcode, 3U, 1U, 2U
        });
        Require(ExecuteVectorBaseInstruction(word, registers, 0x7U)
                == VectorInstructionStatus::Executed,
            "per-lane vector opcode did not execute");
        for (std::size_t lane = 0; lane < expected[opcode].size(); ++lane)
        {
            Require(registers[3][lane] == expected[opcode][lane],
                "vector opcode did not use lane-local source values");
        }
    }
}

void TestVectorShiftCountsUseFiveBits()
{
    using namespace cgx1::isa;

    VectorRegisterFile registers{};
    registers[1].fill(0x80000001U);
    registers[2].fill(0U);
    for (const std::uint8_t opcode : {5U, 6U, 7U})
    {
        const auto word = EncodeBase(BaseInstruction{
            InstructionClass::Vector, opcode, 3U, 1U, 2U
        });
        Require(ExecuteVectorBaseInstruction(word, registers, 1U)
                == VectorInstructionStatus::Executed,
            "zero-count vector shift did not execute");
        Require(registers[3][0] == 0x80000001U, "zero shift count changed the source value");
    }

    registers[2].fill(63U);
    constexpr std::array<std::uint32_t, 3U> expected{0x80000000U, 0x00000001U, 0xffffffffU};
    for (std::uint8_t opcode = 5U; opcode <= 7U; ++opcode)
    {
        const auto word = EncodeBase(BaseInstruction{
            InstructionClass::Vector, opcode, 3U, 1U, 2U
        });
        Require(ExecuteVectorBaseInstruction(word, registers, 1U)
                == VectorInstructionStatus::Executed,
            "31-count vector shift did not execute");
        Require(registers[3][0] == expected[opcode - 5U],
            "vector shift did not mask the count to five bits or sign extend correctly");
    }
}

void TestVectorMaskAndAliasing()
{
    using namespace cgx1::isa;

    VectorRegisterFile registers{};
    for (std::uint32_t lane = 0; lane < 32U; ++lane)
    {
        registers[1][lane] = 100U + lane;
        registers[2][lane] = 2U;
    }
    const auto before = registers[1];
    const auto word = EncodeBase(BaseInstruction{
        InstructionClass::Vector, 0U, 1U, 1U, 2U
    });
    Require(ExecuteVectorBaseInstruction(word, registers, 0x80000001U)
            == VectorInstructionStatus::Executed,
        "aliased vector add did not execute");
    Require(registers[1][0] == 102U && registers[1][31] == 133U,
        "destination/source aliasing lost the original source values");
    for (std::uint32_t lane = 1; lane < 31U; ++lane)
    {
        Require(registers[1][lane] == before[lane],
            "inactive vector lane destination was modified");
    }

    const auto masked_before = registers[1];
    Require(ExecuteVectorBaseInstruction(word, registers, 0U)
            == VectorInstructionStatus::Executed,
        "empty-mask vector add did not complete");
    Require(registers[1] == masked_before, "empty active mask modified vector state");
}

void TestVectorAdditionAndSubtractionWrapAt32Bits()
{
    using namespace cgx1::isa;

    VectorRegisterFile registers{};
    registers[1].fill(0xffffffffU);
    registers[2].fill(1U);
    auto word = EncodeBase(BaseInstruction{
        InstructionClass::Vector, 0U, 3U, 1U, 2U
    });
    Require(ExecuteVectorBaseInstruction(word, registers, 1U)
            == VectorInstructionStatus::Executed,
        "wrapping vector addition did not execute");
    Require(registers[3][0] == 0U, "vector addition did not wrap at 32 bits");

    registers[1].fill(0U);
    word = EncodeBase(BaseInstruction{
        InstructionClass::Vector, 1U, 3U, 1U, 2U
    });
    Require(ExecuteVectorBaseInstruction(word, registers, 1U)
            == VectorInstructionStatus::Executed,
        "wrapping vector subtraction did not execute");
    Require(registers[3][0] == 0xffffffffU, "vector subtraction did not wrap at 32 bits");
}

void TestVectorStreamExecutesDependentInstructionsAndAdvancesPC()
{
    using namespace cgx1::isa;

    constexpr std::uint64_t image_base = 0x1000U;
    std::array<std::uint32_t, 2U> words{
        EncodeBase(BaseInstruction{InstructionClass::Vector, 0U, 3U, 1U, 2U}),
        EncodeBase(BaseInstruction{InstructionClass::Vector, 5U, 4U, 3U, 2U})
    };
    VectorRegisterFile registers{};
    registers[1].fill(2U);
    registers[2].fill(3U);
    std::uint64_t pc = image_base;

    Require(StepVectorInstructionStream(words, image_base, pc, registers, 0xffffffffU)
            == VectorStreamStepStatus::Executed,
        "first vector stream instruction did not execute");
    Require(pc == image_base + 4U && registers[3][0] == 5U,
        "first vector stream instruction did not update destination and PC");
    Require(StepVectorInstructionStream(words, image_base, pc, registers, 0xffffffffU)
            == VectorStreamStepStatus::Executed,
        "dependent vector stream instruction did not execute");
    Require(pc == image_base + 8U && registers[4][0] == 40U,
        "dependent instruction did not observe prior writeback or advance PC");
}

void TestVectorStreamFetchFaultLeavesStateUnchanged()
{
    using namespace cgx1::isa;

    constexpr std::uint64_t image_base = 0x2000U;
    const std::array<std::uint32_t, 1U> words{
        EncodeBase(BaseInstruction{InstructionClass::Vector, 0U, 3U, 1U, 2U})
    };
    VectorRegisterFile registers{};
    registers[1].fill(9U);
    registers[2].fill(7U);
    const auto before = registers;

    for (const std::uint64_t invalid_pc : {
             image_base + 2U,
             image_base - 4U,
             image_base + 4U,
             (std::uint64_t{1U} << 57U)})
    {
        std::uint64_t pc = invalid_pc;
        Require(StepVectorInstructionStream(words, image_base, pc, registers, 0xffffffffU)
                == VectorStreamStepStatus::FetchFault,
            "invalid vector stream PC did not report a fetch fault");
        Require(pc == invalid_pc && registers == before,
            "vector fetch fault modified PC or VGPR state");
    }
}

void TestVectorStreamInvalidImageBaseLeavesStateUnchanged()
{
    using namespace cgx1::isa;

    const std::array<std::uint32_t, 1U> words{
        EncodeBase(BaseInstruction{InstructionClass::Vector, 0U, 3U, 1U, 2U})
    };
    VectorRegisterFile registers{};
    registers[1].fill(9U);
    registers[2].fill(7U);
    const auto before = registers;
    const std::uint64_t address_limit = std::uint64_t{1U} << 57U;

    for (const std::uint64_t invalid_base : std::array<std::uint64_t, 2U>{2U, address_limit})
    {
        std::uint64_t pc = 0U;
        Require(StepVectorInstructionStream(words, invalid_base, pc, registers, 0xffffffffU)
                == VectorStreamStepStatus::FetchFault,
            "invalid vector stream image base did not report a fetch fault");
        Require(pc == 0U && registers == before,
            "invalid image base modified PC or VGPR state");
    }
}

void TestVectorStreamUnsupportedWordsDoNotAdvancePC()
{
    using namespace cgx1::isa;

    constexpr std::uint64_t image_base = 0x3000U;
    const std::array<std::uint32_t, 2U> words{
        EncodeBase(BaseInstruction{InstructionClass::Memory, 0U, 4U, 4U, 4U}),
        EncodeBase(BaseInstruction{InstructionClass::Vector, 8U, 4U, 4U, 4U})
    };
    VectorRegisterFile registers{};
    registers[4].fill(0x12345678U);
    const auto before = registers;

    std::uint64_t pc = image_base;
    Require(StepVectorInstructionStream(words, image_base, pc, registers, 0xffffffffU)
            == VectorStreamStepStatus::NotVectorInstruction,
        "non-vector instruction was not left for another class handler");
    Require(pc == image_base && registers == before,
        "non-vector instruction changed stream or VGPR state");

    pc = image_base + 4U;
    Require(StepVectorInstructionStream(words, image_base, pc, registers, 0xffffffffU)
            == VectorStreamStepStatus::IllegalOpcode,
        "reserved vector opcode did not report an instruction fault");
    Require(pc == image_base + 4U && registers == before,
        "illegal vector opcode changed stream or VGPR state");
}

void TestVectorStreamFinalWordAnd57BitBoundary()
{
    using namespace cgx1::isa;

    const std::array<std::uint32_t, 1U> words{
        EncodeBase(BaseInstruction{InstructionClass::Vector, 0U, 3U, 1U, 2U})
    };
    VectorRegisterFile registers{};
    registers[1].fill(1U);
    registers[2].fill(2U);
    const std::uint64_t address_limit = std::uint64_t{1U} << 57U;
    std::uint64_t pc = address_limit - 4U;

    Require(StepVectorInstructionStream(words, pc, pc, registers, 1U)
            == VectorStreamStepStatus::Executed,
        "last aligned 57-bit instruction address did not execute");
    Require(pc == address_limit && registers[3][0] == 3U,
        "last instruction did not preserve the next sequential PC");
    const auto after_final = registers;
    Require(StepVectorInstructionStream(words, address_limit - 4U, pc, registers, 1U)
            == VectorStreamStepStatus::FetchFault,
        "next fetch beyond the 57-bit address space did not fault");
    Require(pc == address_limit && registers == after_final,
        "out-of-range next fetch modified state");
}

void TestUnsupportedVectorInstructionsDoNotMutateState()
{
    using namespace cgx1::isa;

    VectorRegisterFile registers{};
    registers[4].fill(0x12345678U);
    const auto before = registers;
    const auto illegal_vector = EncodeBase(BaseInstruction{
        InstructionClass::Vector, 8U, 4U, 4U, 4U
    });
    Require(ExecuteVectorBaseInstruction(illegal_vector, registers, 0xffffffffU)
            == VectorInstructionStatus::IllegalOpcode,
        "reserved vector opcode was not rejected");
    Require(registers == before, "illegal vector opcode partially modified vector state");

    const auto other_class = EncodeBase(BaseInstruction{
        InstructionClass::Memory, 0U, 4U, 4U, 4U
    });
    Require(ExecuteVectorBaseInstruction(other_class, registers, 0xffffffffU)
            == VectorInstructionStatus::NotVectorInstruction,
        "non-vector instruction was consumed by vector semantics");
    Require(registers == before, "non-vector instruction modified vector state");
}

} // namespace

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

    TestVectorOpcodeResults();
    TestVectorOpcodesUseEachLaneOperands();
    TestVectorShiftCountsUseFiveBits();
    TestVectorMaskAndAliasing();
    TestVectorAdditionAndSubtractionWrapAt32Bits();
    TestVectorStreamExecutesDependentInstructionsAndAdvancesPC();
    TestVectorStreamFetchFaultLeavesStateUnchanged();
    TestVectorStreamInvalidImageBaseLeavesStateUnchanged();
    TestVectorStreamUnsupportedWordsDoNotAdvancePC();
    TestVectorStreamFinalWordAnd57BitBoundary();
    TestUnsupportedVectorInstructionsDoNotMutateState();

    std::cout << "CGX 1 ISA base encoding and provisional INT32 vector semantics checks passed.\n";
    return 0;
}
