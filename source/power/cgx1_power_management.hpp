// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace cgx1::power {

inline constexpr std::size_t kComputeTileCount = 4U;

enum class BoardPowerState : std::uint8_t
{
    P0SafeBoot = 0,
    P1SlotEco,
    P2SlotMax,
    P3DockQuiet,
    P4DockFull
};

enum class TileOperatingState : std::uint8_t
{
    Off = 0,
    Retention,
    Idle,
    Eco,
    Nominal,
    Boost
};

struct BudgetRequest
{
    BoardPowerState boardState;
    double nonTileWatts;
    std::array<double, kComputeTileCount> tileWatts;
};

struct PowerPlan
{
    BoardPowerState boardState;
    double nonTileWatts;
    std::array<TileOperatingState, kComputeTileCount> tileStates;
    std::array<double, kComputeTileCount> tileWatts;
};

struct TransitionContext
{
    bool schedulerDrained;
    bool dirtyCoherentState;
    bool isolationAsserted;
    bool powerGood;
    bool clocksStable;
    bool coherenceReady;
    bool voltageReadyForHigherPerformance;
    bool clockAtOrBelowLowerTarget;
};

struct HysteresisConfig
{
    std::uint32_t promotionSamplesRequired;
    std::uint32_t demotionSamplesRequired;
};

inline constexpr bool IsValidBoardPowerState(BoardPowerState state)
{
    return state >= BoardPowerState::P0SafeBoot && state <= BoardPowerState::P4DockFull;
}

inline constexpr double BoardLimitWatts(BoardPowerState state)
{
    switch (state)
    {
        case BoardPowerState::P0SafeBoot:  return 25.0;
        case BoardPowerState::P1SlotEco:   return 45.0;
        case BoardPowerState::P2SlotMax:   return 70.0;
        case BoardPowerState::P3DockQuiet: return 220.0;
        case BoardPowerState::P4DockFull:  return 360.0;
    }
    return 25.0;
}

inline constexpr bool BoardStateRequiresDock(BoardPowerState state)
{
    return state == BoardPowerState::P3DockQuiet || state == BoardPowerState::P4DockFull;
}

inline constexpr TileOperatingState MaxTileStateForBoardState(BoardPowerState state)
{
    switch (state)
    {
        case BoardPowerState::P0SafeBoot:  return TileOperatingState::Idle;
        case BoardPowerState::P1SlotEco:   return TileOperatingState::Eco;
        case BoardPowerState::P2SlotMax:   return TileOperatingState::Nominal;
        case BoardPowerState::P3DockQuiet: return TileOperatingState::Boost;
        case BoardPowerState::P4DockFull:  return TileOperatingState::Boost;
    }
    return TileOperatingState::Idle;
}

inline constexpr bool IsValidTileOperatingState(TileOperatingState state)
{
    return state >= TileOperatingState::Off && state <= TileOperatingState::Boost;
}

inline constexpr bool TileIsSchedulerEligible(TileOperatingState state)
{
    return state == TileOperatingState::Eco
        || state == TileOperatingState::Nominal
        || state == TileOperatingState::Boost;
}

inline constexpr bool BoardStateAllowsTileState(BoardPowerState boardState, TileOperatingState tileState)
{
    return IsValidBoardPowerState(boardState)
        && IsValidTileOperatingState(tileState)
        && static_cast<std::uint8_t>(tileState) <= static_cast<std::uint8_t>(MaxTileStateForBoardState(boardState));
}

inline bool IsFiniteNonNegative(double value)
{
    return std::isfinite(value) && value >= 0.0;
}

inline bool CanAuthorizeBudget(const BudgetRequest& request)
{
    if (!IsValidBoardPowerState(request.boardState) || !IsFiniteNonNegative(request.nonTileWatts))
    {
        return false;
    }

    double total = request.nonTileWatts;
    for (double tileWatts : request.tileWatts)
    {
        if (!IsFiniteNonNegative(tileWatts))
        {
            return false;
        }
        total += tileWatts;
    }

    return total <= BoardLimitWatts(request.boardState) + 1e-9;
}

inline bool CanAuthorizePlan(const PowerPlan& plan)
{
    if (!IsValidBoardPowerState(plan.boardState))
    {
        return false;
    }

    for (TileOperatingState state : plan.tileStates)
    {
        if (!BoardStateAllowsTileState(plan.boardState, state))
        {
            return false;
        }
    }

    return CanAuthorizeBudget(BudgetRequest{plan.boardState, plan.nonTileWatts, plan.tileWatts});
}

inline constexpr bool AreAdjacent(TileOperatingState a, TileOperatingState b)
{
    const int ai = static_cast<int>(a);
    const int bi = static_cast<int>(b);
    return ai == bi || ai + 1 == bi || bi + 1 == ai;
}

inline constexpr bool CanOrderlyTransition(
    TileOperatingState current,
    TileOperatingState requested,
    const TransitionContext& context)
{
    if (!IsValidTileOperatingState(current) || !IsValidTileOperatingState(requested))
    {
        return false;
    }

    if (!AreAdjacent(current, requested))
    {
        return false;
    }

    if (current == requested)
    {
        return true;
    }

    if (current == TileOperatingState::Off && requested == TileOperatingState::Retention)
    {
        return context.isolationAsserted && context.powerGood;
    }

    if (current == TileOperatingState::Retention && requested == TileOperatingState::Off)
    {
        return context.schedulerDrained
            && !context.dirtyCoherentState
            && context.isolationAsserted;
    }

    if (current == TileOperatingState::Retention && requested == TileOperatingState::Idle)
    {
        return context.powerGood
            && context.clocksStable
            && context.coherenceReady
            && !context.isolationAsserted;
    }

    if (current == TileOperatingState::Idle && requested == TileOperatingState::Retention)
    {
        return context.schedulerDrained
            && !context.dirtyCoherentState
            && context.isolationAsserted;
    }

    if (current == TileOperatingState::Idle && requested == TileOperatingState::Eco)
    {
        return context.powerGood
            && context.clocksStable
            && context.coherenceReady
            && !context.isolationAsserted
            && context.voltageReadyForHigherPerformance;
    }

    if (current == TileOperatingState::Eco && requested == TileOperatingState::Idle)
    {
        return context.schedulerDrained
            && !context.dirtyCoherentState
            && context.clockAtOrBelowLowerTarget;
    }

    const bool raisingPerformance = static_cast<std::uint8_t>(requested) > static_cast<std::uint8_t>(current);
    if (raisingPerformance)
    {
        return context.powerGood
            && context.clocksStable
            && !context.isolationAsserted
            && context.voltageReadyForHigherPerformance;
    }

    return !context.isolationAsserted && context.clockAtOrBelowLowerTarget;
}

inline constexpr bool EmergencyIsolationRequired(
    bool hardwareFault,
    bool emergencyThermal,
    bool activeDockState,
    bool dockPowerValid,
    bool coolantFlowValid)
{
    return hardwareFault
        || emergencyThermal
        || (activeDockState && (!dockPowerValid || !coolantFlowValid));
}

inline constexpr bool HysteresisConfigValid(const HysteresisConfig& config)
{
    return config.promotionSamplesRequired > 0U && config.demotionSamplesRequired > 0U;
}

inline constexpr bool PromotionAllowed(std::uint32_t qualifyingSamples, const HysteresisConfig& config)
{
    return HysteresisConfigValid(config) && qualifyingSamples >= config.promotionSamplesRequired;
}

inline constexpr bool DemotionAllowed(std::uint32_t qualifyingSamples, const HysteresisConfig& config)
{
    return HysteresisConfigValid(config) && qualifyingSamples >= config.demotionSamplesRequired;
}

} // namespace cgx1::power
