// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cu_dispatch_scheduler.hpp"

#include <array>
#include <cstdint>
#include <iostream>
#include <random>
#include <vector>

#define CHECK(x) do { if (!(x)) { std::cerr << "[fail] " #x " line " << __LINE__ << '\n'; return 1; } } while (false)

using namespace cgx1::compute;

namespace {

CuResourceLimits Limits(
    std::uint32_t waveSlots = 4U,
    std::uint32_t vgprRows = 32U,
    std::uint32_t scalarUnits = 64U,
    std::uint32_t sharedBytes = 1024U,
    std::uint32_t barrierContexts = 4U,
    std::uint32_t otherUnits = 16U)
{
    return {waveSlots, vgprRows, scalarUnits, sharedBytes, barrierContexts, otherUnits};
}

DispatchPolicy Policy(
    std::uint32_t contexts = 4U,
    std::uint32_t pendingPerContext = 32U,
    std::uint32_t agingInterval = 64U)
{
    DispatchPolicy policy;
    policy.maximumQueueContexts = contexts;
    policy.pendingWorkgroupsPerContext = pendingPerContext;
    policy.agingIntervalCycles = agingInterval;
    policy.priorityWeights = {1U, 2U, 4U, 8U, 16U, 32U, 64U, 128U};
    return policy;
}

DispatchQueueContext Queue(
    std::uint8_t id,
    std::uint8_t priority = 3U,
    std::uint64_t process = 0x100U,
    std::uint64_t addressSpace = 0x200U,
    bool faulted = false,
    DispatchEngineClass engine = DispatchEngineClass::Compute)
{
    return {id, process, addressSpace, priority, engine, faulted};
}

WorkgroupDemand Demand(
    std::uint64_t id,
    std::uint32_t waves = 1U,
    std::uint32_t registers = 16U,
    std::uint32_t sharedBytes = 0U)
{
    return {id, waves, registers, 1U, sharedBytes, 0U, {}};
}

int RetireOneWave(ComputeUnitDispatchScheduler& scheduler, std::uint64_t id)
{
    return scheduler.Workgroups().TerminateWave(id, 0U) ? 0 : 1;
}

int TestQueueIdentityAndBounds()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), Policy(1U, 1U));
    CHECK(scheduler.RegisterQueueContext(Queue(64U)) == QueueRegistrationStatus::InvalidContextId);
    CHECK(scheduler.RegisterQueueContext(Queue(0U, 8U)) == QueueRegistrationStatus::InvalidPriority);
    CHECK(scheduler.RegisterQueueContext(Queue(0U, 3U, 0x100U, 0x200U, false,
        DispatchEngineClass::Graphics)) == QueueRegistrationStatus::UnsupportedEngine);
    CHECK(scheduler.RegisterQueueContext(Queue(0U)) == QueueRegistrationStatus::Registered);
    CHECK(scheduler.RegisterQueueContext(Queue(0U, 3U, 0x101U)) == QueueRegistrationStatus::DuplicateContextId);
    CHECK(scheduler.RegisterQueueContext(Queue(1U)) == QueueRegistrationStatus::ContextCapacityReached);
    CHECK(scheduler.EnqueueWorkgroup(1U, Demand(1U)) == EnqueueWorkgroupStatus::UnknownQueueContext);
    CHECK(scheduler.EnqueueWorkgroup(0U, Demand(1U)) == EnqueueWorkgroupStatus::Queued);
    CHECK(scheduler.EnqueueWorkgroup(0U, Demand(2U)) == EnqueueWorkgroupStatus::QueueFull);
    CHECK(scheduler.PendingWorkgroupCount() == 1U);
    return 0;
}

int TestTileEligibilityAndQuiescentCompletion()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), Policy());
    CHECK(scheduler.RegisterQueueContext(Queue(1U)) == QueueRegistrationStatus::Registered);
    CHECK(scheduler.EnqueueWorkgroup(1U, Demand(11U, 2U)) == EnqueueWorkgroupStatus::Queued);
    const auto gated = scheduler.ScheduleOneCycle(false);
    CHECK(gated.status == DispatchCycleStatus::TileIneligible);
    CHECK(scheduler.PendingWorkgroupCount() == 1U);
    CHECK(scheduler.Workgroups().WorkgroupCount() == 0U);

    const auto admitted = scheduler.ScheduleOneCycle(true);
    CHECK(admitted.status == DispatchCycleStatus::Admitted);
    CHECK(admitted.queueContextId == 1U && admitted.workgroupId == 11U);
    CHECK(scheduler.Workgroups().AllLiveWavesResident(11U));
    CHECK(scheduler.EnqueueWorkgroup(1U, Demand(11U))
        == EnqueueWorkgroupStatus::DuplicateWorkgroupId);
    CHECK(scheduler.Workgroups().TerminateWave(11U, 0U));
    CHECK(scheduler.Workgroups().TerminateWave(11U, 1U));
    CHECK(scheduler.CheckInvariants());
    CHECK(scheduler.UnregisterQueueContext(1U) == QueueRegistrationStatus::ContextBusy);
    const auto completions = scheduler.CollectRetiredWorkgroups();
    CHECK(completions.size() == 1U);
    CHECK(completions[0].queueContextId == 1U && completions[0].workgroupId == 11U);
    CHECK(scheduler.Workgroups().WorkgroupCount() == 0U);
    CHECK(scheduler.CheckInvariants());
    CHECK(scheduler.EnqueueWorkgroup(1U, Demand(11U)) == EnqueueWorkgroupStatus::Queued);
    CHECK(scheduler.ScheduleOneCycle(true).status == DispatchCycleStatus::Admitted);
    CHECK(scheduler.Workgroups().TerminateWave(11U, 0U));
    (void)scheduler.CollectRetiredWorkgroups();
    CHECK(scheduler.UnregisterQueueContext(1U) == QueueRegistrationStatus::Unregistered);
    return 0;
}

int TestTemporaryPressureDoesNotLoseOrPinOtherContexts()
{
    ComputeUnitDispatchScheduler scheduler(Limits(3U, 32U), Policy(4U, 16U));
    CHECK(scheduler.RegisterQueueContext(Queue(0U, 7U)) == QueueRegistrationStatus::Registered);
    CHECK(scheduler.RegisterQueueContext(Queue(1U, 7U)) == QueueRegistrationStatus::Registered);
    CHECK(scheduler.EnqueueWorkgroup(0U, Demand(20U, 2U)) == EnqueueWorkgroupStatus::Queued);
    CHECK(scheduler.ScheduleOneCycle(true).status == DispatchCycleStatus::Admitted);
    CHECK(scheduler.EnqueueWorkgroup(0U, Demand(21U, 2U)) == EnqueueWorkgroupStatus::Queued);
    CHECK(scheduler.ScheduleOneCycle(true).status == DispatchCycleStatus::Deferred);
    CHECK(scheduler.EnqueueWorkgroup(1U, Demand(22U, 1U)) == EnqueueWorkgroupStatus::Queued);

    bool siblingAdmitted = false;
    for (std::uint32_t cycle = 0U; cycle < 16U; ++cycle)
    {
        const auto result = scheduler.ScheduleOneCycle(true);
        if (result.status == DispatchCycleStatus::Admitted && result.workgroupId == 22U)
        {
            siblingAdmitted = true;
            break;
        }
        CHECK(result.status == DispatchCycleStatus::Deferred
            || result.status == DispatchCycleStatus::Admitted);
    }
    CHECK(siblingAdmitted);
    CHECK(scheduler.PendingWorkgroupCount() == 1U);
    CHECK(scheduler.Workgroups().TerminateWave(20U, 0U));
    CHECK(scheduler.Workgroups().TerminateWave(20U, 1U));
    CHECK(RetireOneWave(scheduler, 22U) == 0);

    bool retryAdmitted = false;
    for (std::uint32_t cycle = 0U; cycle < 16U; ++cycle)
    {
        const auto result = scheduler.ScheduleOneCycle(true);
        if (result.status == DispatchCycleStatus::Admitted && result.workgroupId == 21U)
        {
            retryAdmitted = true;
            break;
        }
    }
    CHECK(retryAdmitted);
    CHECK(scheduler.Workgroups().AllLiveWavesResident(21U));
    return 0;
}

int TestPermanentResourceFailureIsReportedAndRemoved()
{
    ComputeUnitDispatchScheduler scheduler(Limits(2U, 16U), Policy());
    CHECK(scheduler.RegisterQueueContext(Queue(2U)) == QueueRegistrationStatus::Registered);
    CHECK(scheduler.EnqueueWorkgroup(2U, Demand(30U, 3U)) == EnqueueWorkgroupStatus::Queued);
    const auto result = scheduler.ScheduleOneCycle(true);
    CHECK(result.status == DispatchCycleStatus::Rejected);
    CHECK(result.failure == AdmissionFailure::WorkgroupExceedsResidentWaveCapacity);
    CHECK(scheduler.PendingWorkgroupCount() == 0U);
    CHECK(scheduler.Workgroups().WorkgroupCount() == 0U);
    return 0;
}

int TestResetReportsPendingAndResidentDispatchCancellation()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), Policy());
    CHECK(scheduler.RegisterQueueContext(Queue(4U)) == QueueRegistrationStatus::Registered);
    CHECK(scheduler.EnqueueWorkgroup(4U, Demand(40U)) == EnqueueWorkgroupStatus::Queued);
    CHECK(scheduler.ScheduleOneCycle(true).status == DispatchCycleStatus::Admitted);
    CHECK(scheduler.EnqueueWorkgroup(4U, Demand(41U)) == EnqueueWorkgroupStatus::Queued);

    const auto cancelled = scheduler.Reset();
    CHECK(cancelled.size() == 2U);
    CHECK(cancelled[0].queueContextId == 4U && cancelled[0].workgroupId == 41U
        && !cancelled[0].wasResident);
    CHECK(cancelled[1].queueContextId == 4U && cancelled[1].workgroupId == 40U
        && cancelled[1].wasResident);
    CHECK(scheduler.PendingWorkgroupCount() == 0U);
    CHECK(scheduler.Workgroups().WorkgroupCount() == 0U);
    CHECK(scheduler.CheckInvariants());
    CHECK(scheduler.EnqueueWorkgroup(4U, Demand(42U)) == EnqueueWorkgroupStatus::Queued);
    return 0;
}

int TestWeightedShareAndAging()
{
    ComputeUnitDispatchScheduler weighted(Limits(), Policy(2U, 256U, 10000U));
    CHECK(weighted.RegisterQueueContext(Queue(0U, 3U)) == QueueRegistrationStatus::Registered);
    CHECK(weighted.RegisterQueueContext(Queue(1U, 2U)) == QueueRegistrationStatus::Registered);
    for (std::uint64_t id = 100U; id < 356U; ++id)
    {
        CHECK(weighted.EnqueueWorkgroup(0U, Demand(id)) == EnqueueWorkgroupStatus::Queued);
        CHECK(weighted.EnqueueWorkgroup(1U, Demand(id + 1000U)) == EnqueueWorkgroupStatus::Queued);
    }
    std::array<std::uint32_t, 2U> grants{};
    for (std::uint64_t step = 0U; step < 90U; ++step)
    {
        const auto result = weighted.ScheduleOneCycle(true);
        CHECK(result.status == DispatchCycleStatus::Admitted);
        ++grants[result.queueContextId];
        CHECK(RetireOneWave(weighted, result.workgroupId) == 0);
        (void)weighted.CollectRetiredWorkgroups();
    }
    CHECK(grants[0] >= 58U && grants[0] <= 62U);
    CHECK(grants[1] >= 28U && grants[1] <= 32U);

    ComputeUnitDispatchScheduler aging(Limits(), Policy(2U, 128U, 1U));
    CHECK(aging.RegisterQueueContext(Queue(0U, 7U)) == QueueRegistrationStatus::Registered);
    CHECK(aging.RegisterQueueContext(Queue(1U, 0U)) == QueueRegistrationStatus::Registered);
    for (std::uint64_t id = 500U; id < 560U; ++id)
        CHECK(aging.EnqueueWorkgroup(0U, Demand(id)) == EnqueueWorkgroupStatus::Queued);
    for (std::uint64_t id = 1500U; id < 1550U; ++id)
        CHECK(aging.EnqueueWorkgroup(1U, Demand(id)) == EnqueueWorkgroupStatus::Queued);
    std::array<std::uint32_t, 2U> agedGrants{};
    for (std::uint32_t step = 0U; step < 40U; ++step)
    {
        const auto result = aging.ScheduleOneCycle(true);
        CHECK(result.status == DispatchCycleStatus::Admitted);
        ++agedGrants[result.queueContextId];
        CHECK(RetireOneWave(aging, result.workgroupId) == 0);
        (void)aging.CollectRetiredWorkgroups();
    }
    CHECK(agedGrants[1] >= 5U);
    return 0;
}

int TestFaultedContextAndDeterministicRandomizedProgress()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), Policy(4U, 128U, 4U));
    for (std::uint8_t id = 0U; id < 4U; ++id)
        CHECK(scheduler.RegisterQueueContext(Queue(id, id)) == QueueRegistrationStatus::Registered);
    CHECK(scheduler.EnqueueWorkgroup(3U, Demand(900U)) == EnqueueWorkgroupStatus::Queued);
    CHECK(scheduler.SetQueueFaulted(3U, true));
    const auto faulted = scheduler.ScheduleOneCycle(true);
    CHECK(faulted.status == DispatchCycleStatus::QueueFaulted);
    CHECK(faulted.workgroupId == 900U);
    CHECK(scheduler.PendingWorkgroupCount() == 0U);
    CHECK(scheduler.SetQueueFaulted(3U, false));

    std::mt19937 random(0xC6A1U);
    std::uint64_t nextId = 10000U;
    for (std::uint32_t cycle = 0U; cycle < 600U; ++cycle)
    {
        if ((random() % 3U) == 0U)
        {
            const auto queue = static_cast<std::uint8_t>(random() % 4U);
            const auto waves = 1U + (random() % 4U);
            const auto status = scheduler.EnqueueWorkgroup(queue, Demand(nextId++, waves));
            CHECK(status == EnqueueWorkgroupStatus::Queued || status == EnqueueWorkgroupStatus::QueueFull);
        }
        const auto result = scheduler.ScheduleOneCycle((random() % 5U) != 0U);
        CHECK(result.status == DispatchCycleStatus::Idle
            || result.status == DispatchCycleStatus::TileIneligible
            || result.status == DispatchCycleStatus::Deferred
            || result.status == DispatchCycleStatus::Admitted
            || result.status == DispatchCycleStatus::Rejected
            || result.status == DispatchCycleStatus::QueueFaulted);
        if (result.status == DispatchCycleStatus::Admitted && (random() % 2U) == 0U)
        {
            const auto state = scheduler.Workgroups().GetWorkgroupState(result.workgroupId);
            for (std::uint32_t wave = 0U; wave < state.liveWaves.size(); ++wave)
                CHECK(scheduler.Workgroups().TerminateWave(result.workgroupId, wave));
            (void)scheduler.CollectRetiredWorkgroups();
        }
        if ((cycle % 7U) == 0U)
        {
            for (const auto id : scheduler.Workgroups().ActiveWorkgroupIds())
            {
                const auto state = scheduler.Workgroups().GetWorkgroupState(id);
                for (std::uint32_t wave = 0U; wave < state.liveWaves.size(); ++wave)
                {
                    if (state.liveWaves[wave])
                        CHECK(scheduler.Workgroups().TerminateWave(id, wave));
                }
            }
            (void)scheduler.CollectRetiredWorkgroups();
        }
        CHECK(scheduler.CheckInvariants());
    }
    for (const auto id : scheduler.Workgroups().ActiveWorkgroupIds())
    {
        const auto state = scheduler.Workgroups().GetWorkgroupState(id);
        for (std::uint32_t wave = 0U; wave < state.liveWaves.size(); ++wave)
        {
            if (state.liveWaves[wave])
                CHECK(scheduler.Workgroups().TerminateWave(id, wave));
        }
    }
    (void)scheduler.CollectRetiredWorkgroups();
    for (std::uint32_t cycle = 0U; cycle < 1000U && scheduler.PendingWorkgroupCount() != 0U; ++cycle)
    {
        const auto result = scheduler.ScheduleOneCycle(true);
        CHECK(result.status != DispatchCycleStatus::TileIneligible);
        if (result.status == DispatchCycleStatus::Admitted)
        {
            const auto state = scheduler.Workgroups().GetWorkgroupState(result.workgroupId);
            for (std::uint32_t wave = 0U; wave < state.liveWaves.size(); ++wave)
                CHECK(scheduler.Workgroups().TerminateWave(result.workgroupId, wave));
            (void)scheduler.CollectRetiredWorkgroups();
        }
    }
    CHECK(scheduler.PendingWorkgroupCount() == 0U);
    CHECK(scheduler.CheckInvariants());
    return 0;
}

} // namespace

int main()
{
    CHECK(TestQueueIdentityAndBounds() == 0);
    CHECK(TestTileEligibilityAndQuiescentCompletion() == 0);
    CHECK(TestTemporaryPressureDoesNotLoseOrPinOtherContexts() == 0);
    CHECK(TestPermanentResourceFailureIsReportedAndRemoved() == 0);
    CHECK(TestResetReportsPendingAndResidentDispatchCancellation() == 0);
    CHECK(TestWeightedShareAndAging() == 0);
    CHECK(TestFaultedContextAndDeterministicRandomizedProgress() == 0);
    std::cout << "CGX1 CU dispatch scheduler checks passed.\n";
    return 0;
}
