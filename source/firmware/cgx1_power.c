// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_power.h"

#include <stddef.h>

uint16_t CgxStateBoardPowerLimitWatts(CgxPowerState state)
{
    switch (state)
    {
        case CGX_POWER_P0_SAFE_BOOT:  return 25U;
        case CGX_POWER_P1_SLOT_ECO:   return 45U;
        case CGX_POWER_P2_SLOT_MAX:   return 70U;
        case CGX_POWER_P3_DOCK_QUIET: return 220U;
        case CGX_POWER_P4_DOCK_FULL:  return 360U;
        default:                      return 25U;
    }
}

CgxPowerState CgxChooseSafeState(CgxPowerState requested, const CgxTelemetry* telemetry)
{
    if (telemetry == NULL || requested < CGX_POWER_P0_SAFE_BOOT || requested >= CGX_POWER_STATE_COUNT)
    {
        return CGX_POWER_P0_SAFE_BOOT;
    }

    if (telemetry->hardwareFault)
    {
        return CGX_POWER_P0_SAFE_BOOT;
    }

    if (telemetry->gpuTemperatureC >= 88U || telemetry->vrmTemperatureC >= 105U)
    {
        return CGX_POWER_P0_SAFE_BOOT;
    }

    if (requested >= CGX_POWER_P3_DOCK_QUIET)
    {
        if (!telemetry->external48VPresent || !telemetry->coolantFlowValid)
        {
            return CGX_POWER_P0_SAFE_BOOT;
        }
    }

    return requested;
}
