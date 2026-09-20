// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "model.hpp"

#include <iomanip>
#include <iostream>

int main()
{
    using namespace cgx1;

    const CardGeometry card{kTargetLengthMm, kTargetHeightMm, kTargetThicknessMm};
    const ThermalInputs thermal{360.0, 1.5, 35.0, 0.085, 0.040};

    std::cout << std::fixed << std::setprecision(2);
    std::cout << "CGX 1 analytical engineering model\n\n";
    std::cout << "Peak FP32 target: " << Fp32PeakTflops(kTargetFp32Lanes, kTargetPeakClockGhz) << " TFLOPS\n";
    std::cout << "Peak memory bandwidth target: " << kTargetMemoryTbps << " TB/s\n";
    std::cout << "VRAM baseline: " << kTargetVramGb << " GB\n";
    std::cout << "Board power target: " << kTargetBoardPowerWatts << " W\n";
    std::cout << "Peak FP32 per watt arithmetic: " << PeakFp32PerWatt(kTargetPeakFp32Tflops, kTargetBoardPowerWatts) << " TFLOPS/W\n";
    std::cout << "Card envelope passes target: " << (FitsTargetEnvelope(card) ? "YES" : "NO") << "\n";
    std::cout << "Coolant rise at 1.5 L/min: " << CoolantRiseC(360.0, 1.5) << " C\n";
    std::cout << "Estimated junction at 35 C ambient: " << EstimatedJunctionC(thermal) << " C\n\n";
    std::cout << "These values are analytical design targets. No fabricated CGX 1 silicon measurement is represented.\n";
    return 0;
}
