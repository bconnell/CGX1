// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "workgroup_scheduler.hpp"

#include <algorithm>
#include <cstdint>
#include <iostream>
#include <random>
#include <vector>

#define CHECK(x) do { if (!(x)) { std::cerr << "[fail] " #x " line " << __LINE__ << '\n'; return 1; } } while (false)

using namespace cgx1::compute;

CuResourceLimits Limits(
    std::uint32_t waveSlots = 8U,
    std::uint32_t vgprRows = 64U,
    std::uint32_t scalarUnits = 256U,
    std::uint32_t sharedBytes = 4096U,
    std::uint32_t barrierContexts = 4U,
    std::uint32_t otherUnits = 128U)
{
    return CuResourceLimits{
        waveSlots, vgprRows, scalarUnits, sharedBytes,
        barrierContexts, otherUnits};
}

WorkgroupDemand Demand(
    std::uint64_t id,
    std::uint32_t waves,
    std::uint32_t vgprs = 16U,
    std::uint32_t scalarPerWave = 2U,
    std::uint32_t sharedBytes = 0U,
    std::uint32_t otherUnits = 0U)
{
    return WorkgroupDemand{
        id, waves, vgprs, scalarPerWave, sharedBytes, otherUnits};
}

int TestAdmissionAndResourceBoundaries()
{
    ComputeUnitWorkgroupScheduler scheduler(Limits(4U, 32U, 40U, 4096U, 1U, 9U));
    const auto maximum = Demand(1U, 4U, 64U, 10U, 4096U, 9U);
    CHECK(scheduler.Admit(maximum) == AdmissionFailure::None);
    CHECK(scheduler.ResidentWaveCount() == 4U);
    CHECK(scheduler.OccupiedVgprRows() == 32U);
    CHECK(scheduler.UsedScalarPredicateUnits() == 40U);
    CHECK(scheduler.UsedSharedLocalBytes() == 4096U);
    CHECK(scheduler.UsedOtherWorkgroupUnits() == 9U);
    CHECK(scheduler.AllLiveWavesResident(1U));

    ComputeUnitWorkgroupScheduler vgpr(Limits(4U, 63U));
    CHECK(vgpr.Admit(Demand(2U, 2U, 256U))
        == AdmissionFailure::VgprDemandExceedsCuCapacity);
    CHECK(vgpr.ResidentWaveCount() == 0U);

    ComputeUnitWorkgroupScheduler shared(Limits(4U, 32U, 32U, 1024U));
    CHECK(shared.Admit(Demand(3U, 1U, 16U, 1U, 1025U))
        == AdmissionFailure::SharedLocalMemoryExceedsCuCapacity);
    CHECK(shared.ResidentWaveCount() == 0U);

    ComputeUnitWorkgroupScheduler sharedBusy(Limits(4U, 32U, 32U, 1024U, 2U));
    CHECK(sharedBusy.Admit(Demand(30U, 2U, 16U, 2U, 700U))
        == AdmissionFailure::None);
    CHECK(sharedBusy.Admit(Demand(31U, 1U, 16U, 2U, 400U))
        == AdmissionFailure::SharedLocalMemoryUnavailable);

    ComputeUnitWorkgroupScheduler vgprBusy(Limits(4U, 4U, 32U, 1024U, 2U));
    CHECK(vgprBusy.Admit(Demand(32U, 2U, 16U)) == AdmissionFailure::None);
    CHECK(vgprBusy.Admit(Demand(33U, 1U, 1U))
        == AdmissionFailure::VgprCapacityUnavailable);

    ComputeUnitWorkgroupScheduler otherBusy(Limits(4U, 32U, 32U, 1024U, 2U, 10U));
    CHECK(otherBusy.Admit(Demand(34U, 1U, 16U, 1U, 0U, 7U))
        == AdmissionFailure::None);
    CHECK(otherBusy.Admit(Demand(35U, 1U, 16U, 1U, 0U, 4U))
        == AdmissionFailure::OtherWorkgroupStateUnavailable);

    ComputeUnitWorkgroupScheduler state(Limits(4U, 32U, 15U));
    CHECK(state.Admit(Demand(4U, 2U, 16U, 8U))
        == AdmissionFailure::ScalarPredicateStateExceedsCuCapacity);

    ComputeUnitWorkgroupScheduler scalarBusy(Limits(4U, 32U, 8U, 1024U, 2U));
    CHECK(scalarBusy.Admit(Demand(40U, 2U, 16U, 4U))
        == AdmissionFailure::None);
    CHECK(scalarBusy.Admit(Demand(41U, 1U, 16U, 1U))
        == AdmissionFailure::ScalarPredicateStateUnavailable);

    ComputeUnitWorkgroupScheduler barrierBusy(Limits(4U, 32U, 32U, 1024U, 1U));
    CHECK(barrierBusy.Admit(Demand(42U, 1U)) == AdmissionFailure::None);
    CHECK(barrierBusy.Admit(Demand(43U, 1U))
        == AdmissionFailure::BarrierContextsUnavailable);

    ComputeUnitWorkgroupScheduler multiple(Limits(4U, 32U, 32U, 1024U, 4U, 16U));
    CHECK(multiple.Admit(Demand(5U, 2U, 16U, 2U, 256U, 4U))
        == AdmissionFailure::None);
    CHECK(multiple.Admit(Demand(6U, 2U, 16U, 2U, 256U, 4U))
        == AdmissionFailure::None);
    CHECK(multiple.WorkgroupCount() == 2U);
    CHECK(multiple.ResidentWaveCount() == 4U);
    CHECK(multiple.UsedSharedLocalBytes() == 512U);
    CHECK(multiple.Admit(Demand(7U, 1U))
        == AdmissionFailure::ResidentWaveSlotsUnavailable);
    CHECK(multiple.Admit(Demand(5U, 1U))
        == AdmissionFailure::DuplicateWorkgroupId);
    return 0;
}

int TestBarrierArrivalsAndIssue()
{
    ComputeUnitWorkgroupScheduler oneWave(Limits(4U));
    CHECK(oneWave.Admit(Demand(10U, 1U)) == AdmissionFailure::None);
    auto result = oneWave.ArriveAtBarrier(10U, {0U});
    CHECK(result.status == BarrierStatus::Released);
    CHECK(result.releasedWaveCount == 1U);
    CHECK(oneWave.BarrierGeneration(10U) == 1U);

    ComputeUnitWorkgroupScheduler together(Limits(4U));
    CHECK(together.Admit(Demand(11U, 3U)) == AdmissionFailure::None);
    result = together.ArriveAtBarrier(11U, {2U, 0U, 1U});
    CHECK(result.status == BarrierStatus::Released);
    CHECK(result.releasedWaveCount == 3U);

    ComputeUnitWorkgroupScheduler staggered(Limits(4U));
    CHECK(staggered.Admit(Demand(12U, 4U)) == AdmissionFailure::None);
    CHECK(staggered.ArriveAtBarrier(12U, {3U}).status == BarrierStatus::Waiting);
    CHECK(staggered.ArriveAtBarrier(12U, {3U}).status == BarrierStatus::WaveAlreadyWaiting);
    CHECK(staggered.ArriveAtBarrier(12U, {0U, 0U}).status
        == BarrierStatus::DuplicateWaveInArrival);
    CHECK(staggered.ArriveAtBarrier(12U, {1U, 0U}).status == BarrierStatus::Waiting);
    CHECK(staggered.CanIssue(12U, 2U));
    CHECK(!staggered.CanIssue(12U, 3U));
    const auto selected = staggered.SelectIssuableWave(
        std::vector<bool>(4U, true));
    CHECK(selected.has_value() && *selected == 2U);
    result = staggered.ArriveAtBarrier(12U, {2U});
    CHECK(result.status == BarrierStatus::Released);
    CHECK(result.releasedWaveCount == 4U);

    for (std::uint32_t generation = 1U; generation <= 20U; ++generation)
    {
        CHECK(staggered.BarrierGeneration(12U) == generation);
        CHECK(staggered.ArriveAtBarrier(12U, {2U}).status == BarrierStatus::Waiting);
        CHECK(staggered.ArriveAtBarrier(12U, {0U, 3U}).status == BarrierStatus::Waiting);
        result = staggered.ArriveAtBarrier(12U, {1U});
        CHECK(result.status == BarrierStatus::Released);
    }
    CHECK(staggered.BarrierGeneration(12U) == 21U);

    ComputeUnitWorkgroupScheduler independent(Limits(4U, 32U, 32U, 1024U, 2U));
    CHECK(independent.Admit(Demand(13U, 2U)) == AdmissionFailure::None);
    CHECK(independent.Admit(Demand(14U, 2U)) == AdmissionFailure::None);
    CHECK(independent.ArriveAtBarrier(13U, {0U}).status == BarrierStatus::Waiting);
    CHECK(independent.CanIssue(14U, 0U));
    CHECK(independent.CanIssue(14U, 1U));
    CHECK(independent.SelectIssuableWave(std::vector<bool>(4U, true)).has_value());
    return 0;
}

int TestFragmentationAndLifecycle()
{
    ComputeUnitWorkgroupScheduler fragmented(Limits(8U, 8U, 32U, 2048U, 6U));
    for (std::uint64_t id = 1U; id <= 4U; ++id)
        CHECK(fragmented.Admit(Demand(id, 1U, 16U)) == AdmissionFailure::None);
    CHECK(fragmented.KillWorkgroup(2U));
    CHECK(fragmented.KillWorkgroup(4U));
    CHECK(fragmented.OccupiedVgprRows() == 4U);
    CHECK(fragmented.Admit(Demand(5U, 1U, 17U))
        == AdmissionFailure::VgprCapacityFragmented);
    CHECK(fragmented.ResidentWaveCount() == 2U);

    ComputeUnitWorkgroupScheduler lifecycle(Limits(4U, 32U, 32U, 2048U, 2U, 32U));
    CHECK(lifecycle.Admit(Demand(20U, 3U, 16U, 4U, 1024U, 8U))
        == AdmissionFailure::None);
    CHECK(lifecycle.ArriveAtBarrier(20U, {0U, 1U}).status == BarrierStatus::Waiting);
    CHECK(lifecycle.TerminateWave(20U, 2U));
    CHECK(lifecycle.BarrierGeneration(20U) == 1U);
    CHECK(lifecycle.CanIssue(20U, 0U) && lifecycle.CanIssue(20U, 1U));
    CHECK(lifecycle.ResidentWaveCount() == 2U);
    CHECK(lifecycle.UsedSharedLocalBytes() == 1024U);
    CHECK(lifecycle.TerminateWave(20U, 0U));
    CHECK(lifecycle.UsedScalarPredicateUnits() == 4U);
    CHECK(lifecycle.TerminateWave(20U, 1U));
    CHECK(lifecycle.WorkgroupCount() == 0U);
    CHECK(lifecycle.ResidentWaveCount() == 0U);
    CHECK(lifecycle.OccupiedVgprRows() == 0U);
    CHECK(lifecycle.UsedScalarPredicateUnits() == 0U);
    CHECK(lifecycle.UsedSharedLocalBytes() == 0U);
    CHECK(lifecycle.UsedOtherWorkgroupUnits() == 0U);

    CHECK(lifecycle.Admit(Demand(25U, 3U, 16U, 2U, 256U, 2U))
        == AdmissionFailure::None);
    CHECK(lifecycle.ArriveAtBarrier(25U, {0U, 2U}).status == BarrierStatus::Waiting);
    CHECK(lifecycle.TerminateWave(25U, 2U));
    auto afterFaultedWaiter = lifecycle.GetWorkgroupState(25U);
    CHECK(afterFaultedWaiter.liveWaves[0] && afterFaultedWaiter.waitingWaves[0]);
    CHECK(afterFaultedWaiter.liveWaves[1] && !afterFaultedWaiter.waitingWaves[1]);
    CHECK(!afterFaultedWaiter.liveWaves[2] && !afterFaultedWaiter.waitingWaves[2]);
    CHECK(lifecycle.CanIssue(25U, 1U));
    CHECK(lifecycle.ArriveAtBarrier(25U, {1U}).status == BarrierStatus::Released);
    CHECK(lifecycle.BarrierGeneration(25U) == 1U);
    CHECK(lifecycle.KillWorkgroup(25U));

    for (const bool fault : {false, true})
    {
        const std::uint64_t id = fault ? 22U : 21U;
        CHECK(lifecycle.Admit(Demand(id, 3U, 32U, 3U, 512U, 2U))
            == AdmissionFailure::None);
        CHECK(lifecycle.ArriveAtBarrier(id, {0U, 2U}).status == BarrierStatus::Waiting);
        CHECK((fault ? lifecycle.FaultWorkgroup(id) : lifecycle.KillWorkgroup(id)));
        CHECK(!lifecycle.CanIssue(id, 1U));
        CHECK(lifecycle.WorkgroupCount() == 0U);
        CHECK(lifecycle.ResidentWaveCount() == 0U);
        CHECK(lifecycle.OccupiedVgprRows() == 0U);
        CHECK(lifecycle.UsedSharedLocalBytes() == 0U);
    }

    CHECK(lifecycle.Admit(Demand(23U, 2U)) == AdmissionFailure::None);
    CHECK(lifecycle.ArriveAtBarrier(23U, {1U}).status == BarrierStatus::Waiting);
    lifecycle.Reset();
    CHECK(lifecycle.WorkgroupCount() == 0U);
    CHECK(lifecycle.ResidentWaveCount() == 0U);
    CHECK(lifecycle.OccupiedVgprRows() == 0U);
    CHECK(lifecycle.CheckInvariants());
    CHECK(lifecycle.Admit(Demand(24U, 4U)) == AdmissionFailure::None);
    return 0;
}

int TestRandomizedForwardProgress()
{
    ComputeUnitWorkgroupScheduler scheduler(Limits(16U, 128U, 512U, 8192U, 8U, 256U));
    std::mt19937 random(0xC671BA22U);
    std::uint64_t nextId = 1000U;
    for (std::uint32_t cycle = 0U; cycle < 100000U; ++cycle)
    {
        const auto ids = scheduler.ActiveWorkgroupIds();
        const auto action = random() % 100U;
        if (action < 26U)
        {
            const auto waves = 1U + (random() % 5U);
            const auto registers = 1U + (random() % 256U);
            const auto scalar = random() % 9U;
            const auto shared = random() % 2049U;
            const auto other = random() % 17U;
            (void)scheduler.Admit(Demand(
                nextId++, waves, registers, scalar, shared, other));
        }
        else if (!ids.empty() && action < 72U)
        {
            const auto id = ids[random() % ids.size()];
            const auto state = scheduler.GetWorkgroupState(id);
            std::vector<std::uint32_t> arrivals;
            for (std::uint32_t wave = 0U; wave < state.liveWaves.size(); ++wave)
            {
                if (state.liveWaves[wave] && !state.waitingWaves[wave]
                    && ((random() & 3U) == 0U))
                    arrivals.push_back(wave);
            }
            if (!arrivals.empty())
                (void)scheduler.ArriveAtBarrier(id, arrivals);
        }
        else if (!ids.empty() && action < 90U)
        {
            const auto id = ids[random() % ids.size()];
            const auto state = scheduler.GetWorkgroupState(id);
            std::vector<std::uint32_t> live;
            for (std::uint32_t wave = 0U; wave < state.liveWaves.size(); ++wave)
                if (state.liveWaves[wave]) live.push_back(wave);
            if (!live.empty())
                (void)scheduler.TerminateWave(id, live[random() % live.size()]);
        }
        else if (!ids.empty() && action < 98U)
        {
            const auto id = ids[random() % ids.size()];
            (void)((random() & 1U)
                ? scheduler.KillWorkgroup(id)
                : scheduler.FaultWorkgroup(id));
        }
        else if ((random() & 63U) == 0U)
        {
            scheduler.Reset();
        }

        CHECK(scheduler.CheckInvariants());
        CHECK(scheduler.ResidentWaveCount() <= 16U);
        CHECK(scheduler.OccupiedVgprRows() <= 128U);
        CHECK(scheduler.UsedScalarPredicateUnits() <= 512U);
        CHECK(scheduler.UsedSharedLocalBytes() <= 8192U);
        CHECK(scheduler.UsedOtherWorkgroupUnits() <= 256U);
        for (const auto id : scheduler.ActiveWorkgroupIds())
        {
            const auto state = scheduler.GetWorkgroupState(id);
            CHECK(scheduler.AllLiveWavesResident(id));
            bool liveWaveCanIssue = false;
            for (std::uint32_t wave = 0U; wave < state.liveWaves.size(); ++wave)
            {
                if (state.liveWaves[wave] && !state.waitingWaves[wave])
                    liveWaveCanIssue = true;
            }
            CHECK(liveWaveCanIssue);
        }
    }
    return 0;
}

int main()
{
    if (TestAdmissionAndResourceBoundaries() != 0) return 1;
    if (TestBarrierArrivalsAndIssue() != 0) return 1;
    if (TestFragmentationAndLifecycle() != 0) return 1;
    if (TestRandomizedForwardProgress() != 0) return 1;
    std::cout << "[pass] whole-workgroup residency, resource admission, barriers, lifecycle, and randomized forward progress passed.\n";
    return 0;
}
