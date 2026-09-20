// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "cgx1_matrix.hpp"
#include "../isa/cgx1_isa.hpp"

#include <array>
#include <bit>
#include <cmath>
#include <cstdint>
#include <stdexcept>

namespace cgx1::matrix {

inline constexpr std::uint32_t kMatrixTileM = 16U;
inline constexpr std::uint32_t kMatrixTileN = 16U;
inline constexpr std::uint32_t kFp16Bf16TileK = 16U;
inline constexpr std::uint32_t kFp8Int8TileK = 32U;

inline constexpr std::uint32_t kMatrixSourceRegistersPerLane = 4U;
inline constexpr std::uint32_t kMatrixAccumulatorRegistersPerLane = 8U;
inline constexpr std::uint32_t kMatrixFragmentReadBytesPerWave = 2048U;
inline constexpr std::uint32_t kMatrixFragmentWriteBytesPerWave = 1024U;

inline constexpr std::uint32_t kMatrixRegisterCaptureCycles = 8U;
inline constexpr std::uint32_t kMatrixExecutionCycles = 16U;
inline constexpr std::uint32_t kMatrixWritebackCycles = 8U;
inline constexpr std::uint32_t kMatrixIssueIntervalCycles = 16U;
inline constexpr std::uint32_t kMatrixResultLatencyCycles = 33U;
inline constexpr std::uint32_t kMatrixInputStagingSlots = 1U;
inline constexpr std::uint32_t kMatrixOutputStagingSlots = 1U;
inline constexpr std::uint32_t kMatrixWaveRegisterReadsPerCaptureCycle = 2U;
inline constexpr std::uint32_t kMatrixWaveRegisterWritesPerWritebackCycle = 1U;

inline constexpr bool kMatrixFullWaveActiveRequired = true;
inline constexpr bool kMatrixInstructionUsesExtensionWord = false;
inline constexpr bool kMatrixTimingFeasibilityValidated = false;

enum class MatrixOpcode : std::uint8_t
{
    Fp16Fp32 = 0x0,
    Bf16Fp32 = 0x1,
    E4M3E4M3Fp32 = 0x2,
    E4M3E5M2Fp32 = 0x3,
    E5M2E4M3Fp32 = 0x4,
    E5M2E5M2Fp32 = 0x5,
    Int8Int32 = 0x6
};

struct MatrixShape
{
    std::uint16_t m;
    std::uint16_t n;
    std::uint16_t k;
    std::uint8_t inputBits;
};

struct MatrixCoordinate
{
    std::uint16_t row;
    std::uint16_t column;
};

struct PackedElementLocation
{
    std::uint8_t registerOffset;
    std::uint8_t bitOffset;
};

struct RegisterSpan
{
    std::uint16_t base;
    std::uint16_t count;
};

inline constexpr bool IsDefinedMatrixOpcode(std::uint8_t opcode)
{
    return opcode <= static_cast<std::uint8_t>(MatrixOpcode::Int8Int32);
}

inline constexpr bool IsEightBitOpcode(MatrixOpcode opcode)
{
    return opcode == MatrixOpcode::E4M3E4M3Fp32
        || opcode == MatrixOpcode::E4M3E5M2Fp32
        || opcode == MatrixOpcode::E5M2E4M3Fp32
        || opcode == MatrixOpcode::E5M2E5M2Fp32
        || opcode == MatrixOpcode::Int8Int32;
}

inline constexpr MatrixShape ShapeForOpcode(MatrixOpcode opcode)
{
    if (!IsDefinedMatrixOpcode(static_cast<std::uint8_t>(opcode)))
    {
        throw std::invalid_argument("undefined matrix opcode");
    }

    return MatrixShape{
        static_cast<std::uint16_t>(kMatrixTileM),
        static_cast<std::uint16_t>(kMatrixTileN),
        static_cast<std::uint16_t>(IsEightBitOpcode(opcode) ? kFp8Int8TileK : kFp16Bf16TileK),
        static_cast<std::uint8_t>(IsEightBitOpcode(opcode) ? 8U : 16U)
    };
}

inline constexpr MatrixProfile ProfileForOpcode(MatrixOpcode opcode)
{
    switch (opcode)
    {
        case MatrixOpcode::Fp16Fp32:
            return MatrixProfile{
                MatrixDataType::Fp16, MatrixDataType::Fp16,
                MatrixDataType::Fp32, MatrixDataType::Fp32};
        case MatrixOpcode::Bf16Fp32:
            return MatrixProfile{
                MatrixDataType::Bf16, MatrixDataType::Bf16,
                MatrixDataType::Fp32, MatrixDataType::Fp32};
        case MatrixOpcode::E4M3E4M3Fp32:
            return MatrixProfile{
                MatrixDataType::Fp8E4M3, MatrixDataType::Fp8E4M3,
                MatrixDataType::Fp32, MatrixDataType::Fp32};
        case MatrixOpcode::E4M3E5M2Fp32:
            return MatrixProfile{
                MatrixDataType::Fp8E4M3, MatrixDataType::Fp8E5M2,
                MatrixDataType::Fp32, MatrixDataType::Fp32};
        case MatrixOpcode::E5M2E4M3Fp32:
            return MatrixProfile{
                MatrixDataType::Fp8E5M2, MatrixDataType::Fp8E4M3,
                MatrixDataType::Fp32, MatrixDataType::Fp32};
        case MatrixOpcode::E5M2E5M2Fp32:
            return MatrixProfile{
                MatrixDataType::Fp8E5M2, MatrixDataType::Fp8E5M2,
                MatrixDataType::Fp32, MatrixDataType::Fp32};
        case MatrixOpcode::Int8Int32:
            return MatrixProfile{
                MatrixDataType::Int8, MatrixDataType::Int8,
                MatrixDataType::Int32, MatrixDataType::Int32};
        default:
            throw std::invalid_argument("undefined matrix opcode");
    }
}

inline constexpr std::uint32_t InputElementsPerLane(MatrixOpcode opcode)
{
    return IsEightBitOpcode(opcode) ? 16U : 8U;
}

inline constexpr MatrixCoordinate OutputElementCoordinate(std::uint32_t lane, std::uint32_t element)
{
    if (lane >= kNativeWaveSize || element >= kMatrixAccumulatorRegistersPerLane)
    {
        throw std::invalid_argument("matrix output fragment coordinate is out of range");
    }

    return MatrixCoordinate{
        static_cast<std::uint16_t>(lane / 2U),
        static_cast<std::uint16_t>((lane % 2U) * 8U + element)
    };
}

inline constexpr MatrixCoordinate InputAElementCoordinate(
    MatrixOpcode opcode,
    std::uint32_t lane,
    std::uint32_t element)
{
    const std::uint32_t elements = InputElementsPerLane(opcode);
    if (lane >= kNativeWaveSize || element >= elements)
    {
        throw std::invalid_argument("matrix A fragment coordinate is out of range");
    }

    const std::uint32_t halfWidth = IsEightBitOpcode(opcode) ? 16U : 8U;
    return MatrixCoordinate{
        static_cast<std::uint16_t>(lane / 2U),
        static_cast<std::uint16_t>((lane % 2U) * halfWidth + element)
    };
}

inline constexpr MatrixCoordinate InputBElementCoordinate(
    MatrixOpcode opcode,
    std::uint32_t lane,
    std::uint32_t element)
{
    const std::uint32_t elements = InputElementsPerLane(opcode);
    if (lane >= kNativeWaveSize || element >= elements)
    {
        throw std::invalid_argument("matrix B fragment coordinate is out of range");
    }

    if (IsEightBitOpcode(opcode))
    {
        return MatrixCoordinate{
            static_cast<std::uint16_t>(lane),
            static_cast<std::uint16_t>(element)
        };
    }

    return MatrixCoordinate{
        static_cast<std::uint16_t>(lane / 2U),
        static_cast<std::uint16_t>((lane % 2U) * 8U + element)
    };
}

inline constexpr PackedElementLocation InputPackedLocation(MatrixOpcode opcode, std::uint32_t element)
{
    const std::uint32_t elements = InputElementsPerLane(opcode);
    if (element >= elements)
    {
        throw std::invalid_argument("matrix packed input element is out of range");
    }

    const std::uint32_t elementsPerRegister = IsEightBitOpcode(opcode) ? 4U : 2U;
    const std::uint32_t bitsPerElement = IsEightBitOpcode(opcode) ? 8U : 16U;
    return PackedElementLocation{
        static_cast<std::uint8_t>(element / elementsPerRegister),
        static_cast<std::uint8_t>((element % elementsPerRegister) * bitsPerElement)
    };
}

inline constexpr bool SpansOverlap(RegisterSpan left, RegisterSpan right)
{
    const std::uint32_t leftEnd = static_cast<std::uint32_t>(left.base) + left.count;
    const std::uint32_t rightEnd = static_cast<std::uint32_t>(right.base) + right.count;
    return static_cast<std::uint32_t>(left.base) < rightEnd
        && static_cast<std::uint32_t>(right.base) < leftEnd;
}

inline constexpr bool SpanFitsVectorFile(RegisterSpan span)
{
    return span.count > 0U
        && static_cast<std::uint32_t>(span.base) + span.count <= 256U;
}

inline constexpr bool IsValidMatrixRegisterLayout(
    std::uint8_t destinationBase,
    std::uint8_t sourceABase,
    std::uint8_t sourceBBase)
{
    const RegisterSpan destination{destinationBase, kMatrixAccumulatorRegistersPerLane};
    const RegisterSpan sourceA{sourceABase, kMatrixSourceRegistersPerLane};
    const RegisterSpan sourceB{sourceBBase, kMatrixSourceRegistersPerLane};

    return (destinationBase % 8U) == 0U
        && (sourceABase % 4U) == 0U
        && (sourceBBase % 4U) == 0U
        && SpanFitsVectorFile(destination)
        && SpanFitsVectorFile(sourceA)
        && SpanFitsVectorFile(sourceB)
        && !SpansOverlap(destination, sourceA)
        && !SpansOverlap(destination, sourceB);
}

inline constexpr bool IsValidMatrixInstruction(const isa::BaseInstruction& instruction)
{
    return instruction.instructionClass == isa::InstructionClass::Matrix
        && IsDefinedMatrixOpcode(instruction.opcode)
        && IsValidMatrixRegisterLayout(
            instruction.destination,
            instruction.source0,
            instruction.source1);
}

inline constexpr std::uint32_t DenseArithmeticOperations(MatrixOpcode opcode)
{
    const MatrixShape shape = ShapeForOpcode(opcode);
    return 2U
        * static_cast<std::uint32_t>(shape.m)
        * static_cast<std::uint32_t>(shape.n)
        * static_cast<std::uint32_t>(shape.k);
}

inline constexpr std::uint32_t DenseOperationsPerEngineCycle(MatrixOpcode opcode)
{
    return DenseArithmeticOperations(opcode) / kMatrixIssueIntervalCycles;
}

inline double DenseDeviceTeraOperations(
    MatrixOpcode opcode,
    double clockGhz,
    std::uint32_t computeUnits = 200U)
{
    if (clockGhz <= 0.0 || computeUnits == 0U)
    {
        throw std::invalid_argument("matrix throughput inputs must be positive");
    }

    return static_cast<double>(DenseOperationsPerEngineCycle(opcode))
        * static_cast<double>(kMatrixEnginesPerComputeUnit)
        * static_cast<double>(computeUnits)
        * clockGhz
        / 1000.0;
}

inline float ReferencePhysicalFp16Bf16Cell(
    const std::array<float, kFp16Bf16TileK>& a,
    const std::array<float, kFp16Bf16TileK>& b,
    float accumulator)
{
    float result = accumulator;
    for (std::uint32_t k = 0U; k < kFp16Bf16TileK; ++k)
    {
        result = ReferenceFp32Fma(a[k], b[k], result);
    }
    return result;
}

inline float ReferencePhysicalFp8Cell(
    const std::array<float, kFp8Int8TileK>& a,
    const std::array<float, kFp8Int8TileK>& b,
    float accumulator)
{
    float even = accumulator;
    float odd = 0.0F;

    for (std::uint32_t pair = 0U; pair < kMatrixExecutionCycles; ++pair)
    {
        even = ReferenceFp32Fma(a[pair * 2U], b[pair * 2U], even);
        odd = ReferenceFp32Fma(a[pair * 2U + 1U], b[pair * 2U + 1U], odd);
    }

    return static_cast<float>(even + odd);
}

inline std::int32_t AddInt32Modulo(std::int32_t left, std::int32_t right)
{
    const std::uint32_t leftBits = std::bit_cast<std::uint32_t>(left);
    const std::uint32_t rightBits = std::bit_cast<std::uint32_t>(right);
    return std::bit_cast<std::int32_t>(leftBits + rightBits);
}

inline std::int32_t ReferencePhysicalInt8Cell(
    const std::array<std::int8_t, kFp8Int8TileK>& a,
    const std::array<std::int8_t, kFp8Int8TileK>& b,
    std::int32_t accumulator)
{
    std::int32_t even = accumulator;
    std::int32_t odd = 0;

    for (std::uint32_t pair = 0U; pair < kMatrixExecutionCycles; ++pair)
    {
        even = ReferenceInt8Mac(a[pair * 2U], b[pair * 2U], even);
        odd = ReferenceInt8Mac(a[pair * 2U + 1U], b[pair * 2U + 1U], odd);
    }

    return AddInt32Modulo(even, odd);
}

} // namespace cgx1::matrix
