// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_matrix_architecture.hpp"

#include <array>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <limits>
#include <stdexcept>

namespace {

using cgx1::matrix::MatrixOpcode;

void CheckFragmentCoverage(MatrixOpcode opcode)
{
    using namespace cgx1::matrix;

    const MatrixShape shape = ShapeForOpcode(opcode);
    const std::uint32_t inputElements = InputElementsPerLane(opcode);

    std::array<bool, kMatrixTileM * kFp8Int8TileK> seenA{};
    std::array<bool, kFp8Int8TileK * kMatrixTileN> seenB{};
    std::array<bool, kMatrixTileM * kMatrixTileN> seenD{};

    std::uint32_t aCount = 0U;
    std::uint32_t bCount = 0U;
    std::uint32_t dCount = 0U;

    for (std::uint32_t lane = 0U; lane < kNativeWaveSize; ++lane)
    {
        for (std::uint32_t element = 0U; element < inputElements; ++element)
        {
            const MatrixCoordinate a = InputAElementCoordinate(opcode, lane, element);
            const MatrixCoordinate b = InputBElementCoordinate(opcode, lane, element);

            assert(a.row < shape.m);
            assert(a.column < shape.k);
            assert(b.row < shape.k);
            assert(b.column < shape.n);

            const std::uint32_t aIndex =
                static_cast<std::uint32_t>(a.row) * shape.k + a.column;
            const std::uint32_t bIndex =
                static_cast<std::uint32_t>(b.row) * shape.n + b.column;

            assert(!seenA[aIndex]);
            assert(!seenB[bIndex]);
            seenA[aIndex] = true;
            seenB[bIndex] = true;
            ++aCount;
            ++bCount;

            const PackedElementLocation packed = InputPackedLocation(opcode, element);
            assert(packed.registerOffset < kMatrixSourceRegistersPerLane);
            assert(packed.bitOffset < 32U);
        }

        for (std::uint32_t element = 0U; element < kMatrixAccumulatorRegistersPerLane; ++element)
        {
            const MatrixCoordinate d = OutputElementCoordinate(lane, element);
            assert(d.row < shape.m);
            assert(d.column < shape.n);

            const std::uint32_t dIndex =
                static_cast<std::uint32_t>(d.row) * shape.n + d.column;
            assert(!seenD[dIndex]);
            seenD[dIndex] = true;
            ++dCount;
        }
    }

    assert(aCount == static_cast<std::uint32_t>(shape.m) * shape.k);
    assert(bCount == static_cast<std::uint32_t>(shape.k) * shape.n);
    assert(dCount == static_cast<std::uint32_t>(shape.m) * shape.n);

    for (std::uint32_t row = 0U; row < shape.m; ++row)
    {
        for (std::uint32_t k = 0U; k < shape.k; ++k)
        {
            assert(seenA[row * shape.k + k]);
        }
    }
    for (std::uint32_t k = 0U; k < shape.k; ++k)
    {
        for (std::uint32_t column = 0U; column < shape.n; ++column)
        {
            assert(seenB[k * shape.n + column]);
        }
    }
    for (bool value : seenD)
    {
        assert(value);
    }
}

} // namespace

int main()
{
    using namespace cgx1;
    using namespace cgx1::matrix;

    static_assert(kMatrixTileM == 16U);
    static_assert(kMatrixTileN == 16U);
    static_assert(kFp16Bf16TileK == 16U);
    static_assert(kFp8Int8TileK == 32U);
    static_assert(kMatrixSourceRegistersPerLane == 4U);
    static_assert(kMatrixAccumulatorRegistersPerLane == 8U);
    static_assert(kMatrixFragmentReadBytesPerWave == 2048U);
    static_assert(kMatrixFragmentWriteBytesPerWave == 1024U);
    static_assert(kMatrixRegisterCaptureCycles == 8U);
    static_assert(kMatrixExecutionCycles == 16U);
    static_assert(kMatrixWritebackCycles == 8U);
    static_assert(kMatrixIssueIntervalCycles == 16U);
    static_assert(kMatrixResultLatencyCycles == 33U);
    static_assert(kMatrixInputStagingSlots == 1U);
    static_assert(kMatrixOutputStagingSlots == 1U);
    static_assert(kMatrixVectorReadsPerLanePerCaptureCycle == 2U);
    static_assert(kMatrixVectorWritesPerLanePerWritebackCycle == 1U);
    static_assert(kMatrixFullWaveActiveRequired);
    static_assert(!kMatrixInstructionUsesExtensionWord);
    static_assert(!kMatrixTimingFeasibilityValidated);

    static_assert(kMatrixVectorReadsPerLanePerCaptureCycle * kMatrixRegisterCaptureCycles
        == 2U * kMatrixSourceRegistersPerLane + kMatrixAccumulatorRegistersPerLane);
    static_assert(kMatrixVectorWritesPerLanePerWritebackCycle * kMatrixWritebackCycles
        == kMatrixAccumulatorRegistersPerLane);
    static_assert(kMatrixResultLatencyCycles
        == 1U + kMatrixRegisterCaptureCycles + kMatrixExecutionCycles + kMatrixWritebackCycles);

    constexpr std::array allOpcodes{
        MatrixOpcode::Fp16Fp32,
        MatrixOpcode::Bf16Fp32,
        MatrixOpcode::E4M3E4M3Fp32,
        MatrixOpcode::E4M3E5M2Fp32,
        MatrixOpcode::E5M2E4M3Fp32,
        MatrixOpcode::E5M2E5M2Fp32,
        MatrixOpcode::Int8Int32
    };

    for (MatrixOpcode opcode : allOpcodes)
    {
        const MatrixShape shape = ShapeForOpcode(opcode);
        assert(shape.m == 16U);
        assert(shape.n == 16U);
        assert(shape.k == (IsEightBitOpcode(opcode) ? 32U : 16U));
        assert(shape.inputBits == (IsEightBitOpcode(opcode) ? 8U : 16U));
        assert(IsSupportedProfile(ProfileForOpcode(opcode)));
        CheckFragmentCoverage(opcode);
    }

    static_assert(!IsDefinedMatrixOpcode(0x7U));
    static_assert(!IsDefinedMatrixOpcode(0xFU));

    constexpr MatrixCoordinate d0 = OutputElementCoordinate(0U, 0U);
    constexpr MatrixCoordinate d7 = OutputElementCoordinate(0U, 7U);
    constexpr MatrixCoordinate d248 = OutputElementCoordinate(31U, 0U);
    constexpr MatrixCoordinate d255 = OutputElementCoordinate(31U, 7U);
    static_assert(d0.row == 0U && d0.column == 0U);
    static_assert(d7.row == 0U && d7.column == 7U);
    static_assert(d248.row == 15U && d248.column == 8U);
    static_assert(d255.row == 15U && d255.column == 15U);

    constexpr MatrixCoordinate a16First =
        InputAElementCoordinate(MatrixOpcode::Fp16Fp32, 0U, 0U);
    constexpr MatrixCoordinate a16SecondHalf =
        InputAElementCoordinate(MatrixOpcode::Fp16Fp32, 1U, 0U);
    constexpr MatrixCoordinate b16Last =
        InputBElementCoordinate(MatrixOpcode::Fp16Fp32, 31U, 7U);
    static_assert(a16First.row == 0U && a16First.column == 0U);
    static_assert(a16SecondHalf.row == 0U && a16SecondHalf.column == 8U);
    static_assert(b16Last.row == 15U && b16Last.column == 15U);

    constexpr MatrixCoordinate a8SecondHalf =
        InputAElementCoordinate(MatrixOpcode::E4M3E4M3Fp32, 1U, 0U);
    constexpr MatrixCoordinate b8Last =
        InputBElementCoordinate(MatrixOpcode::Int8Int32, 31U, 15U);
    static_assert(a8SecondHalf.row == 0U && a8SecondHalf.column == 16U);
    static_assert(b8Last.row == 31U && b8Last.column == 15U);

    constexpr PackedElementLocation p16 =
        InputPackedLocation(MatrixOpcode::Fp16Fp32, 7U);
    constexpr PackedElementLocation p8 =
        InputPackedLocation(MatrixOpcode::E4M3E4M3Fp32, 15U);
    static_assert(p16.registerOffset == 3U && p16.bitOffset == 16U);
    static_assert(p8.registerOffset == 3U && p8.bitOffset == 24U);

    constexpr isa::BaseInstruction validMatrix{
        isa::InstructionClass::Matrix,
        static_cast<std::uint8_t>(MatrixOpcode::Fp16Fp32),
        32U,
        64U,
        68U
    };
    static_assert(IsValidMatrixInstruction(validMatrix));
    static_assert(isa::EncodeBase(validMatrix) == 0x60204044U);

    constexpr isa::BaseInstruction aliasedReadSources{
        isa::InstructionClass::Matrix,
        static_cast<std::uint8_t>(MatrixOpcode::Bf16Fp32),
        32U,
        64U,
        64U
    };
    static_assert(IsValidMatrixInstruction(aliasedReadSources));

    constexpr isa::BaseInstruction badDestinationAlignment{
        isa::InstructionClass::Matrix,
        static_cast<std::uint8_t>(MatrixOpcode::Fp16Fp32),
        33U,
        64U,
        68U
    };
    static_assert(!IsValidMatrixInstruction(badDestinationAlignment));

    constexpr isa::BaseInstruction badSourceAlignment{
        isa::InstructionClass::Matrix,
        static_cast<std::uint8_t>(MatrixOpcode::Fp16Fp32),
        32U,
        65U,
        68U
    };
    static_assert(!IsValidMatrixInstruction(badSourceAlignment));

    constexpr isa::BaseInstruction overlappingDestination{
        isa::InstructionClass::Matrix,
        static_cast<std::uint8_t>(MatrixOpcode::Fp16Fp32),
        32U,
        36U,
        68U
    };
    static_assert(!IsValidMatrixInstruction(overlappingDestination));

    constexpr isa::BaseInstruction reservedOpcode{
        isa::InstructionClass::Matrix,
        0x7U,
        32U,
        64U,
        68U
    };
    static_assert(!IsValidMatrixInstruction(reservedOpcode));

    constexpr isa::BaseInstruction wrongClass{
        isa::InstructionClass::Vector,
        0x0U,
        32U,
        64U,
        68U
    };
    static_assert(!IsValidMatrixInstruction(wrongClass));

    static_assert(DenseArithmeticOperations(MatrixOpcode::Fp16Fp32) == 8192U);
    static_assert(DenseArithmeticOperations(MatrixOpcode::Bf16Fp32) == 8192U);
    static_assert(DenseArithmeticOperations(MatrixOpcode::E4M3E4M3Fp32) == 16384U);
    static_assert(DenseArithmeticOperations(MatrixOpcode::Int8Int32) == 16384U);
    static_assert(DenseOperationsPerEngineCycle(MatrixOpcode::Fp16Fp32) == 512U);
    static_assert(DenseOperationsPerEngineCycle(MatrixOpcode::Int8Int32) == 1024U);

    assert(std::abs(DenseDeviceTeraOperations(MatrixOpcode::Fp16Fp32, 2.80) - 1146.88) < 0.001);
    assert(std::abs(DenseDeviceTeraOperations(MatrixOpcode::Fp16Fp32, 2.65) - 1085.44) < 0.001);
    assert(std::abs(DenseDeviceTeraOperations(MatrixOpcode::E4M3E4M3Fp32, 2.80) - 2293.76) < 0.001);
    assert(std::abs(DenseDeviceTeraOperations(MatrixOpcode::Int8Int32, 2.65) - 2170.88) < 0.001);

    std::array<float, kFp16Bf16TileK> f16A{};
    std::array<float, kFp16Bf16TileK> f16B{};
    f16A.fill(1.0F);
    f16B.fill(1.0F);
    assert(ReferencePhysicalFp16Bf16Cell(f16A, f16B, 2.0F) == 18.0F);

    std::array<float, kFp8Int8TileK> fp8A{};
    std::array<float, kFp8Int8TileK> fp8B{};
    fp8A.fill(1.0F);
    fp8B.fill(1.0F);
    assert(ReferencePhysicalFp8Cell(fp8A, fp8B, 2.0F) == 34.0F);

    std::array<std::int8_t, kFp8Int8TileK> int8A{};
    std::array<std::int8_t, kFp8Int8TileK> int8B{};
    int8A.fill(127);
    int8B.fill(127);
    const std::int32_t int8Result = ReferencePhysicalInt8Cell(
        int8A,
        int8B,
        std::numeric_limits<std::int32_t>::max() - 1000);
    std::int32_t expected = std::numeric_limits<std::int32_t>::max() - 1000;
    for (std::uint32_t k = 0U; k < kFp8Int8TileK; ++k)
    {
        expected = ReferenceInt8Mac(127, 127, expected);
    }
    assert(int8Result == expected);

    bool rejectedClock = false;
    try
    {
        (void)DenseDeviceTeraOperations(MatrixOpcode::Fp16Fp32, 0.0);
    }
    catch (const std::invalid_argument&)
    {
        rejectedClock = true;
    }
    assert(rejectedClock);

    bool rejectedCoordinate = false;
    try
    {
        (void)OutputElementCoordinate(32U, 0U);
    }
    catch (const std::invalid_argument&)
    {
        rejectedCoordinate = true;
    }
    assert(rejectedCoordinate);

    return 0;
}
