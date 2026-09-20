// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#ifndef CGX1_POWER_H
#define CGX1_POWER_H

#include <stdbool.h>
#include <stdint.h>

typedef enum CgxPowerState
{
    CGX_POWER_P0_SAFE_BOOT = 0,
    CGX_POWER_P1_SLOT_ECO,
    CGX_POWER_P2_SLOT_MAX,
    CGX_POWER_P3_DOCK_QUIET,
    CGX_POWER_P4_DOCK_FULL,
    CGX_POWER_STATE_COUNT
} CgxPowerState;

typedef struct CgxTelemetry
{
    bool external48VPresent;
    bool coolantFlowValid;
    bool hardwareFault;
    uint16_t gpuTemperatureC;
    uint16_t vrmTemperatureC;
    uint16_t slotPowerWatts;
    uint16_t externalPowerWatts;
} CgxTelemetry;

CgxPowerState CgxChooseSafeState(CgxPowerState requested, const CgxTelemetry* telemetry);
uint16_t CgxStateBoardPowerLimitWatts(CgxPowerState state);

#endif
