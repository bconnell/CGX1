// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_check.h"
#include "cgx1_power.h"

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

    CGX1_TEST_CHECK(CgxChooseSafeState(CGX_POWER_P0_SAFE_BOOT, &telemetry) == CGX_POWER_P0_SAFE_BOOT);
    CGX1_TEST_CHECK(CgxChooseSafeState(CGX_POWER_P1_SLOT_ECO, &telemetry) == CGX_POWER_P1_SLOT_ECO);
    CGX1_TEST_CHECK(CgxChooseSafeState(CGX_POWER_P2_SLOT_MAX, &telemetry) == CGX_POWER_P2_SLOT_MAX);
    CGX1_TEST_CHECK(CgxChooseSafeState(CGX_POWER_P3_DOCK_QUIET, &telemetry) == CGX_POWER_P3_DOCK_QUIET);
    CGX1_TEST_CHECK(CgxChooseSafeState(CGX_POWER_P4_DOCK_FULL, &telemetry) == CGX_POWER_P4_DOCK_FULL);

    telemetry.coolantFlowValid = false;
    CGX1_TEST_CHECK(CgxChooseSafeState(CGX_POWER_P4_DOCK_FULL, &telemetry) == CGX_POWER_P0_SAFE_BOOT);

    telemetry = MakeNominalTelemetry();
    telemetry.external48VPresent = false;
    CGX1_TEST_CHECK(CgxChooseSafeState(CGX_POWER_P3_DOCK_QUIET, &telemetry) == CGX_POWER_P0_SAFE_BOOT);

    telemetry = MakeNominalTelemetry();
    telemetry.hardwareFault = true;
    CGX1_TEST_CHECK(CgxChooseSafeState(CGX_POWER_P4_DOCK_FULL, &telemetry) == CGX_POWER_P0_SAFE_BOOT);

    telemetry = MakeNominalTelemetry();
    telemetry.gpuTemperatureC = 88U;
    CGX1_TEST_CHECK(CgxChooseSafeState(CGX_POWER_P4_DOCK_FULL, &telemetry) == CGX_POWER_P0_SAFE_BOOT);

    telemetry = MakeNominalTelemetry();
    telemetry.vrmTemperatureC = 105U;
    CGX1_TEST_CHECK(CgxChooseSafeState(CGX_POWER_P4_DOCK_FULL, &telemetry) == CGX_POWER_P0_SAFE_BOOT);

    telemetry = MakeNominalTelemetry();
    CGX1_TEST_CHECK(CgxChooseSafeState((CgxPowerState)99, &telemetry) == CGX_POWER_P0_SAFE_BOOT);
    CGX1_TEST_CHECK(CgxChooseSafeState(CGX_POWER_P4_DOCK_FULL, NULL) == CGX_POWER_P0_SAFE_BOOT);

    CGX1_TEST_CHECK(CgxStateBoardPowerLimitWatts(CGX_POWER_P0_SAFE_BOOT) == 25U);
    CGX1_TEST_CHECK(CgxStateBoardPowerLimitWatts(CGX_POWER_P1_SLOT_ECO) == 45U);
    CGX1_TEST_CHECK(CgxStateBoardPowerLimitWatts(CGX_POWER_P2_SLOT_MAX) == 70U);
    CGX1_TEST_CHECK(CgxStateBoardPowerLimitWatts(CGX_POWER_P3_DOCK_QUIET) == 220U);
    CGX1_TEST_CHECK(CgxStateBoardPowerLimitWatts(CGX_POWER_P4_DOCK_FULL) == 360U);
    CGX1_TEST_CHECK(CgxStateBoardPowerLimitWatts((CgxPowerState)99) == 25U);

    puts("CGX 1 firmware power state checks passed.");
    return 0;
}
