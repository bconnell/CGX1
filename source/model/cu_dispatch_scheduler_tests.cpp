// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_context.hpp"
#include "cu_dispatch_scheduler.hpp"

#include <array>
#include <cstdint>
#include <iostream>
#include <random>
#include <vector>

#define CHECK(x) do { if (!(x)) { std::cerr << "[fail] " #x " line " << __LINE__; ::cgx1::testing::WriteRandomTestFailureContext(std::cerr); std::cerr << '\n'; return 1; } } while (false)

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
    {
        auto&& check_action_registerqueuecontext_70_1 = (scheduler.RegisterQueueContext(Queue(64U)));
        CHECK(check_action_registerqueuecontext_70_1 == QueueRegistrationStatus::InvalidContextId);
    }
    {
        auto&& check_action_registerqueuecontext_71_2 = (scheduler.RegisterQueueContext(Queue(0U, 8U)));
        CHECK(check_action_registerqueuecontext_71_2 == QueueRegistrationStatus::InvalidPriority);
    }
    {
        auto&& check_action_registerqueuecontext_72_3 = (scheduler.RegisterQueueContext(Queue(0U, 3U, 0x100U, 0x200U, false,
        DispatchEngineClass::Graphics)));
        CHECK(check_action_registerqueuecontext_72_3 == QueueRegistrationStatus::UnsupportedEngine);
    }
    {
        auto&& check_action_registerqueuecontext_74_4 = (scheduler.RegisterQueueContext(Queue(0U)));
        CHECK(check_action_registerqueuecontext_74_4 == QueueRegistrationStatus::Registered);
    }
    {
        auto&& check_action_registerqueuecontext_75_5 = (scheduler.RegisterQueueContext(Queue(0U, 3U, 0x101U)));
        CHECK(check_action_registerqueuecontext_75_5 == QueueRegistrationStatus::DuplicateContextId);
    }
    {
        auto&& check_action_registerqueuecontext_76_6 = (scheduler.RegisterQueueContext(Queue(1U)));
        CHECK(check_action_registerqueuecontext_76_6 == QueueRegistrationStatus::ContextCapacityReached);
    }
    {
        auto&& check_action_enqueueworkgroup_77_7 = (scheduler.EnqueueWorkgroup(1U, Demand(1U)));
        CHECK(check_action_enqueueworkgroup_77_7 == EnqueueWorkgroupStatus::UnknownQueueContext);
    }
    {
        auto&& check_action_enqueueworkgroup_78_8 = (scheduler.EnqueueWorkgroup(0U, Demand(1U)));
        CHECK(check_action_enqueueworkgroup_78_8 == EnqueueWorkgroupStatus::Queued);
    }
    {
        auto&& check_action_enqueueworkgroup_79_9 = (scheduler.EnqueueWorkgroup(0U, Demand(2U)));
        CHECK(check_action_enqueueworkgroup_79_9 == EnqueueWorkgroupStatus::QueueFull);
    }
    CHECK(scheduler.PendingWorkgroupCount() == 1U);

    ComputeUnitDispatchScheduler lastContext(Limits(), Policy(64U, 1U));
    {
        auto&& check_action_registerqueuecontext_83_10 = (lastContext.RegisterQueueContext(Queue(63U)));
        CHECK(check_action_registerqueuecontext_83_10
        == QueueRegistrationStatus::Registered);
    }
    DispatchPolicy overCapacity = Policy();
    overCapacity.maximumQueueContexts = kHardwareQueueContextCount + 1U;
    bool rejectedCapacity = false;
    try { ComputeUnitDispatchScheduler invalid(Limits(), overCapacity); }
    catch (const std::invalid_argument&) { rejectedCapacity = true; }
    CHECK(rejectedCapacity);
    return 0;
}

int TestTileEligibilityAndQuiescentCompletion()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), Policy());
    {
        auto&& check_action_registerqueuecontext_97_11 = (scheduler.RegisterQueueContext(Queue(1U)));
        CHECK(check_action_registerqueuecontext_97_11 == QueueRegistrationStatus::Registered);
    }
    {
        auto&& check_action_enqueueworkgroup_98_12 = (scheduler.EnqueueWorkgroup(1U, Demand(11U, 2U)));
        CHECK(check_action_enqueueworkgroup_98_12 == EnqueueWorkgroupStatus::Queued);
    }
    const auto gated = scheduler.ScheduleOneCycle(false);
    CHECK(gated.status == DispatchCycleStatus::TileIneligible);
    CHECK(scheduler.PendingWorkgroupCount() == 1U);
    CHECK(scheduler.Workgroups().WorkgroupCount() == 0U);

    const auto admitted = scheduler.ScheduleOneCycle(true);
    CHECK(admitted.status == DispatchCycleStatus::Admitted);
    CHECK(admitted.queueContextId == 1U && admitted.workgroupId == 11U);
    CHECK(scheduler.Workgroups().AllLiveWavesResident(11U));
    {
        auto&& check_action_enqueueworkgroup_108_13 = (scheduler.EnqueueWorkgroup(1U, Demand(11U)));
        CHECK(check_action_enqueueworkgroup_108_13
        == EnqueueWorkgroupStatus::DuplicateWorkgroupId);
    }
    {
        auto&& check_action_terminatewave_110_14 = (scheduler.Workgroups().TerminateWave(11U, 0U));
        CHECK(check_action_terminatewave_110_14);
    }
    {
        auto&& check_action_terminatewave_111_15 = (scheduler.Workgroups().TerminateWave(11U, 1U));
        CHECK(check_action_terminatewave_111_15);
    }
    CHECK(scheduler.CheckInvariants());
    {
        auto&& check_action_unregisterqueuecontext_113_16 = (scheduler.UnregisterQueueContext(1U));
        CHECK(check_action_unregisterqueuecontext_113_16 == QueueRegistrationStatus::ContextBusy);
    }
    const auto completions = scheduler.CollectRetiredWorkgroups();
    CHECK(completions.size() == 1U);
    CHECK(completions[0].queueContextId == 1U && completions[0].workgroupId == 11U);
    CHECK(scheduler.Workgroups().WorkgroupCount() == 0U);
    CHECK(scheduler.CheckInvariants());
    {
        auto&& check_action_enqueueworkgroup_119_17 = (scheduler.EnqueueWorkgroup(1U, Demand(11U)));
        CHECK(check_action_enqueueworkgroup_119_17 == EnqueueWorkgroupStatus::Queued);
    }
    {
        auto&& check_action_scheduleonecycle_120_18 = (scheduler.ScheduleOneCycle(true));
        CHECK(check_action_scheduleonecycle_120_18.status == DispatchCycleStatus::Admitted);
    }
    {
        auto&& check_action_terminatewave_121_19 = (scheduler.Workgroups().TerminateWave(11U, 0U));
        CHECK(check_action_terminatewave_121_19);
    }
    (void)scheduler.CollectRetiredWorkgroups();
    {
        auto&& check_action_unregisterqueuecontext_123_20 = (scheduler.UnregisterQueueContext(1U));
        CHECK(check_action_unregisterqueuecontext_123_20 == QueueRegistrationStatus::Unregistered);
    }
    return 0;
}

int TestTemporaryPressureDoesNotLoseOrPinOtherContexts()
{
    ComputeUnitDispatchScheduler scheduler(Limits(3U, 32U), Policy(4U, 16U));
    {
        auto&& check_action_registerqueuecontext_130_21 = (scheduler.RegisterQueueContext(Queue(0U, 7U)));
        CHECK(check_action_registerqueuecontext_130_21 == QueueRegistrationStatus::Registered);
    }
    {
        auto&& check_action_registerqueuecontext_131_22 = (scheduler.RegisterQueueContext(Queue(1U, 7U)));
        CHECK(check_action_registerqueuecontext_131_22 == QueueRegistrationStatus::Registered);
    }
    {
        auto&& check_action_enqueueworkgroup_132_23 = (scheduler.EnqueueWorkgroup(0U, Demand(20U, 2U)));
        CHECK(check_action_enqueueworkgroup_132_23 == EnqueueWorkgroupStatus::Queued);
    }
    {
        auto&& check_action_scheduleonecycle_133_24 = (scheduler.ScheduleOneCycle(true));
        CHECK(check_action_scheduleonecycle_133_24.status == DispatchCycleStatus::Admitted);
    }
    {
        auto&& check_action_enqueueworkgroup_134_25 = (scheduler.EnqueueWorkgroup(0U, Demand(21U, 2U)));
        CHECK(check_action_enqueueworkgroup_134_25 == EnqueueWorkgroupStatus::Queued);
    }
    {
        auto&& check_action_scheduleonecycle_135_26 = (scheduler.ScheduleOneCycle(true));
        CHECK(check_action_scheduleonecycle_135_26.status == DispatchCycleStatus::Deferred);
    }
    {
        auto&& check_action_enqueueworkgroup_136_27 = (scheduler.EnqueueWorkgroup(1U, Demand(22U, 1U)));
        CHECK(check_action_enqueueworkgroup_136_27 == EnqueueWorkgroupStatus::Queued);
    }

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
    {
        auto&& check_action_terminatewave_152_28 = (scheduler.Workgroups().TerminateWave(20U, 0U));
        CHECK(check_action_terminatewave_152_28);
    }
    {
        auto&& check_action_terminatewave_153_29 = (scheduler.Workgroups().TerminateWave(20U, 1U));
        CHECK(check_action_terminatewave_153_29);
    }
    {
        auto&& check_action_retireonewave_154_30 = (RetireOneWave(scheduler, 22U));
        CHECK(check_action_retireonewave_154_30 == 0);
    }

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
    {
        auto&& check_action_registerqueuecontext_174_31 = (scheduler.RegisterQueueContext(Queue(2U)));
        CHECK(check_action_registerqueuecontext_174_31 == QueueRegistrationStatus::Registered);
    }
    {
        auto&& check_action_enqueueworkgroup_175_32 = (scheduler.EnqueueWorkgroup(2U, Demand(30U, 3U)));
        CHECK(check_action_enqueueworkgroup_175_32 == EnqueueWorkgroupStatus::Queued);
    }
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
    {
        auto&& check_action_registerqueuecontext_187_33 = (scheduler.RegisterQueueContext(Queue(4U)));
        CHECK(check_action_registerqueuecontext_187_33 == QueueRegistrationStatus::Registered);
    }
    {
        auto&& check_action_enqueueworkgroup_188_34 = (scheduler.EnqueueWorkgroup(4U, Demand(40U)));
        CHECK(check_action_enqueueworkgroup_188_34 == EnqueueWorkgroupStatus::Queued);
    }
    {
        auto&& check_action_scheduleonecycle_189_35 = (scheduler.ScheduleOneCycle(true));
        CHECK(check_action_scheduleonecycle_189_35.status == DispatchCycleStatus::Admitted);
    }
    {
        auto&& check_action_enqueueworkgroup_190_36 = (scheduler.EnqueueWorkgroup(4U, Demand(41U)));
        CHECK(check_action_enqueueworkgroup_190_36 == EnqueueWorkgroupStatus::Queued);
    }

    const auto cancelled = scheduler.Reset();
    CHECK(cancelled.size() == 2U);
    CHECK(cancelled[0].queueContextId == 4U && cancelled[0].workgroupId == 41U
        && !cancelled[0].wasResident);
    CHECK(cancelled[1].queueContextId == 4U && cancelled[1].workgroupId == 40U
        && cancelled[1].wasResident);
    CHECK(scheduler.PendingWorkgroupCount() == 0U);
    CHECK(scheduler.Workgroups().WorkgroupCount() == 0U);
    CHECK(scheduler.CheckInvariants());
    {
        auto&& check_action_enqueueworkgroup_201_37 = (scheduler.EnqueueWorkgroup(4U, Demand(42U)));
        CHECK(check_action_enqueueworkgroup_201_37 == EnqueueWorkgroupStatus::Queued);
    }
    return 0;
}

int TestWeightedShareAndAging()
{
    ComputeUnitDispatchScheduler weighted(Limits(), Policy(2U, 256U, 10000U));
    {
        auto&& check_action_registerqueuecontext_208_38 = (weighted.RegisterQueueContext(Queue(0U, 3U)));
        CHECK(check_action_registerqueuecontext_208_38 == QueueRegistrationStatus::Registered);
    }
    {
        auto&& check_action_registerqueuecontext_209_39 = (weighted.RegisterQueueContext(Queue(1U, 2U)));
        CHECK(check_action_registerqueuecontext_209_39 == QueueRegistrationStatus::Registered);
    }
    for (std::uint64_t id = 100U; id < 356U; ++id)
    {
        {
            auto&& check_action_enqueueworkgroup_212_40 = (weighted.EnqueueWorkgroup(0U, Demand(id)));
            CHECK(check_action_enqueueworkgroup_212_40 == EnqueueWorkgroupStatus::Queued);
        }
        {
            auto&& check_action_enqueueworkgroup_213_41 = (weighted.EnqueueWorkgroup(1U, Demand(id + 1000U)));
            CHECK(check_action_enqueueworkgroup_213_41 == EnqueueWorkgroupStatus::Queued);
        }
    }
    std::array<std::uint32_t, 2U> grants{};
    for (std::uint64_t step = 0U; step < 90U; ++step)
    {
        const auto result = weighted.ScheduleOneCycle(true);
        CHECK(result.status == DispatchCycleStatus::Admitted);
        ++grants[result.queueContextId];
        {
            auto&& check_action_retireonewave_221_42 = (RetireOneWave(weighted, result.workgroupId));
            CHECK(check_action_retireonewave_221_42 == 0);
        }
        (void)weighted.CollectRetiredWorkgroups();
    }
    CHECK(grants[0] >= 58U && grants[0] <= 62U);
    CHECK(grants[1] >= 28U && grants[1] <= 32U);

    ComputeUnitDispatchScheduler aging(Limits(), Policy(2U, 128U, 1U));
    {
        auto&& check_action_registerqueuecontext_228_43 = (aging.RegisterQueueContext(Queue(0U, 7U)));
        CHECK(check_action_registerqueuecontext_228_43 == QueueRegistrationStatus::Registered);
    }
    {
        auto&& check_action_registerqueuecontext_229_44 = (aging.RegisterQueueContext(Queue(1U, 0U)));
        CHECK(check_action_registerqueuecontext_229_44 == QueueRegistrationStatus::Registered);
    }
    for (std::uint64_t id = 500U; id < 560U; ++id)
        {
            auto&& check_action_enqueueworkgroup_231_45 = (aging.EnqueueWorkgroup(0U, Demand(id)));
            CHECK(check_action_enqueueworkgroup_231_45 == EnqueueWorkgroupStatus::Queued);
        }
    for (std::uint64_t id = 1500U; id < 1550U; ++id)
        {
            auto&& check_action_enqueueworkgroup_233_46 = (aging.EnqueueWorkgroup(1U, Demand(id)));
            CHECK(check_action_enqueueworkgroup_233_46 == EnqueueWorkgroupStatus::Queued);
        }
    std::array<std::uint32_t, 2U> agedGrants{};
    for (std::uint32_t step = 0U; step < 40U; ++step)
    {
        const auto result = aging.ScheduleOneCycle(true);
        CHECK(result.status == DispatchCycleStatus::Admitted);
        ++agedGrants[result.queueContextId];
        {
            auto&& check_action_retireonewave_240_47 = (RetireOneWave(aging, result.workgroupId));
            CHECK(check_action_retireonewave_240_47 == 0);
        }
        (void)aging.CollectRetiredWorkgroups();
    }
    CHECK(agedGrants[1] >= 5U);
    return 0;
}

int TestFaultedContextAndDeterministicRandomizedProgress()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), Policy(4U, 128U, 4U));
    for (std::uint8_t id = 0U; id < 4U; ++id)
        {
            auto&& check_action_registerqueuecontext_251_48 = (scheduler.RegisterQueueContext(Queue(id, id)));
            CHECK(check_action_registerqueuecontext_251_48 == QueueRegistrationStatus::Registered);
        }
    {
        auto&& check_action_enqueueworkgroup_252_49 = (scheduler.EnqueueWorkgroup(3U, Demand(900U)));
        CHECK(check_action_enqueueworkgroup_252_49 == EnqueueWorkgroupStatus::Queued);
    }
    {
        auto&& check_action_setqueuefaulted_253_50 = (scheduler.SetQueueFaulted(3U, true));
        CHECK(check_action_setqueuefaulted_253_50);
    }
    const auto faulted = scheduler.ScheduleOneCycle(true);
    CHECK(faulted.status == DispatchCycleStatus::QueueFaulted);
    CHECK(faulted.workgroupId == 900U);
    CHECK(scheduler.PendingWorkgroupCount() == 0U);
    {
        auto&& check_action_setqueuefaulted_258_51 = (scheduler.SetQueueFaulted(3U, false));
        CHECK(check_action_setqueuefaulted_258_51);
    }

    constexpr std::uint32_t seed = 0xC6A1U;
    std::mt19937 random(seed);
    std::uint64_t nextId = 10000U;
    for (std::uint32_t cycle = 0U; cycle < 600U; ++cycle)
    {
        ::cgx1::testing::SetRandomTestFailureContext(
            "TestFaultedContextAndDeterministicRandomizedProgress", seed, cycle);
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
                {
                    auto&& check_action_terminatewave_285_52 = (scheduler.Workgroups().TerminateWave(result.workgroupId, wave));
                    CHECK(check_action_terminatewave_285_52);
                }
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
                        {
                            auto&& check_action_terminatewave_296_53 = (scheduler.Workgroups().TerminateWave(id, wave));
                            CHECK(check_action_terminatewave_296_53);
                        }
                }
            }
            (void)scheduler.CollectRetiredWorkgroups();
        }
        CHECK(scheduler.CheckInvariants());
    }
    ::cgx1::testing::ClearRandomTestFailureContext();
    for (const auto id : scheduler.Workgroups().ActiveWorkgroupIds())
    {
        const auto state = scheduler.Workgroups().GetWorkgroupState(id);
        for (std::uint32_t wave = 0U; wave < state.liveWaves.size(); ++wave)
        {
            if (state.liveWaves[wave])
                {
                    auto&& check_action_terminatewave_310_54 = (scheduler.Workgroups().TerminateWave(id, wave));
                    CHECK(check_action_terminatewave_310_54);
                }
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
                {
                    auto&& check_action_terminatewave_322_55 = (scheduler.Workgroups().TerminateWave(result.workgroupId, wave));
                    CHECK(check_action_terminatewave_322_55);
                }
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
    {
        auto&& check_action_testqueueidentityandbounds_335_56 = (TestQueueIdentityAndBounds());
        CHECK(check_action_testqueueidentityandbounds_335_56 == 0);
    }
    {
        auto&& check_action_testtileeligibilityandquiescentcompletion_336_57 = (TestTileEligibilityAndQuiescentCompletion());
        CHECK(check_action_testtileeligibilityandquiescentcompletion_336_57 == 0);
    }
    {
        auto&& check_action_testtemporarypressuredoesnotloseorpinothercontexts_337_58 = (TestTemporaryPressureDoesNotLoseOrPinOtherContexts());
        CHECK(check_action_testtemporarypressuredoesnotloseorpinothercontexts_337_58 == 0);
    }
    {
        auto&& check_action_testpermanentresourcefailureisreportedandremoved_338_59 = (TestPermanentResourceFailureIsReportedAndRemoved());
        CHECK(check_action_testpermanentresourcefailureisreportedandremoved_338_59 == 0);
    }
    {
        auto&& check_action_testresetreportspendingandresidentdispatchcancellation_339_60 = (TestResetReportsPendingAndResidentDispatchCancellation());
        CHECK(check_action_testresetreportspendingandresidentdispatchcancellation_339_60 == 0);
    }
    {
        auto&& check_action_testweightedshareandaging_340_61 = (TestWeightedShareAndAging());
        CHECK(check_action_testweightedshareandaging_340_61 == 0);
    }
    {
        auto&& check_action_testfaultedcontextanddeterministicrandomizedprogress_341_62 = (TestFaultedContextAndDeterministicRandomizedProgress());
        CHECK(check_action_testfaultedcontextanddeterministicrandomizedprogress_341_62 == 0);
    }
    std::cout << "CGX1 CU dispatch scheduler checks passed.\n";
    return 0;
}
