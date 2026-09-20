// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include <stdexcept>

namespace cgx1 {

struct CardGeometry
{
    double lengthMm;
    double heightMm;
    double thicknessMm;
};

struct ThermalInputs
{
    double powerWatts;
    double coolantLitersPerMinute;
    double ambientC;
    double junctionToCoolantCPerW;
    double radiatorToAmbientCPerW;
};

inline constexpr double kTargetLengthMm = 167.5;
inline constexpr double kTargetHeightMm = 68.5;
inline constexpr double kTargetThicknessMm = 39.5;
inline constexpr double kTargetFp32Lanes = 25600.0;
inline constexpr double kTargetPeakClockGhz = 2.80;
inline constexpr double kTargetPeakFp32Tflops = 143.36;
inline constexpr double kTargetMemoryTbps = 6.6;
inline constexpr double kTargetBoardPowerWatts = 360.0;
inline constexpr double kTargetVramGb = 72.0;

inline double Fp32PeakTflops(double lanes, double clockGhz)
{
    return lanes * 2.0 * clockGhz / 1000.0;
}

inline double CoolantRiseC(double watts, double litersPerMinute)
{
    constexpr double densityKgPerLiter = 0.997;
    constexpr double waterHeatCapacityJPerKgK = 4186.0;
    const double kilogramsPerSecond = litersPerMinute * densityKgPerLiter / 60.0;
    if (kilogramsPerSecond <= 0.0)
    {
        throw std::invalid_argument("coolant flow must be positive");
    }
    return watts / (kilogramsPerSecond * waterHeatCapacityJPerKgK);
}

inline double EstimatedJunctionC(const ThermalInputs& input)
{
    const double coolantRise = CoolantRiseC(input.powerWatts, input.coolantLitersPerMinute);
    return input.ambientC
        + input.powerWatts * input.radiatorToAmbientCPerW
        + coolantRise * 0.5
        + input.powerWatts * input.junctionToCoolantCPerW;
}

inline bool FitsTargetEnvelope(const CardGeometry& geometry)
{
    return geometry.lengthMm <= kTargetLengthMm
        && geometry.heightMm <= kTargetHeightMm
        && geometry.thicknessMm <= kTargetThicknessMm;
}

inline double PeakFp32PerWatt(double tflops, double watts)
{
    if (watts <= 0.0)
    {
        throw std::invalid_argument("power must be positive");
    }
    return tflops / watts;
}

} // namespace cgx1
