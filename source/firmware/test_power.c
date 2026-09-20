// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_power.h"

#include <assert.h>
#include <stdio.h>

static CgxTelemetry MakeNominalTelemetry(void)
{
    CgxTelemetry telemetry = {
        .external48VPresent = true,
        .coolantFlowValid = true,
        .hardwareFault = false,
        .gpuTemperatureC = 70U,
        .vrmTemperatureC = 80U,
        .slotPowerWatts = 20U,
        .externalPowerWatts = 330U
    };
    return telemetry;
}

int main(void)
{
    CgxTelemetry telemetry = MakeNominalTelemetry();

    assert(CgxChooseSafeState(CGX_POWER_P0_SAFE_BOOT, &telemetry) == CGX_POWER_P0_SAFE_BOOT);
    assert(CgxChooseSafeState(CGX_POWER_P1_SLOT_ECO, &telemetry) == CGX_POWER_P1_SLOT_ECO);
    assert(CgxChooseSafeState(CGX_POWER_P2_SLOT_MAX, &telemetry) == CGX_POWER_P2_SLOT_MAX);
    assert(CgxChooseSafeState(CGX_POWER_P3_DOCK_QUIET, &telemetry) == CGX_POWER_P3_DOCK_QUIET);
    assert(CgxChooseSafeState(CGX_POWER_P4_DOCK_FULL, &telemetry) == CGX_POWER_P4_DOCK_FULL);

    telemetry.coolantFlowValid = false;
    assert(CgxChooseSafeState(CGX_POWER_P4_DOCK_FULL, &telemetry) == CGX_POWER_P0_SAFE_BOOT);

    telemetry = MakeNominalTelemetry();
    telemetry.external48VPresent = false;
    assert(CgxChooseSafeState(CGX_POWER_P3_DOCK_QUIET, &telemetry) == CGX_POWER_P0_SAFE_BOOT);

    telemetry = MakeNominalTelemetry();
    telemetry.hardwareFault = true;
    assert(CgxChooseSafeState(CGX_POWER_P4_DOCK_FULL, &telemetry) == CGX_POWER_P0_SAFE_BOOT);

    telemetry = MakeNominalTelemetry();
    telemetry.gpuTemperatureC = 88U;
    assert(CgxChooseSafeState(CGX_POWER_P4_DOCK_FULL, &telemetry) == CGX_POWER_P0_SAFE_BOOT);

    telemetry = MakeNominalTelemetry();
    telemetry.vrmTemperatureC = 105U;
    assert(CgxChooseSafeState(CGX_POWER_P4_DOCK_FULL, &telemetry) == CGX_POWER_P0_SAFE_BOOT);

    telemetry = MakeNominalTelemetry();
    assert(CgxChooseSafeState((CgxPowerState)99, &telemetry) == CGX_POWER_P0_SAFE_BOOT);
    assert(CgxChooseSafeState(CGX_POWER_P4_DOCK_FULL, NULL) == CGX_POWER_P0_SAFE_BOOT);

    assert(CgxStateBoardPowerLimitWatts(CGX_POWER_P0_SAFE_BOOT) == 25U);
    assert(CgxStateBoardPowerLimitWatts(CGX_POWER_P1_SLOT_ECO) == 45U);
    assert(CgxStateBoardPowerLimitWatts(CGX_POWER_P2_SLOT_MAX) == 70U);
    assert(CgxStateBoardPowerLimitWatts(CGX_POWER_P3_DOCK_QUIET) == 220U);
    assert(CgxStateBoardPowerLimitWatts(CGX_POWER_P4_DOCK_FULL) == 360U);
    assert(CgxStateBoardPowerLimitWatts((CgxPowerState)99) == 25U);

    puts("CGX 1 firmware power state checks passed.");
    return 0;
}
