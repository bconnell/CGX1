// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_context.hpp"
#include "workgroup_scheduler.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <random>
#include <stdexcept>
#include <vector>

#define CHECK(x) do { if (!(x)) { std::cerr << "[fail] " #x " line " << __LINE__; ::cgx1::testing::WriteRandomTestFailureContext(std::cerr); std::cerr << '\n'; return 1; } } while (false)

using namespace cgx1::compute;
using cgx1::memory::AccessKind;
using cgx1::memory::MemoryRequest;
using cgx1::memory::SubmitStatus;

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
        id, waves, vgprs, scalarPerWave, sharedBytes, otherUnits, {}};
}

MemoryRequest LocalMemoryRequest(
    std::uint64_t workgroupId,
    std::uint32_t waveId,
    std::uint64_t tag,
    AccessKind access,
    std::uint32_t laneMask,
    const std::array<std::uint32_t, 32U>& addresses,
    const std::array<std::uint32_t, 32U>& data = {})
{
    return {workgroupId, waveId, tag, access, laneMask, addresses, data};
}

int TestAdmissionAndResourceBoundaries()
{
    ComputeUnitWorkgroupScheduler scheduler(Limits(4U, 32U, 40U, 4096U, 1U, 9U));
    const auto maximum = Demand(1U, 4U, 64U, 10U, 4096U, 9U);
    {
        auto&& check_action_admit_62_1 = (scheduler.Admit(maximum));
        CHECK(check_action_admit_62_1 == AdmissionFailure::None);
    }
    CHECK(scheduler.ResidentWaveCount() == 4U);
    CHECK(scheduler.OccupiedVgprRows() == 32U);
    CHECK(scheduler.UsedScalarPredicateUnits() == 40U);
    CHECK(scheduler.UsedSharedLocalBytes() == 4096U);
    CHECK(scheduler.UsedOtherWorkgroupUnits() == 9U);
    CHECK(scheduler.AllLiveWavesResident(1U));
    const auto maximumRegion = scheduler.SharedLocalMemoryRegionForWorkgroup(1U);
    CHECK(maximumRegion.has_value());
    CHECK(maximumRegion->byteCount == 4096U);

    ComputeUnitWorkgroupScheduler vgpr(Limits(4U, 63U));
    {
        auto&& check_action_admit_74_2 = (vgpr.Admit(Demand(2U, 2U, 256U)));
        CHECK(check_action_admit_74_2
        == AdmissionFailure::VgprDemandExceedsCuCapacity);
    }
    CHECK(vgpr.ResidentWaveCount() == 0U);

    ComputeUnitWorkgroupScheduler shared(Limits(4U, 32U, 32U, 1024U));
    {
        auto&& check_action_admit_79_3 = (shared.Admit(Demand(3U, 1U, 16U, 1U, 1024U)));
        CHECK(check_action_admit_79_3
        == AdmissionFailure::None);
    }
    CHECK(shared.UsedSharedLocalBytes() == 1024U);
    {
        auto&& check_action_admit_82_4 = (shared.Admit(Demand(4U, 1U, 16U, 1U, 1U)));
        CHECK(check_action_admit_82_4
        == AdmissionFailure::SharedLocalMemoryUnavailable);
    }
    CHECK(shared.ResidentWaveCount() == 1U);

    ComputeUnitWorkgroupScheduler sharedBusy(Limits(4U, 32U, 32U, 1024U, 2U));
    {
        auto&& check_action_admit_87_5 = (sharedBusy.Admit(Demand(30U, 2U, 16U, 2U, 700U)));
        CHECK(check_action_admit_87_5
        == AdmissionFailure::None);
    }
    {
        auto&& check_action_admit_89_6 = (sharedBusy.Admit(Demand(31U, 1U, 16U, 2U, 400U)));
        CHECK(check_action_admit_89_6
        == AdmissionFailure::SharedLocalMemoryUnavailable);
    }

    ComputeUnitWorkgroupScheduler vgprBusy(Limits(4U, 4U, 32U, 1024U, 2U));
    {
        auto&& check_action_admit_93_7 = (vgprBusy.Admit(Demand(32U, 2U, 16U)));
        CHECK(check_action_admit_93_7 == AdmissionFailure::None);
    }
    {
        auto&& check_action_admit_94_8 = (vgprBusy.Admit(Demand(33U, 1U, 1U)));
        CHECK(check_action_admit_94_8
        == AdmissionFailure::VgprCapacityUnavailable);
    }

    ComputeUnitWorkgroupScheduler otherBusy(Limits(4U, 32U, 32U, 1024U, 2U, 10U));
    {
        auto&& check_action_admit_98_9 = (otherBusy.Admit(Demand(34U, 1U, 16U, 1U, 0U, 7U)));
        CHECK(check_action_admit_98_9
        == AdmissionFailure::None);
    }
    {
        auto&& check_action_admit_100_10 = (otherBusy.Admit(Demand(35U, 1U, 16U, 1U, 0U, 4U)));
        CHECK(check_action_admit_100_10
        == AdmissionFailure::OtherWorkgroupStateUnavailable);
    }

    ComputeUnitWorkgroupScheduler state(Limits(4U, 32U, 15U));
    {
        auto&& check_action_admit_104_11 = (state.Admit(Demand(4U, 2U, 16U, 8U)));
        CHECK(check_action_admit_104_11
        == AdmissionFailure::ScalarPredicateStateExceedsCuCapacity);
    }

    ComputeUnitWorkgroupScheduler scalarBusy(Limits(4U, 32U, 8U, 1024U, 2U));
    {
        auto&& check_action_admit_108_12 = (scalarBusy.Admit(Demand(40U, 2U, 16U, 4U)));
        CHECK(check_action_admit_108_12
        == AdmissionFailure::None);
    }
    {
        auto&& check_action_admit_110_13 = (scalarBusy.Admit(Demand(41U, 1U, 16U, 1U)));
        CHECK(check_action_admit_110_13
        == AdmissionFailure::ScalarPredicateStateUnavailable);
    }

    ComputeUnitWorkgroupScheduler barrierBusy(Limits(4U, 32U, 32U, 1024U, 1U));
    {
        auto&& check_action_admit_114_14 = (barrierBusy.Admit(Demand(42U, 1U)));
        CHECK(check_action_admit_114_14 == AdmissionFailure::None);
    }
    {
        auto&& check_action_admit_115_15 = (barrierBusy.Admit(Demand(43U, 1U)));
        CHECK(check_action_admit_115_15
        == AdmissionFailure::BarrierContextsUnavailable);
    }

    ComputeUnitWorkgroupScheduler multiple(Limits(4U, 32U, 32U, 1024U, 4U, 16U));
    {
        auto&& check_action_admit_119_16 = (multiple.Admit(Demand(5U, 2U, 16U, 2U, 256U, 4U)));
        CHECK(check_action_admit_119_16
        == AdmissionFailure::None);
    }
    {
        auto&& check_action_admit_121_17 = (multiple.Admit(Demand(6U, 2U, 16U, 2U, 256U, 4U)));
        CHECK(check_action_admit_121_17
        == AdmissionFailure::None);
    }
    CHECK(multiple.WorkgroupCount() == 2U);
    CHECK(multiple.ResidentWaveCount() == 4U);
    CHECK(multiple.UsedSharedLocalBytes() == 512U);
    {
        auto&& check_action_admit_126_18 = (multiple.Admit(Demand(7U, 1U)));
        CHECK(check_action_admit_126_18
        == AdmissionFailure::ResidentWaveSlotsUnavailable);
    }
    {
        auto&& check_action_admit_128_19 = (multiple.Admit(Demand(5U, 1U)));
        CHECK(check_action_admit_128_19
        == AdmissionFailure::DuplicateWorkgroupId);
    }
    return 0;
}

int TestBarrierArrivalsAndIssue()
{
    ComputeUnitWorkgroupScheduler oneWave(Limits(4U));
    {
        auto&& check_action_admit_136_20 = (oneWave.Admit(Demand(10U, 1U)));
        CHECK(check_action_admit_136_20 == AdmissionFailure::None);
    }
    auto result = oneWave.ArriveAtBarrier(10U, {0U});
    CHECK(result.status == BarrierStatus::Released);
    CHECK(result.releasedWaveCount == 1U);
    CHECK(oneWave.BarrierGeneration(10U) == 1U);

    ComputeUnitWorkgroupScheduler together(Limits(4U));
    {
        auto&& check_action_admit_143_21 = (together.Admit(Demand(11U, 3U)));
        CHECK(check_action_admit_143_21 == AdmissionFailure::None);
    }
    result = together.ArriveAtBarrier(11U, {2U, 0U, 1U});
    CHECK(result.status == BarrierStatus::Released);
    CHECK(result.releasedWaveCount == 3U);

    ComputeUnitWorkgroupScheduler staggered(Limits(4U));
    {
        auto&& check_action_admit_149_22 = (staggered.Admit(Demand(12U, 4U)));
        CHECK(check_action_admit_149_22 == AdmissionFailure::None);
    }
    {
        auto&& check_action_arriveatbarrier_150_23 = (staggered.ArriveAtBarrier(12U, {3U}));
        CHECK(check_action_arriveatbarrier_150_23.status == BarrierStatus::Waiting);
    }
    {
        auto&& check_action_arriveatbarrier_151_24 = (staggered.ArriveAtBarrier(12U, {3U}));
        CHECK(check_action_arriveatbarrier_151_24.status == BarrierStatus::WaveAlreadyWaiting);
    }
    {
        auto&& check_action_arriveatbarrier_152_25 = (staggered.ArriveAtBarrier(12U, {0U, 0U}));
        CHECK(check_action_arriveatbarrier_152_25.status
        == BarrierStatus::DuplicateWaveInArrival);
    }
    {
        auto&& check_action_arriveatbarrier_154_26 = (staggered.ArriveAtBarrier(12U, {1U, 0U}));
        CHECK(check_action_arriveatbarrier_154_26.status == BarrierStatus::Waiting);
    }
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
        {
            auto&& check_action_arriveatbarrier_167_27 = (staggered.ArriveAtBarrier(12U, {2U}));
            CHECK(check_action_arriveatbarrier_167_27.status == BarrierStatus::Waiting);
        }
        {
            auto&& check_action_arriveatbarrier_168_28 = (staggered.ArriveAtBarrier(12U, {0U, 3U}));
            CHECK(check_action_arriveatbarrier_168_28.status == BarrierStatus::Waiting);
        }
        result = staggered.ArriveAtBarrier(12U, {1U});
        CHECK(result.status == BarrierStatus::Released);
    }
    CHECK(staggered.BarrierGeneration(12U) == 21U);

    ComputeUnitWorkgroupScheduler independent(Limits(4U, 32U, 32U, 1024U, 2U));
    {
        auto&& check_action_admit_175_29 = (independent.Admit(Demand(13U, 2U)));
        CHECK(check_action_admit_175_29 == AdmissionFailure::None);
    }
    {
        auto&& check_action_admit_176_30 = (independent.Admit(Demand(14U, 2U)));
        CHECK(check_action_admit_176_30 == AdmissionFailure::None);
    }
    {
        auto&& check_action_arriveatbarrier_177_31 = (independent.ArriveAtBarrier(13U, {0U}));
        CHECK(check_action_arriveatbarrier_177_31.status == BarrierStatus::Waiting);
    }
    CHECK(independent.CanIssue(14U, 0U));
    CHECK(independent.CanIssue(14U, 1U));
    {
        auto&& check_action_selectissuablewave_180_32 = (independent.SelectIssuableWave(std::vector<bool>(4U, true)));
        CHECK(check_action_selectissuablewave_180_32.has_value());
    }
    return 0;
}

int TestFragmentationAndLifecycle()
{
    ComputeUnitWorkgroupScheduler fragmented(Limits(8U, 8U, 32U, 2048U, 6U));
    for (std::uint64_t id = 1U; id <= 4U; ++id)
        {
            auto&& check_action_admit_188_33 = (fragmented.Admit(Demand(id, 1U, 16U)));
            CHECK(check_action_admit_188_33 == AdmissionFailure::None);
        }
    {
        auto&& check_action_killworkgroup_189_34 = (fragmented.KillWorkgroup(2U));
        CHECK(check_action_killworkgroup_189_34);
    }
    {
        auto&& check_action_killworkgroup_190_35 = (fragmented.KillWorkgroup(4U));
        CHECK(check_action_killworkgroup_190_35);
    }
    CHECK(fragmented.OccupiedVgprRows() == 4U);
    {
        auto&& check_action_admit_192_36 = (fragmented.Admit(Demand(5U, 1U, 17U)));
        CHECK(check_action_admit_192_36
        == AdmissionFailure::VgprCapacityFragmented);
    }
    CHECK(fragmented.ResidentWaveCount() == 2U);

    ComputeUnitWorkgroupScheduler lifecycle(Limits(4U, 32U, 32U, 2048U, 2U, 32U));
    {
        auto&& check_action_admit_197_37 = (lifecycle.Admit(Demand(20U, 3U, 16U, 4U, 1024U, 8U)));
        CHECK(check_action_admit_197_37
        == AdmissionFailure::None);
    }
    {
        auto&& check_action_arriveatbarrier_199_38 = (lifecycle.ArriveAtBarrier(20U, {0U, 1U}));
        CHECK(check_action_arriveatbarrier_199_38.status == BarrierStatus::Waiting);
    }
    {
        auto&& check_action_terminatewave_200_39 = (lifecycle.TerminateWave(20U, 2U));
        CHECK(check_action_terminatewave_200_39);
    }
    CHECK(lifecycle.BarrierGeneration(20U) == 1U);
    CHECK(lifecycle.CanIssue(20U, 0U) && lifecycle.CanIssue(20U, 1U));
    CHECK(lifecycle.ResidentWaveCount() == 2U);
    CHECK(lifecycle.UsedSharedLocalBytes() == 1024U);
    {
        auto&& check_action_terminatewave_205_40 = (lifecycle.TerminateWave(20U, 0U));
        CHECK(check_action_terminatewave_205_40);
    }
    CHECK(lifecycle.UsedScalarPredicateUnits() == 4U);
    {
        auto&& check_action_terminatewave_207_41 = (lifecycle.TerminateWave(20U, 1U));
        CHECK(check_action_terminatewave_207_41);
    }
    CHECK(lifecycle.WorkgroupCount() == 0U);
    CHECK(lifecycle.ResidentWaveCount() == 0U);
    CHECK(lifecycle.OccupiedVgprRows() == 0U);
    CHECK(lifecycle.UsedScalarPredicateUnits() == 0U);
    CHECK(lifecycle.UsedSharedLocalBytes() == 0U);
    CHECK(lifecycle.UsedOtherWorkgroupUnits() == 0U);

    {
        auto&& check_action_admit_215_42 = (lifecycle.Admit(Demand(25U, 3U, 16U, 2U, 256U, 2U)));
        CHECK(check_action_admit_215_42
        == AdmissionFailure::None);
    }
    {
        auto&& check_action_arriveatbarrier_217_43 = (lifecycle.ArriveAtBarrier(25U, {0U, 2U}));
        CHECK(check_action_arriveatbarrier_217_43.status == BarrierStatus::Waiting);
    }
    {
        auto&& check_action_terminatewave_218_44 = (lifecycle.TerminateWave(25U, 2U));
        CHECK(check_action_terminatewave_218_44);
    }
    auto afterFaultedWaiter = lifecycle.GetWorkgroupState(25U);
    CHECK(afterFaultedWaiter.liveWaves[0] && afterFaultedWaiter.waitingWaves[0]);
    CHECK(afterFaultedWaiter.liveWaves[1] && !afterFaultedWaiter.waitingWaves[1]);
    CHECK(!afterFaultedWaiter.liveWaves[2] && !afterFaultedWaiter.waitingWaves[2]);
    CHECK(lifecycle.CanIssue(25U, 1U));
    {
        auto&& check_action_arriveatbarrier_224_45 = (lifecycle.ArriveAtBarrier(25U, {1U}));
        CHECK(check_action_arriveatbarrier_224_45.status == BarrierStatus::Released);
    }
    CHECK(lifecycle.BarrierGeneration(25U) == 1U);
    {
        auto&& check_action_killworkgroup_226_46 = (lifecycle.KillWorkgroup(25U));
        CHECK(check_action_killworkgroup_226_46);
    }

    for (const bool fault : {false, true})
    {
        const std::uint64_t id = fault ? 22U : 21U;
        {
            auto&& check_action_admit_231_47 = (lifecycle.Admit(Demand(id, 3U, 32U, 3U, 512U, 2U)));
            CHECK(check_action_admit_231_47
            == AdmissionFailure::None);
        }
        {
            auto&& check_action_arriveatbarrier_233_48 = (lifecycle.ArriveAtBarrier(id, {0U, 2U}));
            CHECK(check_action_arriveatbarrier_233_48.status == BarrierStatus::Waiting);
        }
        {
            auto&& check_condition_234_49 = ((fault ? lifecycle.FaultWorkgroup(id) : lifecycle.KillWorkgroup(id)));
            CHECK(check_condition_234_49);
        }
        CHECK(!lifecycle.CanIssue(id, 1U));
        CHECK(lifecycle.WorkgroupCount() == 0U);
        CHECK(lifecycle.ResidentWaveCount() == 0U);
        CHECK(lifecycle.OccupiedVgprRows() == 0U);
        CHECK(lifecycle.UsedSharedLocalBytes() == 0U);
    }

    {
        auto&& check_action_admit_242_50 = (lifecycle.Admit(Demand(23U, 2U)));
        CHECK(check_action_admit_242_50 == AdmissionFailure::None);
    }
    {
        auto&& check_action_arriveatbarrier_243_51 = (lifecycle.ArriveAtBarrier(23U, {1U}));
        CHECK(check_action_arriveatbarrier_243_51.status == BarrierStatus::Waiting);
    }
    lifecycle.Reset();
    CHECK(lifecycle.WorkgroupCount() == 0U);
    CHECK(lifecycle.ResidentWaveCount() == 0U);
    CHECK(lifecycle.OccupiedVgprRows() == 0U);
    CHECK(lifecycle.CheckInvariants());
    {
        auto&& check_action_admit_249_52 = (lifecycle.Admit(Demand(24U, 4U)));
        CHECK(check_action_admit_249_52 == AdmissionFailure::None);
    }
    return 0;
}

int TestAuthoritativePoolTransactionsAndQuiescence()
{
    ComputeUnitWorkgroupScheduler variable(
        Limits(8U, 64U, 128U, 2048U, 4U, 64U));
    auto variableDemand = Demand(50U, 2U, 16U);
    variableDemand.vgprRegisterCountsByWave = {9U, 17U};
    {
        auto&& check_action_admit_259_53 = (variable.Admit(variableDemand));
        CHECK(check_action_admit_259_53 == AdmissionFailure::None);
    }
    CHECK(variable.AllocationForWave(50U, 0U).state
        == cgx1::matrix::VgprAllocationState::Active);
    CHECK(variable.AllocationForWave(50U, 0U).physicalRowCount == 2U);
    CHECK(variable.AllocationForWave(50U, 0U).architecturalRegisterCount == 9U);
    CHECK(variable.AllocationForWave(50U, 1U).physicalRowCount == 3U);
    CHECK(variable.AllocationForWave(50U, 1U).architecturalRegisterCount == 17U);
    bool outOfBoundsRejected = false;
    try
    {
        (void)variable.ReadVgpr(50U, 0U, 9U);
    }
    catch (const std::out_of_range&)
    {
        outOfBoundsRejected = true;
    }
    CHECK(outOfBoundsRejected);

    cgx1::matrix::PooledWaveRegister stalePattern{};
    stalePattern.fill(0xDEADBEEFU);
    {
        auto&& check_action_restorevgpr_279_54 = (variable.RestoreVgpr(50U, 0U, 0U, stalePattern));
        CHECK(check_action_restorevgpr_279_54);
    }
    CHECK(variable.ReadVgpr(50U, 0U, 0U) == stalePattern);
    {
        auto&& check_action_faultworkgroup_281_55 = (variable.FaultWorkgroup(50U));
        CHECK(check_action_faultworkgroup_281_55);
    }
    {
        auto&& check_action_admit_282_56 = (variable.Admit(Demand(51U, 1U, 9U)));
        CHECK(check_action_admit_282_56 == AdmissionFailure::None);
    }
    bool staleReadRejected = false;
    try
    {
        (void)variable.ReadVgpr(51U, 0U, 0U);
    }
    catch (const std::logic_error&)
    {
        staleReadRejected = true;
    }
    CHECK(staleReadRejected);

    ComputeUnitWorkgroupScheduler fragmented(
        Limits(8U, 16U, 64U, 2048U, 8U, 128U));
    for (std::uint64_t id = 60U; id <= 63U; ++id)
        {
            auto&& check_action_admit_297_57 = (fragmented.Admit(Demand(id, 1U, 32U)));
            CHECK(check_action_admit_297_57 == AdmissionFailure::None);
        }
    {
        auto&& check_action_killworkgroup_298_58 = (fragmented.KillWorkgroup(61U));
        CHECK(check_action_killworkgroup_298_58);
    }
    {
        auto&& check_action_killworkgroup_299_59 = (fragmented.KillWorkgroup(63U));
        CHECK(check_action_killworkgroup_299_59);
    }
    std::array<cgx1::matrix::ResidentWaveVgprAllocation, 8U> before{};
    for (std::uint32_t slot = 0U; slot < before.size(); ++slot)
        before[slot] = fragmented.AllocationForSlot(slot);
    auto fragmentedDemand = Demand(64U, 2U, 16U, 2U, 256U);
    fragmentedDemand.vgprRegisterCountsByWave = {8U, 40U};
    {
        auto&& check_action_admit_305_60 = (fragmented.Admit(fragmentedDemand));
        CHECK(check_action_admit_305_60
        == AdmissionFailure::VgprCapacityFragmented);
    }
    CHECK(fragmented.UsedSharedLocalBytes() == 0U);
    CHECK(!fragmented.SharedLocalMemoryRegionForWorkgroup(64U).has_value());
    for (std::uint32_t slot = 0U; slot < before.size(); ++slot)
    {
        const auto& after = fragmented.AllocationForSlot(slot);
        CHECK(after.state == before[slot].state);
        CHECK(after.physicalRowBase == before[slot].physicalRowBase);
        CHECK(after.physicalRowCount == before[slot].physicalRowCount);
        CHECK(after.architecturalRegisterCount == before[slot].architecturalRegisterCount);
        CHECK(after.invalidatedRows == before[slot].invalidatedRows);
    }
    CHECK(fragmented.CheckInvariants());

    ComputeUnitWorkgroupScheduler lifecycle(
        Limits(4U, 32U, 64U, 2048U, 4U, 64U));
    {
        auto&& check_action_admit_322_61 = (lifecycle.Admit(Demand(70U, 2U)));
        CHECK(check_action_admit_322_61 == AdmissionFailure::None);
    }
    const auto faultedSlot = *lifecycle.GetWorkgroupState(70U).waveSlots[0U];
    {
        auto&& check_action_beginwaveexecution_324_62 = (lifecycle.BeginWaveExecution(70U, 0U));
        CHECK(check_action_beginwaveexecution_324_62);
    }
    {
        auto&& check_action_arriveatbarrier_325_63 = (lifecycle.ArriveAtBarrier(70U, {1U}));
        CHECK(check_action_arriveatbarrier_325_63.status == BarrierStatus::Waiting);
    }
    {
        auto&& check_action_faultwave_326_64 = (lifecycle.FaultWave(70U, 0U));
        CHECK(check_action_faultwave_326_64);
    }
    CHECK(lifecycle.AllocationForWave(70U, 0U).state
        == cgx1::matrix::VgprAllocationState::Active);
    CHECK(!lifecycle.CanIssue(70U, 0U));
    CHECK(lifecycle.CanIssue(70U, 1U));
    CHECK(lifecycle.BarrierGeneration(70U) == 1U);
    {
        auto&& check_action_completewaveexecution_332_65 = (lifecycle.CompleteWaveExecution(70U, 0U));
        CHECK(check_action_completewaveexecution_332_65);
    }
    CHECK(lifecycle.AllocationForSlot(faultedSlot).state
        == cgx1::matrix::VgprAllocationState::Free);
    {
        auto&& check_action_terminatewave_335_66 = (lifecycle.TerminateWave(70U, 1U));
        CHECK(check_action_terminatewave_335_66);
    }
    CHECK(lifecycle.WorkgroupCount() == 0U);
    CHECK(lifecycle.OccupiedVgprRows() == 0U);

    {
        auto&& check_action_admit_339_67 = (lifecycle.Admit(Demand(71U, 1U)));
        CHECK(check_action_admit_339_67 == AdmissionFailure::None);
    }
    {
        auto&& check_action_beginwaveexecution_340_68 = (lifecycle.BeginWaveExecution(71U, 0U));
        CHECK(check_action_beginwaveexecution_340_68);
    }
    {
        auto&& check_action_killworkgroup_341_69 = (lifecycle.KillWorkgroup(71U));
        CHECK(check_action_killworkgroup_341_69);
    }
    CHECK(lifecycle.WorkgroupCount() == 1U);
    CHECK(lifecycle.AllocationForWave(71U, 0U).state
        == cgx1::matrix::VgprAllocationState::Active);
    {
        auto&& check_action_completewaveexecution_345_70 = (lifecycle.CompleteWaveExecution(71U, 0U));
        CHECK(check_action_completewaveexecution_345_70);
    }
    CHECK(lifecycle.WorkgroupCount() == 0U);
    CHECK(lifecycle.OccupiedVgprRows() == 0U);

    {
        auto&& check_action_admit_349_71 = (lifecycle.Admit(Demand(72U, 2U)));
        CHECK(check_action_admit_349_71 == AdmissionFailure::None);
    }
    {
        auto&& check_action_beginwaveexecution_350_72 = (lifecycle.BeginWaveExecution(72U, 0U));
        CHECK(check_action_beginwaveexecution_350_72);
    }
    {
        auto&& check_action_arriveatbarrier_351_73 = (lifecycle.ArriveAtBarrier(72U, {1U}));
        CHECK(check_action_arriveatbarrier_351_73.status == BarrierStatus::Waiting);
    }
    lifecycle.Reset();
    CHECK(lifecycle.WorkgroupCount() == 0U);
    CHECK(lifecycle.OccupiedVgprRows() == 0U);
    for (std::uint32_t slot = 0U; slot < 4U; ++slot)
        CHECK(lifecycle.AllocationForSlot(slot).state
            == cgx1::matrix::VgprAllocationState::Free);
    CHECK(lifecycle.CheckInvariants());
    return 0;
}

int TestSharedMemoryAdmissionAndFragmentation()
{
    ComputeUnitWorkgroupScheduler fragmented(Limits(8U, 16U, 64U, 1024U, 6U, 64U));
    for (std::uint64_t id = 1U; id <= 4U; ++id)
        {
            auto&& check_action_admit_366_74 = (fragmented.Admit(Demand(id, 1U, 8U, 1U, 256U)));
            CHECK(check_action_admit_366_74
            == AdmissionFailure::None);
        }
    CHECK(fragmented.UsedSharedLocalBytes() == 1024U);
    {
        auto&& check_action_killworkgroup_369_75 = (fragmented.KillWorkgroup(2U));
        CHECK(check_action_killworkgroup_369_75);
    }
    {
        auto&& check_action_killworkgroup_370_76 = (fragmented.KillWorkgroup(4U));
        CHECK(check_action_killworkgroup_370_76);
    }
    CHECK(fragmented.UsedSharedLocalBytes() == 512U);

    {
        auto&& check_action_admit_373_77 = (fragmented.Admit(Demand(5U, 1U, 8U, 1U, 384U)));
        CHECK(check_action_admit_373_77
        == AdmissionFailure::SharedLocalMemoryFragmented);
    }
    CHECK(fragmented.WorkgroupCount() == 2U);
    CHECK(fragmented.ResidentWaveCount() == 2U);
    CHECK(fragmented.OccupiedVgprRows() == 2U);
    CHECK(fragmented.UsedSharedLocalBytes() == 512U);
    CHECK(!fragmented.SharedLocalMemoryRegionForWorkgroup(5U).has_value());

    {
        auto&& check_action_admit_381_78 = (fragmented.Admit(Demand(6U, 1U, 8U, 1U, 256U)));
        CHECK(check_action_admit_381_78
        == AdmissionFailure::None);
    }
    CHECK(fragmented.UsedSharedLocalBytes() == 768U);
    CHECK(fragmented.CheckInvariants());
    return 0;
}

int TestSharedMemoryWaitBarrierAndResponseLifecycle()
{
    ComputeUnitWorkgroupScheduler scheduler(Limits(8U, 64U, 128U, 256U, 4U, 64U));
    {
        auto&& check_action_admit_391_79 = (scheduler.Admit(Demand(80U, 2U, 16U, 2U, 128U)));
        CHECK(check_action_admit_391_79
        == AdmissionFailure::None);
    }
    {
        auto&& check_action_admit_393_80 = (scheduler.Admit(Demand(81U, 1U, 16U, 2U, 128U)));
        CHECK(check_action_admit_393_80
        == AdmissionFailure::None);
    }

    std::array<std::uint32_t, 32U> addresses{};
    std::array<std::uint32_t, 32U> data{};
    addresses[0] = 0U;
    addresses[1] = 4U;
    data[0] = 0x12345678U;
    data[1] = 0xabcdef01U;
    const auto request = LocalMemoryRequest(
        80U, 0U, 700U, AccessKind::Store, 0x3U, addresses, data);
    {
        auto&& check_action_submitsharedlocalmemoryrequest_404_81 = (scheduler.SubmitSharedLocalMemoryRequest(request));
        CHECK(check_action_submitsharedlocalmemoryrequest_404_81.status
        == SubmitStatus::Accepted);
    }
    CHECK(!scheduler.CanIssue(80U, 0U));
    CHECK(scheduler.CanIssue(80U, 1U));
    CHECK(scheduler.CanIssue(81U, 0U));
    CHECK(scheduler.GetWorkgroupState(80U).memoryWaitingWaves[0U]);
    {
        auto&& check_action_arriveatbarrier_410_82 = (scheduler.ArriveAtBarrier(80U, {0U}));
        CHECK(check_action_arriveatbarrier_410_82.status == BarrierStatus::WaveBusy);
    }
    {
        auto&& check_action_arriveatbarrier_411_83 = (scheduler.ArriveAtBarrier(80U, {1U}));
        CHECK(check_action_arriveatbarrier_411_83.status == BarrierStatus::Waiting);
    }
    {
        auto&& check_action_submitsharedlocalmemoryrequest_412_84 = (scheduler.SubmitSharedLocalMemoryRequest(LocalMemoryRequest(
        80U, 1U, 702U, AccessKind::Load, 0x1U, addresses)));
        CHECK(check_action_submitsharedlocalmemoryrequest_412_84.status
        == SubmitStatus::WaveNotIssuable);
    }

    {
        auto&& check_action_beginwaveexecution_416_85 = (scheduler.BeginWaveExecution(81U, 0U));
        CHECK(check_action_beginwaveexecution_416_85);
    }
    {
        auto&& check_action_submitsharedlocalmemoryrequest_417_86 = (scheduler.SubmitSharedLocalMemoryRequest(LocalMemoryRequest(
        81U, 0U, 703U, AccessKind::Load, 0x1U, addresses)));
        CHECK(check_action_submitsharedlocalmemoryrequest_417_86.status
        == SubmitStatus::WaveNotIssuable);
    }
    {
        auto&& check_action_completewaveexecution_420_87 = (scheduler.CompleteWaveExecution(81U, 0U));
        CHECK(check_action_completewaveexecution_420_87);
    }

    const auto siblingSlot = *scheduler.GetWorkgroupState(81U).waveSlots[0U];
    {
        auto&& check_action_selectissuablewave_423_88 = (scheduler.SelectIssuableWave(std::vector<bool>(8U, true)));
        CHECK(check_action_selectissuablewave_423_88 == siblingSlot);
    }
    {
        auto&& check_action_servicesharedlocalmemorycycle_424_89 = (scheduler.ServiceSharedLocalMemoryCycle());
        CHECK(check_action_servicesharedlocalmemorycycle_424_89 == 2U);
    }
    CHECK(!scheduler.CanIssue(80U, 0U));
    {
        auto&& check_action_arriveatbarrier_426_90 = (scheduler.ArriveAtBarrier(80U, {0U}));
        CHECK(check_action_arriveatbarrier_426_90.status == BarrierStatus::WaveBusy);
    }
    const auto storeResponse = scheduler.TakeSharedLocalMemoryResponse();
    CHECK(storeResponse.has_value() && storeResponse->transactionTag == 700U);
    CHECK(!scheduler.GetWorkgroupState(80U).memoryWaitingWaves[0U]);
    CHECK(scheduler.CanIssue(80U, 0U));
    {
        auto&& check_action_arriveatbarrier_431_91 = (scheduler.ArriveAtBarrier(80U, {0U}));
        CHECK(check_action_arriveatbarrier_431_91.status == BarrierStatus::Released);
    }
    CHECK(scheduler.BarrierGeneration(80U) == 1U);

    const auto load = LocalMemoryRequest(
        80U, 0U, 701U, AccessKind::Load, 0x3U, addresses);
    {
        auto&& check_action_submitsharedlocalmemoryrequest_436_92 = (scheduler.SubmitSharedLocalMemoryRequest(load));
        CHECK(check_action_submitsharedlocalmemoryrequest_436_92.status
        == SubmitStatus::Accepted);
    }
    {
        auto&& check_action_servicesharedlocalmemorycycle_438_93 = (scheduler.ServiceSharedLocalMemoryCycle());
        CHECK(check_action_servicesharedlocalmemorycycle_438_93 == 2U);
    }
    const auto loadResponse = scheduler.TakeSharedLocalMemoryResponse();
    CHECK(loadResponse.has_value());
    CHECK(loadResponse->laneData[0] == data[0]);
    CHECK(loadResponse->laneData[1] == data[1]);
    CHECK(scheduler.CanIssue(80U, 0U));
    {
        auto&& check_action_killworkgroup_444_94 = (scheduler.KillWorkgroup(80U));
        CHECK(check_action_killworkgroup_444_94);
    }
    {
        auto&& check_action_killworkgroup_445_95 = (scheduler.KillWorkgroup(81U));
        CHECK(check_action_killworkgroup_445_95);
    }
    CHECK(scheduler.UsedSharedLocalBytes() == 0U);
    CHECK(scheduler.CheckInvariants());
    return 0;
}

int TestSharedMemoryTerminalDrainAndReset()
{
    ComputeUnitWorkgroupScheduler scheduler(Limits(4U, 32U, 64U, 256U, 4U, 64U));
    {
        auto&& check_action_admit_454_96 = (scheduler.Admit(Demand(90U, 1U, 16U, 2U, 256U)));
        CHECK(check_action_admit_454_96
        == AdmissionFailure::None);
    }
    const auto canceledSlot = *scheduler.GetWorkgroupState(90U).waveSlots[0U];
    std::array<std::uint32_t, 32U> conflictAddresses{};
    std::array<std::uint32_t, 32U> data{};
    conflictAddresses[0] = 0U;
    conflictAddresses[1] = 128U;
    const auto pending = LocalMemoryRequest(
        90U, 0U, 900U, AccessKind::Store, 0x3U, conflictAddresses, data);
    {
        auto&& check_action_submitsharedlocalmemoryrequest_463_97 = (scheduler.SubmitSharedLocalMemoryRequest(pending));
        CHECK(check_action_submitsharedlocalmemoryrequest_463_97.status
        == SubmitStatus::Accepted);
    }
    {
        auto&& check_action_faultwave_465_98 = (scheduler.FaultWave(90U, 0U));
        CHECK(check_action_faultwave_465_98);
    }
    CHECK(scheduler.WorkgroupCount() == 1U);
    CHECK(scheduler.UsedSharedLocalBytes() == 256U);
    CHECK(scheduler.GetWorkgroupState(90U).memoryWaitingWaves[0U]);
    CHECK(scheduler.AllocationForSlot(canceledSlot).state
        == cgx1::matrix::VgprAllocationState::Active);
    CHECK(scheduler.CheckInvariants());
    {
        auto&& check_action_servicesharedlocalmemorycycle_472_99 = (scheduler.ServiceSharedLocalMemoryCycle());
        CHECK(check_action_servicesharedlocalmemorycycle_472_99 == 1U);
    }
    CHECK(scheduler.WorkgroupCount() == 1U);
    CHECK(scheduler.CheckInvariants());
    {
        auto&& check_action_servicesharedlocalmemorycycle_475_100 = (scheduler.ServiceSharedLocalMemoryCycle());
        CHECK(check_action_servicesharedlocalmemorycycle_475_100 == 1U);
    }
    CHECK(scheduler.WorkgroupCount() == 0U);
    CHECK(scheduler.UsedSharedLocalBytes() == 0U);
    {
        auto&& check_action_takesharedlocalmemoryresponse_478_101 = (scheduler.TakeSharedLocalMemoryResponse());
        CHECK(!check_action_takesharedlocalmemoryresponse_478_101.has_value());
    }

    {
        auto&& check_action_admit_480_102 = (scheduler.Admit(Demand(93U, 2U, 16U, 2U, 256U)));
        CHECK(check_action_admit_480_102
        == AdmissionFailure::None);
    }
    {
        auto&& check_action_submitsharedlocalmemoryrequest_482_103 = (scheduler.SubmitSharedLocalMemoryRequest(LocalMemoryRequest(
        93U, 0U, 903U, AccessKind::Store, 0x3U, conflictAddresses, data)));
        CHECK(check_action_submitsharedlocalmemoryrequest_482_103.status
        == SubmitStatus::Accepted);
    }
    {
        auto&& check_action_arriveatbarrier_485_104 = (scheduler.ArriveAtBarrier(93U, {1U}));
        CHECK(check_action_arriveatbarrier_485_104.status == BarrierStatus::Waiting);
    }
    {
        auto&& check_action_faultwave_486_105 = (scheduler.FaultWave(93U, 0U));
        CHECK(check_action_faultwave_486_105);
    }
    CHECK(scheduler.BarrierGeneration(93U) == 1U);
    CHECK(scheduler.CanIssue(93U, 1U));
    CHECK(scheduler.GetWorkgroupState(93U).memoryWaitingWaves[0U]);
    CHECK(scheduler.UsedSharedLocalBytes() == 256U);
    {
        auto&& check_action_servicesharedlocalmemorycycle_491_106 = (scheduler.ServiceSharedLocalMemoryCycle());
        CHECK(check_action_servicesharedlocalmemorycycle_491_106 == 1U);
    }
    {
        auto&& check_action_servicesharedlocalmemorycycle_492_107 = (scheduler.ServiceSharedLocalMemoryCycle());
        CHECK(check_action_servicesharedlocalmemorycycle_492_107 == 1U);
    }
    {
        auto&& check_action_takesharedlocalmemoryresponse_493_108 = (scheduler.TakeSharedLocalMemoryResponse());
        CHECK(!check_action_takesharedlocalmemoryresponse_493_108.has_value());
    }
    CHECK(scheduler.WorkgroupCount() == 1U);
    CHECK(scheduler.UsedSharedLocalBytes() == 256U);
    {
        auto&& check_action_terminatewave_496_109 = (scheduler.TerminateWave(93U, 1U));
        CHECK(check_action_terminatewave_496_109);
    }
    CHECK(scheduler.WorkgroupCount() == 0U);
    CHECK(scheduler.UsedSharedLocalBytes() == 0U);

    {
        auto&& check_action_admit_500_110 = (scheduler.Admit(Demand(91U, 1U, 16U, 2U, 128U)));
        CHECK(check_action_admit_500_110
        == AdmissionFailure::None);
    }
    std::array<std::uint32_t, 32U> oneAddress{};
    const auto completed = LocalMemoryRequest(
        91U, 0U, 901U, AccessKind::Load, 0x1U, oneAddress);
    {
        auto&& check_action_submitsharedlocalmemoryrequest_505_111 = (scheduler.SubmitSharedLocalMemoryRequest(completed));
        CHECK(check_action_submitsharedlocalmemoryrequest_505_111.status
        == SubmitStatus::Accepted);
    }
    {
        auto&& check_action_servicesharedlocalmemorycycle_507_112 = (scheduler.ServiceSharedLocalMemoryCycle());
        CHECK(check_action_servicesharedlocalmemorycycle_507_112 == 1U);
    }
    {
        auto&& check_action_killworkgroup_508_113 = (scheduler.KillWorkgroup(91U));
        CHECK(check_action_killworkgroup_508_113);
    }
    CHECK(scheduler.WorkgroupCount() == 0U);
    {
        auto&& check_action_takesharedlocalmemoryresponse_510_114 = (scheduler.TakeSharedLocalMemoryResponse());
        CHECK(!check_action_takesharedlocalmemoryresponse_510_114.has_value());
    }
    CHECK(scheduler.UsedSharedLocalBytes() == 0U);

    {
        auto&& check_action_admit_513_115 = (scheduler.Admit(Demand(92U, 1U, 16U, 2U, 256U)));
        CHECK(check_action_admit_513_115
        == AdmissionFailure::None);
    }
    {
        auto&& check_action_submitsharedlocalmemoryrequest_515_116 = (scheduler.SubmitSharedLocalMemoryRequest(LocalMemoryRequest(
        92U, 0U, 902U, AccessKind::Load, 0x3U, conflictAddresses)));
        CHECK(check_action_submitsharedlocalmemoryrequest_515_116.status
        == SubmitStatus::Accepted);
    }
    {
        auto&& check_action_servicesharedlocalmemorycycle_518_117 = (scheduler.ServiceSharedLocalMemoryCycle());
        CHECK(check_action_servicesharedlocalmemorycycle_518_117 == 1U);
    }
    scheduler.Reset();
    CHECK(scheduler.WorkgroupCount() == 0U);
    CHECK(scheduler.ResidentWaveCount() == 0U);
    CHECK(scheduler.OccupiedVgprRows() == 0U);
    CHECK(scheduler.UsedSharedLocalBytes() == 0U);
    {
        auto&& check_action_takesharedlocalmemoryresponse_524_118 = (scheduler.TakeSharedLocalMemoryResponse());
        CHECK(!check_action_takesharedlocalmemoryresponse_524_118.has_value());
    }
    CHECK(scheduler.CheckInvariants());
    {
        auto&& check_action_admit_526_119 = (scheduler.Admit(Demand(92U, 1U)));
        CHECK(check_action_admit_526_119 == AdmissionFailure::None);
    }
    {
        auto&& check_action_killworkgroup_527_120 = (scheduler.KillWorkgroup(92U));
        CHECK(check_action_killworkgroup_527_120);
    }
    return 0;
}

int TestRandomizedSharedMemoryScheduling()
{
    ComputeUnitWorkgroupScheduler scheduler(Limits(8U, 64U, 128U, 1024U, 4U, 64U));
    {
        auto&& check_action_admit_534_121 = (scheduler.Admit(Demand(100U, 2U, 16U, 2U, 512U)));
        CHECK(check_action_admit_534_121
        == AdmissionFailure::None);
    }
    {
        auto&& check_action_admit_536_122 = (scheduler.Admit(Demand(101U, 2U, 16U, 2U, 512U)));
        CHECK(check_action_admit_536_122
        == AdmissionFailure::None);
    }
    constexpr std::uint32_t seed = 0x5A17C0DEU;
    std::mt19937 random(seed);
    std::uint64_t tag = 1000U;
    std::uint32_t completions = 0U;
    std::uint32_t barrierReleases = 0U;
    for (std::uint32_t cycle = 0U; cycle < 5000U; ++cycle)
    {
        const auto group = 100U + (random() % 2U);
        const auto wave = static_cast<std::uint32_t>(random() % 2U);
        ::cgx1::testing::SetRandomTestFailureContext(
            "TestRandomizedSharedMemoryScheduling", seed, cycle,
            (static_cast<std::uint64_t>(group) << 32U) | wave);
        const auto state = scheduler.GetWorkgroupState(group);
        if (state.liveWaves[wave] && !state.waitingWaves[wave]
            && !state.memoryWaitingWaves[wave] && scheduler.CanIssue(group, wave))
        {
            switch (random() % 4U)
            {
                case 0U:
                {
                    std::array<std::uint32_t, 32U> addresses{};
                    std::array<std::uint32_t, 32U> data{};
                    addresses[0] = 4U * (random() % 128U);
                    data[0] = static_cast<std::uint32_t>(random());
                    const auto access = (random() & 1U) == 0U
                        ? AccessKind::Load : AccessKind::Store;
                    const auto result = scheduler.SubmitSharedLocalMemoryRequest(
                        LocalMemoryRequest(
                            group, wave, tag++, access, 1U, addresses, data));
                    CHECK(result.status == SubmitStatus::Accepted);
                    break;
                }
                case 1U:
                    if (scheduler.ArriveAtBarrier(group, {wave}).status
                        == BarrierStatus::Released)
                        ++barrierReleases;
                    break;
                default:
                    break;
            }
        }
        (void)scheduler.ServiceSharedLocalMemoryCycle();
        if (scheduler.TakeSharedLocalMemoryResponse())
            ++completions;
        CHECK(scheduler.CheckInvariants());
    }
    CHECK(completions != 0U);
    CHECK(barrierReleases != 0U);
    {
        auto&& check_action_killworkgroup_586_123 = (scheduler.KillWorkgroup(100U));
        CHECK(check_action_killworkgroup_586_123);
    }
    {
        auto&& check_action_killworkgroup_587_124 = (scheduler.KillWorkgroup(101U));
        CHECK(check_action_killworkgroup_587_124);
    }
    for (std::uint32_t cycle = 0U; cycle < 8U && scheduler.WorkgroupCount() != 0U; ++cycle)
    {
        (void)scheduler.ServiceSharedLocalMemoryCycle();
        while (scheduler.TakeSharedLocalMemoryResponse())
            ++completions;
    }
    CHECK(scheduler.WorkgroupCount() == 0U);
    CHECK(scheduler.UsedSharedLocalBytes() == 0U);
    CHECK(scheduler.CheckInvariants());
    ::cgx1::testing::ClearRandomTestFailureContext();
    return 0;
}

int TestRandomizedForwardProgress()
{
    ComputeUnitWorkgroupScheduler scheduler(Limits(16U, 128U, 512U, 8192U, 8U, 256U));
    constexpr std::uint32_t seed = 0xC671BA22U;
    std::mt19937 random(seed);
    std::uint64_t nextId = 1000U;
    for (std::uint32_t cycle = 0U; cycle < 100000U; ++cycle)
    {
        const auto ids = scheduler.ActiveWorkgroupIds();
        const auto action = random() % 100U;
        ::cgx1::testing::SetRandomTestFailureContext(
            "TestRandomizedForwardProgress", seed, cycle, action);
        if (action < 22U)
        {
            const auto waves = static_cast<std::uint32_t>(
                1U + (random() % 5U));
            const auto registers = static_cast<std::uint32_t>(
                1U + (random() % 256U));
            const auto scalar = static_cast<std::uint32_t>(random() % 9U);
            const auto shared = static_cast<std::uint32_t>(random() % 2049U);
            const auto other = static_cast<std::uint32_t>(random() % 17U);
            (void)scheduler.Admit(Demand(
                nextId++, waves, registers, scalar, shared, other));
        }
        else if (!ids.empty() && action < 50U)
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
        else if (!ids.empty() && action < 65U)
        {
            const auto id = ids[random() % ids.size()];
            const auto state = scheduler.GetWorkgroupState(id);
            std::vector<std::uint32_t> issuable;
            for (std::uint32_t wave = 0U; wave < state.liveWaves.size(); ++wave)
            {
                if (state.liveWaves[wave] && !state.waitingWaves[wave]
                    && !state.busyWaves[wave])
                    issuable.push_back(wave);
            }
            if (!issuable.empty())
                (void)scheduler.BeginWaveExecution(id, issuable[random() % issuable.size()]);
        }
        else if (!ids.empty() && action < 78U)
        {
            const auto id = ids[random() % ids.size()];
            const auto state = scheduler.GetWorkgroupState(id);
            std::vector<std::uint32_t> busy;
            for (std::uint32_t wave = 0U; wave < state.busyWaves.size(); ++wave)
                if (state.busyWaves[wave]) busy.push_back(wave);
            if (!busy.empty())
                (void)scheduler.CompleteWaveExecution(id, busy[random() % busy.size()]);
        }
        else if (!ids.empty() && action < 88U)
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
        else
        {
            scheduler.Reset();
        }

        if (!scheduler.CheckInvariants())
        {
            std::cerr << "[fail] randomized scheduler invariant at cycle "
                      << cycle << " action " << action;
            ::cgx1::testing::WriteRandomTestFailureContext(std::cerr);
            std::cerr << '\n';
            return 1;
        }
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
            bool anyLiveWave = false;
            bool busyLiveWaveExists = false;
            for (std::uint32_t wave = 0U; wave < state.liveWaves.size(); ++wave)
            {
                anyLiveWave = anyLiveWave || state.liveWaves[wave];
                if (state.liveWaves[wave] && state.busyWaves[wave])
                    busyLiveWaveExists = true;
                if (state.liveWaves[wave] && !state.waitingWaves[wave]
                    && !state.busyWaves[wave])
                    liveWaveCanIssue = true;
            }
            bool terminalBusyWaveExists = false;
            for (std::uint32_t wave = 0U; wave < state.liveWaves.size(); ++wave)
            {
                if (!state.liveWaves[wave] && state.busyWaves[wave])
                    terminalBusyWaveExists = true;
            }
            if (anyLiveWave)
                CHECK(liveWaveCanIssue || busyLiveWaveExists);
            else
                CHECK(terminalBusyWaveExists);
        }
    }
    ::cgx1::testing::ClearRandomTestFailureContext();
    return 0;
}

int main()
{
    if (TestAdmissionAndResourceBoundaries() != 0) return 1;
    if (TestBarrierArrivalsAndIssue() != 0) return 1;
    if (TestFragmentationAndLifecycle() != 0) return 1;
    if (TestAuthoritativePoolTransactionsAndQuiescence() != 0) return 1;
    if (TestSharedMemoryAdmissionAndFragmentation() != 0) return 1;
    if (TestSharedMemoryWaitBarrierAndResponseLifecycle() != 0) return 1;
    if (TestSharedMemoryTerminalDrainAndReset() != 0) return 1;
    if (TestRandomizedSharedMemoryScheduling() != 0) return 1;
    if (TestRandomizedForwardProgress() != 0) return 1;
    std::cout << "[pass] whole-workgroup admission, shared-memory ownership/waits, barriers, lifecycle, and randomized forward progress passed.\n";
    return 0;
}
