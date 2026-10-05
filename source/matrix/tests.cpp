// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_check.h"
#include "cgx1_matrix.hpp"

#include <array>
#include <bit>
#include <cmath>
#include <cstdint>
#include <limits>
#include <stdexcept>

int main()
{
    using namespace cgx1::matrix;

    static_assert(kMatrixEnginesPerComputeUnit == 4U);
    static_assert(kNativeWaveSize == 32U);
    static_assert(kThroughputFrozen);
    static_assert(kPhysicalTileShapesFrozen);
    static_assert(kPhysicalFragmentMappingFrozen);
    static_assert(kMatrixInstructionEncodingFrozen);
    static_assert(!kStructuredSparsityAccelerationClaimed);
    static_assert(!kMxFormatsBaseline);
    static_assert(!kTf32Baseline);
    static_assert(!kFp64MatrixBaseline);
    static_assert(!kFp32InputMatrixBaseline);
    static_assert(kFloatingOperandsWidenExactlyToFp32);
    static_assert(kFloatingAccumulationUsesFp32Fma);
    static_assert(kFloatingReductionOrderFrozen);

    static_assert(FormatInfo(MatrixDataType::Fp16).exponentBits == 5U);
    static_assert(FormatInfo(MatrixDataType::Fp16).fractionBits == 10U);
    static_assert(FormatInfo(MatrixDataType::Bf16).exponentBits == 8U);
    static_assert(FormatInfo(MatrixDataType::Bf16).fractionBits == 7U);
    static_assert(FormatInfo(MatrixDataType::Fp8E4M3).exponentBits == 4U);
    static_assert(FormatInfo(MatrixDataType::Fp8E4M3).fractionBits == 3U);
    static_assert(!FormatInfo(MatrixDataType::Fp8E4M3).hasInfinity);
    static_assert(FormatInfo(MatrixDataType::Fp8E5M2).hasInfinity);

    static_assert(IsSupportedProfile(MatrixProfile{
        MatrixDataType::Fp16, MatrixDataType::Fp16, MatrixDataType::Fp32, MatrixDataType::Fp32}));
    static_assert(IsSupportedProfile(MatrixProfile{
        MatrixDataType::Bf16, MatrixDataType::Bf16, MatrixDataType::Fp32, MatrixDataType::Fp32}));
    static_assert(IsSupportedProfile(MatrixProfile{
        MatrixDataType::Fp8E4M3, MatrixDataType::Fp8E4M3, MatrixDataType::Fp32, MatrixDataType::Fp32}));
    static_assert(IsSupportedProfile(MatrixProfile{
        MatrixDataType::Fp8E4M3, MatrixDataType::Fp8E5M2, MatrixDataType::Fp32, MatrixDataType::Fp32}));
    static_assert(IsSupportedProfile(MatrixProfile{
        MatrixDataType::Fp8E5M2, MatrixDataType::Fp8E4M3, MatrixDataType::Fp32, MatrixDataType::Fp32}));
    static_assert(IsSupportedProfile(MatrixProfile{
        MatrixDataType::Fp8E5M2, MatrixDataType::Fp8E5M2, MatrixDataType::Fp32, MatrixDataType::Fp32}));
    static_assert(IsSupportedProfile(MatrixProfile{
        MatrixDataType::Int8, MatrixDataType::Int8, MatrixDataType::Int32, MatrixDataType::Int32}));

    static_assert(!IsSupportedProfile(MatrixProfile{
        MatrixDataType::Fp16, MatrixDataType::Fp16, MatrixDataType::Fp16, MatrixDataType::Fp16}));
    static_assert(!IsSupportedProfile(MatrixProfile{
        MatrixDataType::Fp32, MatrixDataType::Fp32, MatrixDataType::Fp32, MatrixDataType::Fp32}));
    static_assert(!IsSupportedProfile(MatrixProfile{
        MatrixDataType::Int8, MatrixDataType::Int8, MatrixDataType::Fp32, MatrixDataType::Fp32}));
    static_assert(!IsSupportedProfile(MatrixProfile{
        static_cast<MatrixDataType>(99), MatrixDataType::Fp16, MatrixDataType::Fp32, MatrixDataType::Fp32}));

    CGX1_TEST_CHECK(DecodeFp8(0x38U, MatrixDataType::Fp8E4M3) == 1.0F);
    CGX1_TEST_CHECK(DecodeFp8(0x3CU, MatrixDataType::Fp8E5M2) == 1.0F);
    CGX1_TEST_CHECK(DecodeFp8(0x7EU, MatrixDataType::Fp8E4M3) == 448.0F);
    CGX1_TEST_CHECK(DecodeFp8(0x7BU, MatrixDataType::Fp8E5M2) == 57344.0F);
    CGX1_TEST_CHECK(std::isnan(DecodeFp8(0x7FU, MatrixDataType::Fp8E4M3)));
    CGX1_TEST_CHECK(std::isinf(DecodeFp8(0x7CU, MatrixDataType::Fp8E5M2)));
    CGX1_TEST_CHECK(std::signbit(DecodeFp8(0xFCU, MatrixDataType::Fp8E5M2)));
    CGX1_TEST_CHECK(IsFp8Subnormal(0x01U, MatrixDataType::Fp8E4M3));
    CGX1_TEST_CHECK(IsFp8Subnormal(0x01U, MatrixDataType::Fp8E5M2));
    CGX1_TEST_CHECK(DecodeFp8(0x01U, MatrixDataType::Fp8E4M3) == 0.001953125F);
    CGX1_TEST_CHECK(DecodeFp8(0x01U, MatrixDataType::Fp8E5M2) == 0.0000152587890625F);

    CGX1_TEST_CHECK(EncodeFp8RoundTiesToEven(1.0F, MatrixDataType::Fp8E4M3, Fp8SaturationMode::NonSaturating) == 0x38U);
    CGX1_TEST_CHECK(EncodeFp8RoundTiesToEven(1.0F, MatrixDataType::Fp8E5M2, Fp8SaturationMode::NonSaturating) == 0x3CU);
    CGX1_TEST_CHECK(EncodeFp8RoundTiesToEven(-1.0F, MatrixDataType::Fp8E4M3, Fp8SaturationMode::NonSaturating) == 0xB8U);
    CGX1_TEST_CHECK(EncodeFp8RoundTiesToEven(1.0625F, MatrixDataType::Fp8E4M3, Fp8SaturationMode::NonSaturating) == 0x38U);
    CGX1_TEST_CHECK(EncodeFp8RoundTiesToEven(448.0F, MatrixDataType::Fp8E4M3, Fp8SaturationMode::NonSaturating) == 0x7EU);
    CGX1_TEST_CHECK(EncodeFp8RoundTiesToEven(464.0F, MatrixDataType::Fp8E4M3, Fp8SaturationMode::NonSaturating) == 0x7EU);
    CGX1_TEST_CHECK(IsFp8NaN(EncodeFp8RoundTiesToEven(464.1F, MatrixDataType::Fp8E4M3, Fp8SaturationMode::NonSaturating), MatrixDataType::Fp8E4M3));
    CGX1_TEST_CHECK(EncodeFp8RoundTiesToEven(100000.0F, MatrixDataType::Fp8E4M3, Fp8SaturationMode::Saturating) == 0x7EU);
    CGX1_TEST_CHECK(EncodeFp8RoundTiesToEven(60000.0F, MatrixDataType::Fp8E5M2, Fp8SaturationMode::NonSaturating) == 0x7BU);
    CGX1_TEST_CHECK(IsFp8Infinity(EncodeFp8RoundTiesToEven(61440.0F, MatrixDataType::Fp8E5M2, Fp8SaturationMode::NonSaturating), MatrixDataType::Fp8E5M2));
    CGX1_TEST_CHECK(EncodeFp8RoundTiesToEven(100000.0F, MatrixDataType::Fp8E5M2, Fp8SaturationMode::Saturating) == 0x7BU);
    CGX1_TEST_CHECK(IsFp8NaN(EncodeFp8RoundTiesToEven(
        std::numeric_limits<float>::quiet_NaN(), MatrixDataType::Fp8E4M3, Fp8SaturationMode::NonSaturating), MatrixDataType::Fp8E4M3));
    CGX1_TEST_CHECK(IsFp8Infinity(EncodeFp8RoundTiesToEven(
        std::numeric_limits<float>::infinity(), MatrixDataType::Fp8E5M2, Fp8SaturationMode::NonSaturating), MatrixDataType::Fp8E5M2));
    CGX1_TEST_CHECK(EncodeFp8RoundTiesToEven(
        std::numeric_limits<float>::infinity(), MatrixDataType::Fp8E5M2, Fp8SaturationMode::Saturating) == 0x7BU);
    CGX1_TEST_CHECK(EncodeFp8RoundTiesToEven(-0.0F, MatrixDataType::Fp8E4M3, Fp8SaturationMode::NonSaturating) == 0x80U);

    constexpr std::array fp8Types{MatrixDataType::Fp8E4M3, MatrixDataType::Fp8E5M2};
    for (MatrixDataType type : fp8Types)
    {
        float previous = 0.0F;
        bool havePrevious = false;
        for (std::uint16_t rawValue = 0U; rawValue <= 0x7FU; ++rawValue)
        {
            const auto raw = static_cast<std::uint8_t>(rawValue);
            if (IsFp8NaN(raw, type) || IsFp8Infinity(raw, type))
            {
                continue;
            }

            const float decoded = DecodeFp8(raw, type);
            CGX1_TEST_CHECK(decoded >= 0.0F);
            if (havePrevious)
            {
                CGX1_TEST_CHECK(decoded >= previous);
            }
            previous = decoded;
            havePrevious = true;

            CGX1_TEST_CHECK(EncodeFp8RoundTiesToEven(decoded, type, Fp8SaturationMode::NonSaturating) == raw);
            if (raw != 0U)
            {
                const auto negativeRaw = static_cast<std::uint8_t>(raw | 0x80U);
                const float negativeDecoded = DecodeFp8(negativeRaw, type);
                CGX1_TEST_CHECK(std::signbit(negativeDecoded));
                CGX1_TEST_CHECK(negativeDecoded == -decoded);
                CGX1_TEST_CHECK(EncodeFp8RoundTiesToEven(
                    negativeDecoded, type, Fp8SaturationMode::NonSaturating) == negativeRaw);
            }
        }
    }

    CGX1_TEST_CHECK(Fp16ToFloat(0x3C00U) == 1.0F);
    CGX1_TEST_CHECK(Fp16ToFloat(0xBC00U) == -1.0F);
    CGX1_TEST_CHECK(Fp16ToFloat(0x0001U) == std::ldexp(1.0F, -24));
    CGX1_TEST_CHECK(std::isinf(Fp16ToFloat(0x7C00U)));
    CGX1_TEST_CHECK(std::isnan(Fp16ToFloat(0x7E00U)));

    const std::uint16_t bf16One = FloatToBf16RoundTiesToEven(1.0F);
    CGX1_TEST_CHECK(bf16One == 0x3F80U);
    CGX1_TEST_CHECK(Bf16ToFloat(bf16One) == 1.0F);
    CGX1_TEST_CHECK(FloatToBf16RoundTiesToEven(std::bit_cast<float>(0x3F808000U)) == 0x3F80U);
    CGX1_TEST_CHECK(FloatToBf16RoundTiesToEven(std::bit_cast<float>(0x3F818000U)) == 0x3F82U);
    const std::uint16_t bf16Nan = FloatToBf16RoundTiesToEven(std::numeric_limits<float>::quiet_NaN());
    CGX1_TEST_CHECK((bf16Nan & 0x7F80U) == 0x7F80U);
    CGX1_TEST_CHECK((bf16Nan & 0x007FU) != 0U);

    CGX1_TEST_CHECK(ReferenceFp32Fma(2.0F, 3.0F, 4.0F) == 10.0F);
    CGX1_TEST_CHECK(ReferenceInt8Mac(12, -3, 100) == 64);
    CGX1_TEST_CHECK(ReferenceInt8Mac(127, 127, std::numeric_limits<std::int32_t>::max())
        == std::bit_cast<std::int32_t>(0x80003F00U));

    bool rejectedFp8DecodeType = false;
    try
    {
        (void)DecodeFp8(0U, MatrixDataType::Fp16);
    }
    catch (const std::invalid_argument&)
    {
        rejectedFp8DecodeType = true;
    }
    CGX1_TEST_CHECK(rejectedFp8DecodeType);

    bool rejectedFloatInfoType = false;
    try
    {
        (void)FormatInfo(MatrixDataType::Int8);
    }
    catch (const std::invalid_argument&)
    {
        rejectedFloatInfoType = true;
    }
    CGX1_TEST_CHECK(rejectedFloatInfoType);

    return 0;
}
