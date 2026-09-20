// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include <bit>
#include <cmath>
#include <cstdint>
#include <limits>
#include <stdexcept>

namespace cgx1::matrix {

inline constexpr std::uint32_t kMatrixEnginesPerComputeUnit = 4U;
inline constexpr std::uint32_t kNativeWaveSize = 32U;
inline constexpr bool kThroughputFrozen = true;
inline constexpr bool kPhysicalTileShapesFrozen = true;
inline constexpr bool kPhysicalFragmentMappingFrozen = true;
inline constexpr bool kMatrixInstructionEncodingFrozen = true;
inline constexpr bool kStructuredSparsityAccelerationClaimed = false;
inline constexpr bool kMxFormatsBaseline = false;
inline constexpr bool kTf32Baseline = false;
inline constexpr bool kFp64MatrixBaseline = false;
inline constexpr bool kFp32InputMatrixBaseline = false;
inline constexpr bool kFloatingOperandsWidenExactlyToFp32 = true;
inline constexpr bool kFloatingAccumulationUsesFp32Fma = true;
inline constexpr bool kFloatingReductionOrderFrozen = true;

enum class MatrixDataType : std::uint8_t
{
    Fp16 = 0,
    Bf16,
    Fp8E4M3,
    Fp8E5M2,
    Int8,
    Fp32,
    Int32
};

enum class Fp8SaturationMode : std::uint8_t
{
    Saturating = 0,
    NonSaturating
};

struct MatrixProfile
{
    MatrixDataType a;
    MatrixDataType b;
    MatrixDataType accumulator;
    MatrixDataType result;
};

struct FloatFormatInfo
{
    std::uint8_t exponentBits;
    std::uint8_t fractionBits;
    std::int16_t exponentBias;
    bool hasInfinity;
    bool hasSubnormals;
    float maxFinite;
};

inline constexpr bool IsKnownDataType(MatrixDataType type)
{
    return type >= MatrixDataType::Fp16 && type <= MatrixDataType::Int32;
}

inline constexpr bool IsFp8Type(MatrixDataType type)
{
    return type == MatrixDataType::Fp8E4M3 || type == MatrixDataType::Fp8E5M2;
}

inline constexpr FloatFormatInfo FormatInfo(MatrixDataType type)
{
    switch (type)
    {
        case MatrixDataType::Fp16:
            return FloatFormatInfo{5U, 10U, 15, true, true, 65504.0F};
        case MatrixDataType::Bf16:
            return FloatFormatInfo{8U, 7U, 127, true, true, 3.38953139e38F};
        case MatrixDataType::Fp8E4M3:
            return FloatFormatInfo{4U, 3U, 7, false, true, 448.0F};
        case MatrixDataType::Fp8E5M2:
            return FloatFormatInfo{5U, 2U, 15, true, true, 57344.0F};
        default:
            throw std::invalid_argument("matrix data type is not a floating-point format");
    }
}

inline constexpr bool IsSupportedProfile(const MatrixProfile& profile)
{
    if (!IsKnownDataType(profile.a)
        || !IsKnownDataType(profile.b)
        || !IsKnownDataType(profile.accumulator)
        || !IsKnownDataType(profile.result))
    {
        return false;
    }

    const bool fp16 = profile.a == MatrixDataType::Fp16
        && profile.b == MatrixDataType::Fp16
        && profile.accumulator == MatrixDataType::Fp32
        && profile.result == MatrixDataType::Fp32;

    const bool bf16 = profile.a == MatrixDataType::Bf16
        && profile.b == MatrixDataType::Bf16
        && profile.accumulator == MatrixDataType::Fp32
        && profile.result == MatrixDataType::Fp32;

    const bool fp8 = IsFp8Type(profile.a)
        && IsFp8Type(profile.b)
        && profile.accumulator == MatrixDataType::Fp32
        && profile.result == MatrixDataType::Fp32;

    const bool int8 = profile.a == MatrixDataType::Int8
        && profile.b == MatrixDataType::Int8
        && profile.accumulator == MatrixDataType::Int32
        && profile.result == MatrixDataType::Int32;

    return fp16 || bf16 || fp8 || int8;
}

inline constexpr bool IsFp8NaN(std::uint8_t bits, MatrixDataType type)
{
    if (type == MatrixDataType::Fp8E4M3)
    {
        return (bits & 0x7FU) == 0x7FU;
    }
    if (type == MatrixDataType::Fp8E5M2)
    {
        return (bits & 0x7CU) == 0x7CU && (bits & 0x03U) != 0U;
    }
    return false;
}

inline constexpr bool IsFp8Infinity(std::uint8_t bits, MatrixDataType type)
{
    return type == MatrixDataType::Fp8E5M2 && (bits & 0x7FU) == 0x7CU;
}

inline constexpr bool IsFp8Subnormal(std::uint8_t bits, MatrixDataType type)
{
    if (type == MatrixDataType::Fp8E4M3)
    {
        return (bits & 0x78U) == 0U && (bits & 0x07U) != 0U;
    }
    if (type == MatrixDataType::Fp8E5M2)
    {
        return (bits & 0x7CU) == 0U && (bits & 0x03U) != 0U;
    }
    return false;
}

inline float DecodeFp8(std::uint8_t bits, MatrixDataType type)
{
    if (!IsFp8Type(type))
    {
        throw std::invalid_argument("FP8 decode requires E4M3 or E5M2");
    }

    if (IsFp8NaN(bits, type))
    {
        return std::numeric_limits<float>::quiet_NaN();
    }

    const bool negative = (bits & 0x80U) != 0U;
    if (IsFp8Infinity(bits, type))
    {
        return negative ? -std::numeric_limits<float>::infinity()
                        : std::numeric_limits<float>::infinity();
    }

    const FloatFormatInfo info = FormatInfo(type);
    const std::uint8_t fractionMask = static_cast<std::uint8_t>((1U << info.fractionBits) - 1U);
    const std::uint8_t fraction = bits & fractionMask;
    const std::uint8_t exponentMask = static_cast<std::uint8_t>((1U << info.exponentBits) - 1U);
    const std::uint8_t exponent = static_cast<std::uint8_t>((bits >> info.fractionBits) & exponentMask);

    float magnitude = 0.0F;
    if (exponent == 0U)
    {
        if (fraction == 0U)
        {
            return negative ? -0.0F : 0.0F;
        }
        const float significand = static_cast<float>(fraction) / static_cast<float>(1U << info.fractionBits);
        magnitude = std::ldexp(significand, 1 - info.exponentBias);
    }
    else
    {
        const float significand = 1.0F
            + static_cast<float>(fraction) / static_cast<float>(1U << info.fractionBits);
        magnitude = std::ldexp(significand, static_cast<int>(exponent) - info.exponentBias);
    }

    return negative ? -magnitude : magnitude;
}

inline constexpr std::uint8_t Fp8MaxFiniteBits(MatrixDataType type, bool negative)
{
    if (type == MatrixDataType::Fp8E4M3)
    {
        return static_cast<std::uint8_t>((negative ? 0x80U : 0U) | 0x7EU);
    }
    if (type == MatrixDataType::Fp8E5M2)
    {
        return static_cast<std::uint8_t>((negative ? 0x80U : 0U) | 0x7BU);
    }
    throw std::invalid_argument("FP8 max finite requires E4M3 or E5M2");
}

inline constexpr std::uint8_t Fp8CanonicalNaNBits(MatrixDataType type, bool negative = false)
{
    if (type == MatrixDataType::Fp8E4M3)
    {
        return static_cast<std::uint8_t>((negative ? 0x80U : 0U) | 0x7FU);
    }
    if (type == MatrixDataType::Fp8E5M2)
    {
        return static_cast<std::uint8_t>((negative ? 0x80U : 0U) | 0x7DU);
    }
    throw std::invalid_argument("FP8 NaN requires E4M3 or E5M2");
}

inline constexpr std::uint8_t Fp8InfinityBits(MatrixDataType type, bool negative)
{
    if (type != MatrixDataType::Fp8E5M2)
    {
        throw std::invalid_argument("only E5M2 represents infinity");
    }
    return static_cast<std::uint8_t>((negative ? 0x80U : 0U) | 0x7CU);
}

inline float Fp8OverflowThreshold(MatrixDataType type)
{
    if (type == MatrixDataType::Fp8E4M3)
    {
        return 464.0F;
    }
    if (type == MatrixDataType::Fp8E5M2)
    {
        return 61440.0F;
    }
    throw std::invalid_argument("FP8 overflow threshold requires E4M3 or E5M2");
}

inline std::uint8_t EncodeFp8RoundTiesToEven(
    float value,
    MatrixDataType type,
    Fp8SaturationMode saturationMode)
{
    if (!IsFp8Type(type))
    {
        throw std::invalid_argument("FP8 encode requires E4M3 or E5M2");
    }

    const bool negative = std::signbit(value);
    if (std::isnan(value))
    {
        return Fp8CanonicalNaNBits(type, negative);
    }

    if (std::isinf(value))
    {
        if (saturationMode == Fp8SaturationMode::Saturating)
        {
            return Fp8MaxFiniteBits(type, negative);
        }
        return type == MatrixDataType::Fp8E5M2
            ? Fp8InfinityBits(type, negative)
            : Fp8CanonicalNaNBits(type, negative);
    }

    if (value == 0.0F)
    {
        return negative ? 0x80U : 0x00U;
    }

    const float magnitude = std::fabs(value);
    const float threshold = Fp8OverflowThreshold(type);
    const bool overflow = type == MatrixDataType::Fp8E5M2
        ? magnitude >= threshold
        : magnitude > threshold;

    if (overflow)
    {
        if (saturationMode == Fp8SaturationMode::Saturating)
        {
            return Fp8MaxFiniteBits(type, negative);
        }
        return type == MatrixDataType::Fp8E5M2
            ? Fp8InfinityBits(type, negative)
            : Fp8CanonicalNaNBits(type, negative);
    }

    std::uint8_t bestMagnitudeBits = 0U;
    float bestDistance = std::numeric_limits<float>::infinity();

    for (std::uint16_t raw = 0U; raw <= 0x7FU; ++raw)
    {
        const auto candidateBits = static_cast<std::uint8_t>(raw);
        if (IsFp8NaN(candidateBits, type) || IsFp8Infinity(candidateBits, type))
        {
            continue;
        }

        const float candidate = DecodeFp8(candidateBits, type);
        const float distance = std::fabs(magnitude - candidate);
        if (distance < bestDistance)
        {
            bestDistance = distance;
            bestMagnitudeBits = candidateBits;
            continue;
        }

        if (distance == bestDistance
            && (candidateBits & 0x01U) == 0U
            && (bestMagnitudeBits & 0x01U) != 0U)
        {
            bestMagnitudeBits = candidateBits;
        }
    }

    return static_cast<std::uint8_t>(bestMagnitudeBits | (negative ? 0x80U : 0U));
}

inline float Fp16ToFloat(std::uint16_t bits)
{
    const bool negative = (bits & 0x8000U) != 0U;
    const std::uint16_t exponent = static_cast<std::uint16_t>((bits >> 10U) & 0x1FU);
    const std::uint16_t fraction = static_cast<std::uint16_t>(bits & 0x03FFU);

    if (exponent == 0x1FU)
    {
        if (fraction == 0U)
        {
            return negative ? -std::numeric_limits<float>::infinity()
                            : std::numeric_limits<float>::infinity();
        }
        return std::numeric_limits<float>::quiet_NaN();
    }

    float magnitude = 0.0F;
    if (exponent == 0U)
    {
        if (fraction == 0U)
        {
            return negative ? -0.0F : 0.0F;
        }
        magnitude = std::ldexp(static_cast<float>(fraction), -24);
    }
    else
    {
        const float significand = 1.0F + static_cast<float>(fraction) / 1024.0F;
        magnitude = std::ldexp(significand, static_cast<int>(exponent) - 15);
    }

    return negative ? -magnitude : magnitude;
}

inline std::uint16_t FloatToBf16RoundTiesToEven(float value)
{
    const std::uint32_t bits = std::bit_cast<std::uint32_t>(value);
    const std::uint32_t exponent = bits & 0x7F800000U;
    const std::uint32_t fraction = bits & 0x007FFFFFU;

    if (exponent == 0x7F800000U && fraction != 0U)
    {
        const std::uint16_t upper = static_cast<std::uint16_t>(bits >> 16U);
        return static_cast<std::uint16_t>(upper | 0x0040U);
    }

    const std::uint32_t leastSignificantRetainedBit = (bits >> 16U) & 1U;
    const std::uint32_t rounded = bits + 0x7FFFU + leastSignificantRetainedBit;
    return static_cast<std::uint16_t>(rounded >> 16U);
}

inline float Bf16ToFloat(std::uint16_t bits)
{
    return std::bit_cast<float>(static_cast<std::uint32_t>(bits) << 16U);
}

inline float ReferenceFp32Fma(float a, float b, float accumulator)
{
    return std::fma(a, b, accumulator);
}

inline std::int32_t ReferenceInt8Mac(
    std::int8_t a,
    std::int8_t b,
    std::int32_t accumulator)
{
    const std::int32_t product = static_cast<std::int32_t>(a) * static_cast<std::int32_t>(b);
    const std::uint32_t accumulatorBits = std::bit_cast<std::uint32_t>(accumulator);
    const std::uint32_t productBits = static_cast<std::uint32_t>(product);
    return std::bit_cast<std::int32_t>(accumulatorBits + productBits);
}

} // namespace cgx1::matrix
