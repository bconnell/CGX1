// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// Keep runtime checks active in optimized Release CTest builds.
#ifdef NDEBUG
#undef NDEBUG
#endif
#include "cgx1_test_check.h"
#include "cgx1_power_management.hpp"

#include <limits>

int main()
{
    using namespace cgx1::power;

    static_assert(kComputeTileCount == 4U);

    static_assert(BoardLimitWatts(BoardPowerState::P0SafeBoot) == 25.0);
    static_assert(BoardLimitWatts(BoardPowerState::P1SlotEco) == 45.0);
    static_assert(BoardLimitWatts(BoardPowerState::P2SlotMax) == 70.0);
    static_assert(BoardLimitWatts(BoardPowerState::P3DockQuiet) == 220.0);
    static_assert(BoardLimitWatts(BoardPowerState::P4DockFull) == 360.0);
    static_assert(!BoardStateRequiresDock(BoardPowerState::P2SlotMax));
    static_assert(BoardStateRequiresDock(BoardPowerState::P3DockQuiet));
    static_assert(IsValidBoardPowerState(BoardPowerState::P0SafeBoot));
    static_assert(IsValidBoardPowerState(BoardPowerState::P4DockFull));
    static_assert(!IsValidBoardPowerState(static_cast<BoardPowerState>(99)));

    static_assert(MaxTileStateForBoardState(BoardPowerState::P0SafeBoot) == TileOperatingState::Idle);
    static_assert(MaxTileStateForBoardState(BoardPowerState::P1SlotEco) == TileOperatingState::Eco);
    static_assert(MaxTileStateForBoardState(BoardPowerState::P2SlotMax) == TileOperatingState::Nominal);
    static_assert(MaxTileStateForBoardState(BoardPowerState::P4DockFull) == TileOperatingState::Boost);
    static_assert(IsValidTileOperatingState(TileOperatingState::Off));
    static_assert(IsValidTileOperatingState(TileOperatingState::Boost));
    static_assert(!IsValidTileOperatingState(static_cast<TileOperatingState>(99)));
    static_assert(!TileIsSchedulerEligible(TileOperatingState::Idle));
    static_assert(TileIsSchedulerEligible(TileOperatingState::Eco));
    static_assert(BoardStateAllowsTileState(BoardPowerState::P2SlotMax, TileOperatingState::Nominal));
    static_assert(!BoardStateAllowsTileState(BoardPowerState::P2SlotMax, TileOperatingState::Boost));

    CGX1_TEST_CHECK(CanAuthorizeBudget(BudgetRequest{BoardPowerState::P4DockFull, 130.0, {57.5, 57.5, 57.5, 57.5}}));
    CGX1_TEST_CHECK(!CanAuthorizeBudget(BudgetRequest{BoardPowerState::P4DockFull, 130.1, {57.5, 57.5, 57.5, 57.5}}));
    CGX1_TEST_CHECK(CanAuthorizeBudget(BudgetRequest{BoardPowerState::P1SlotEco, 25.0, {20.0, 0.0, 0.0, 0.0}}));
    CGX1_TEST_CHECK(!CanAuthorizeBudget(BudgetRequest{BoardPowerState::P1SlotEco, 25.0, {20.1, 0.0, 0.0, 0.0}}));
    CGX1_TEST_CHECK(!CanAuthorizeBudget(BudgetRequest{BoardPowerState::P2SlotMax, -1.0, {0.0, 0.0, 0.0, 0.0}}));
    CGX1_TEST_CHECK(!CanAuthorizeBudget(BudgetRequest{static_cast<BoardPowerState>(99), 0.0, {0.0, 0.0, 0.0, 0.0}}));
    CGX1_TEST_CHECK(!CanAuthorizeBudget(BudgetRequest{BoardPowerState::P2SlotMax, 0.0, {std::numeric_limits<double>::quiet_NaN(), 0.0, 0.0, 0.0}}));
    CGX1_TEST_CHECK(!CanAuthorizeBudget(BudgetRequest{BoardPowerState::P2SlotMax, 0.0, {std::numeric_limits<double>::infinity(), 0.0, 0.0, 0.0}}));
    CGX1_TEST_CHECK(!CanAuthorizeBudget(BudgetRequest{BoardPowerState::P2SlotMax, 0.0, {-0.1, 0.0, 0.0, 0.0}}));

    CGX1_TEST_CHECK(CanAuthorizePlan(PowerPlan{
        BoardPowerState::P4DockFull,
        130.0,
        {TileOperatingState::Boost, TileOperatingState::Boost, TileOperatingState::Boost, TileOperatingState::Boost},
        {57.5, 57.5, 57.5, 57.5}}));
    CGX1_TEST_CHECK(!CanAuthorizePlan(PowerPlan{
        BoardPowerState::P2SlotMax,
        10.0,
        {TileOperatingState::Boost, TileOperatingState::Off, TileOperatingState::Off, TileOperatingState::Off},
        {10.0, 0.0, 0.0, 0.0}}));
    CGX1_TEST_CHECK(!CanAuthorizePlan(PowerPlan{
        BoardPowerState::P4DockFull,
        0.0,
        {static_cast<TileOperatingState>(99), TileOperatingState::Off, TileOperatingState::Off, TileOperatingState::Off},
        {0.0, 0.0, 0.0, 0.0}}));

    const TransitionContext readyUp{true, false, false, true, true, true, true, false};
    const TransitionContext readyDown{true, false, false, true, true, true, false, true};

    CGX1_TEST_CHECK(CanOrderlyTransition(TileOperatingState::Idle, TileOperatingState::Eco, readyUp));
    CGX1_TEST_CHECK(CanOrderlyTransition(TileOperatingState::Eco, TileOperatingState::Nominal, readyUp));
    CGX1_TEST_CHECK(CanOrderlyTransition(TileOperatingState::Nominal, TileOperatingState::Boost, readyUp));
    CGX1_TEST_CHECK(CanOrderlyTransition(TileOperatingState::Boost, TileOperatingState::Nominal, readyDown));
    CGX1_TEST_CHECK(CanOrderlyTransition(TileOperatingState::Nominal, TileOperatingState::Eco, readyDown));

    TransitionContext noVoltage = readyUp;
    noVoltage.voltageReadyForHigherPerformance = false;
    CGX1_TEST_CHECK(!CanOrderlyTransition(TileOperatingState::Eco, TileOperatingState::Nominal, noVoltage));

    TransitionContext clockTooHigh = readyDown;
    clockTooHigh.clockAtOrBelowLowerTarget = false;
    CGX1_TEST_CHECK(!CanOrderlyTransition(TileOperatingState::Nominal, TileOperatingState::Eco, clockTooHigh));

    TransitionContext dirty = readyDown;
    dirty.dirtyCoherentState = true;
    CGX1_TEST_CHECK(!CanOrderlyTransition(TileOperatingState::Eco, TileOperatingState::Idle, dirty));

    TransitionContext notDrained = readyDown;
    notDrained.schedulerDrained = false;
    CGX1_TEST_CHECK(!CanOrderlyTransition(TileOperatingState::Eco, TileOperatingState::Idle, notDrained));

    TransitionContext idleToRetention{
        true, false, true, true, false, true, false, true
    };
    CGX1_TEST_CHECK(CanOrderlyTransition(TileOperatingState::Idle, TileOperatingState::Retention, idleToRetention));
    CGX1_TEST_CHECK(CanOrderlyTransition(TileOperatingState::Retention, TileOperatingState::Off, idleToRetention));

    TransitionContext offToRetention{
        true, false, true, true, false, false, false, true
    };
    CGX1_TEST_CHECK(CanOrderlyTransition(TileOperatingState::Off, TileOperatingState::Retention, offToRetention));

    TransitionContext retentionToIdle{
        true, false, false, true, true, true, false, true
    };
    CGX1_TEST_CHECK(CanOrderlyTransition(TileOperatingState::Retention, TileOperatingState::Idle, retentionToIdle));

    TransitionContext noCoherence = retentionToIdle;
    noCoherence.coherenceReady = false;
    CGX1_TEST_CHECK(!CanOrderlyTransition(TileOperatingState::Retention, TileOperatingState::Idle, noCoherence));

    TransitionContext idleNoCoherence = readyUp;
    idleNoCoherence.coherenceReady = false;
    CGX1_TEST_CHECK(!CanOrderlyTransition(TileOperatingState::Idle, TileOperatingState::Eco, idleNoCoherence));

    CGX1_TEST_CHECK(!CanOrderlyTransition(static_cast<TileOperatingState>(99), TileOperatingState::Idle, readyUp));
    CGX1_TEST_CHECK(!CanOrderlyTransition(TileOperatingState::Idle, static_cast<TileOperatingState>(99), readyUp));

    for (int current = static_cast<int>(TileOperatingState::Off); current <= static_cast<int>(TileOperatingState::Boost); ++current)
    {
        for (int requested = static_cast<int>(TileOperatingState::Off); requested <= static_cast<int>(TileOperatingState::Boost); ++requested)
        {
            const int distance = current > requested ? current - requested : requested - current;
            if (distance > 1)
            {
                CGX1_TEST_CHECK(!CanOrderlyTransition(
                    static_cast<TileOperatingState>(current),
                    static_cast<TileOperatingState>(requested),
                    readyUp));
            }
        }
    }

    CGX1_TEST_CHECK(EmergencyIsolationRequired(true, false, false, false, true, true));
    CGX1_TEST_CHECK(EmergencyIsolationRequired(false, true, false, false, true, true));
    CGX1_TEST_CHECK(EmergencyIsolationRequired(false, false, true, false, false, true));
    CGX1_TEST_CHECK(EmergencyIsolationRequired(false, false, true, false, true, false));
    CGX1_TEST_CHECK(EmergencyIsolationRequired(false, false, false, true, false, true));
    CGX1_TEST_CHECK(EmergencyIsolationRequired(false, false, false, true, true, false));
    CGX1_TEST_CHECK(EmergencyIsolationRequired(false, false, true, true, false, true));
    CGX1_TEST_CHECK(!EmergencyIsolationRequired(false, false, true, false, true, true));
    CGX1_TEST_CHECK(!EmergencyIsolationRequired(false, false, false, true, true, true));
    CGX1_TEST_CHECK(!EmergencyIsolationRequired(false, false, false, false, false, false));

    constexpr HysteresisConfig hysteresis{3U, 5U};
    static_assert(HysteresisConfigValid(hysteresis));
    static_assert(!PromotionAllowed(2U, hysteresis));
    static_assert(PromotionAllowed(3U, hysteresis));
    static_assert(!DemotionAllowed(4U, hysteresis));
    static_assert(DemotionAllowed(5U, hysteresis));
    static_assert(!HysteresisConfigValid(HysteresisConfig{0U, 1U}));

    return 0;
}
