// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "workgroup_scheduler.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <random>
#include <stdexcept>
#include <vector>

#define CHECK(x) do { if (!(x)) { std::cerr << "[fail] " #x " line " << __LINE__ << '\n'; return 1; } } while (false)

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
    CHECK(scheduler.Admit(maximum) == AdmissionFailure::None);
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

int TestAuthoritativePoolTransactionsAndQuiescence()
{
    ComputeUnitWorkgroupScheduler variable(
        Limits(8U, 64U, 128U, 2048U, 4U, 64U));
    auto variableDemand = Demand(50U, 2U, 16U);
    variableDemand.vgprRegisterCountsByWave = {9U, 17U};
    CHECK(variable.Admit(variableDemand) == AdmissionFailure::None);
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
    CHECK(variable.RestoreVgpr(50U, 0U, 0U, stalePattern));
    CHECK(variable.ReadVgpr(50U, 0U, 0U) == stalePattern);
    CHECK(variable.FaultWorkgroup(50U));
    CHECK(variable.Admit(Demand(51U, 1U, 9U)) == AdmissionFailure::None);
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
        CHECK(fragmented.Admit(Demand(id, 1U, 32U)) == AdmissionFailure::None);
    CHECK(fragmented.KillWorkgroup(61U));
    CHECK(fragmented.KillWorkgroup(63U));
    std::array<cgx1::matrix::ResidentWaveVgprAllocation, 8U> before{};
    for (std::uint32_t slot = 0U; slot < before.size(); ++slot)
        before[slot] = fragmented.AllocationForSlot(slot);
    auto fragmentedDemand = Demand(64U, 2U, 16U, 2U, 256U);
    fragmentedDemand.vgprRegisterCountsByWave = {8U, 40U};
    CHECK(fragmented.Admit(fragmentedDemand)
        == AdmissionFailure::VgprCapacityFragmented);
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
    CHECK(lifecycle.Admit(Demand(70U, 2U)) == AdmissionFailure::None);
    const auto faultedSlot = *lifecycle.GetWorkgroupState(70U).waveSlots[0U];
    CHECK(lifecycle.BeginWaveExecution(70U, 0U));
    CHECK(lifecycle.ArriveAtBarrier(70U, {1U}).status == BarrierStatus::Waiting);
    CHECK(lifecycle.FaultWave(70U, 0U));
    CHECK(lifecycle.AllocationForWave(70U, 0U).state
        == cgx1::matrix::VgprAllocationState::Active);
    CHECK(!lifecycle.CanIssue(70U, 0U));
    CHECK(lifecycle.CanIssue(70U, 1U));
    CHECK(lifecycle.BarrierGeneration(70U) == 1U);
    CHECK(lifecycle.CompleteWaveExecution(70U, 0U));
    CHECK(lifecycle.AllocationForSlot(faultedSlot).state
        == cgx1::matrix::VgprAllocationState::Free);
    CHECK(lifecycle.TerminateWave(70U, 1U));
    CHECK(lifecycle.WorkgroupCount() == 0U);
    CHECK(lifecycle.OccupiedVgprRows() == 0U);

    CHECK(lifecycle.Admit(Demand(71U, 1U)) == AdmissionFailure::None);
    CHECK(lifecycle.BeginWaveExecution(71U, 0U));
    CHECK(lifecycle.KillWorkgroup(71U));
    CHECK(lifecycle.WorkgroupCount() == 1U);
    CHECK(lifecycle.AllocationForWave(71U, 0U).state
        == cgx1::matrix::VgprAllocationState::Active);
    CHECK(lifecycle.CompleteWaveExecution(71U, 0U));
    CHECK(lifecycle.WorkgroupCount() == 0U);
    CHECK(lifecycle.OccupiedVgprRows() == 0U);

    CHECK(lifecycle.Admit(Demand(72U, 2U)) == AdmissionFailure::None);
    CHECK(lifecycle.BeginWaveExecution(72U, 0U));
    CHECK(lifecycle.ArriveAtBarrier(72U, {1U}).status == BarrierStatus::Waiting);
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
        CHECK(fragmented.Admit(Demand(id, 1U, 8U, 1U, 256U))
            == AdmissionFailure::None);
    CHECK(fragmented.UsedSharedLocalBytes() == 1024U);
    CHECK(fragmented.KillWorkgroup(2U));
    CHECK(fragmented.KillWorkgroup(4U));
    CHECK(fragmented.UsedSharedLocalBytes() == 512U);

    CHECK(fragmented.Admit(Demand(5U, 1U, 8U, 1U, 384U))
        == AdmissionFailure::SharedLocalMemoryFragmented);
    CHECK(fragmented.WorkgroupCount() == 2U);
    CHECK(fragmented.ResidentWaveCount() == 2U);
    CHECK(fragmented.OccupiedVgprRows() == 2U);
    CHECK(fragmented.UsedSharedLocalBytes() == 512U);
    CHECK(!fragmented.SharedLocalMemoryRegionForWorkgroup(5U).has_value());

    CHECK(fragmented.Admit(Demand(6U, 1U, 8U, 1U, 256U))
        == AdmissionFailure::None);
    CHECK(fragmented.UsedSharedLocalBytes() == 768U);
    CHECK(fragmented.CheckInvariants());
    return 0;
}

int TestSharedMemoryWaitBarrierAndResponseLifecycle()
{
    ComputeUnitWorkgroupScheduler scheduler(Limits(8U, 64U, 128U, 256U, 4U, 64U));
    CHECK(scheduler.Admit(Demand(80U, 2U, 16U, 2U, 128U))
        == AdmissionFailure::None);
    CHECK(scheduler.Admit(Demand(81U, 1U, 16U, 2U, 128U))
        == AdmissionFailure::None);

    std::array<std::uint32_t, 32U> addresses{};
    std::array<std::uint32_t, 32U> data{};
    addresses[0] = 0U;
    addresses[1] = 4U;
    data[0] = 0x12345678U;
    data[1] = 0xabcdef01U;
    const auto request = LocalMemoryRequest(
        80U, 0U, 700U, AccessKind::Store, 0x3U, addresses, data);
    CHECK(scheduler.SubmitSharedLocalMemoryRequest(request).status
        == SubmitStatus::Accepted);
    CHECK(!scheduler.CanIssue(80U, 0U));
    CHECK(scheduler.CanIssue(80U, 1U));
    CHECK(scheduler.CanIssue(81U, 0U));
    CHECK(scheduler.GetWorkgroupState(80U).memoryWaitingWaves[0U]);
    CHECK(scheduler.ArriveAtBarrier(80U, {0U}).status == BarrierStatus::WaveBusy);
    CHECK(scheduler.ArriveAtBarrier(80U, {1U}).status == BarrierStatus::Waiting);
    CHECK(scheduler.SubmitSharedLocalMemoryRequest(LocalMemoryRequest(
        80U, 1U, 702U, AccessKind::Load, 0x1U, addresses)).status
        == SubmitStatus::WaveNotIssuable);

    CHECK(scheduler.BeginWaveExecution(81U, 0U));
    CHECK(scheduler.SubmitSharedLocalMemoryRequest(LocalMemoryRequest(
        81U, 0U, 703U, AccessKind::Load, 0x1U, addresses)).status
        == SubmitStatus::WaveNotIssuable);
    CHECK(scheduler.CompleteWaveExecution(81U, 0U));

    const auto siblingSlot = *scheduler.GetWorkgroupState(81U).waveSlots[0U];
    CHECK(scheduler.SelectIssuableWave(std::vector<bool>(8U, true)) == siblingSlot);
    CHECK(scheduler.ServiceSharedLocalMemoryCycle() == 2U);
    CHECK(!scheduler.CanIssue(80U, 0U));
    CHECK(scheduler.ArriveAtBarrier(80U, {0U}).status == BarrierStatus::WaveBusy);
    const auto storeResponse = scheduler.TakeSharedLocalMemoryResponse();
    CHECK(storeResponse.has_value() && storeResponse->transactionTag == 700U);
    CHECK(!scheduler.GetWorkgroupState(80U).memoryWaitingWaves[0U]);
    CHECK(scheduler.CanIssue(80U, 0U));
    CHECK(scheduler.ArriveAtBarrier(80U, {0U}).status == BarrierStatus::Released);
    CHECK(scheduler.BarrierGeneration(80U) == 1U);

    const auto load = LocalMemoryRequest(
        80U, 0U, 701U, AccessKind::Load, 0x3U, addresses);
    CHECK(scheduler.SubmitSharedLocalMemoryRequest(load).status
        == SubmitStatus::Accepted);
    CHECK(scheduler.ServiceSharedLocalMemoryCycle() == 2U);
    const auto loadResponse = scheduler.TakeSharedLocalMemoryResponse();
    CHECK(loadResponse.has_value());
    CHECK(loadResponse->laneData[0] == data[0]);
    CHECK(loadResponse->laneData[1] == data[1]);
    CHECK(scheduler.CanIssue(80U, 0U));
    CHECK(scheduler.KillWorkgroup(80U));
    CHECK(scheduler.KillWorkgroup(81U));
    CHECK(scheduler.UsedSharedLocalBytes() == 0U);
    CHECK(scheduler.CheckInvariants());
    return 0;
}

int TestSharedMemoryTerminalDrainAndReset()
{
    ComputeUnitWorkgroupScheduler scheduler(Limits(4U, 32U, 64U, 256U, 4U, 64U));
    CHECK(scheduler.Admit(Demand(90U, 1U, 16U, 2U, 256U))
        == AdmissionFailure::None);
    const auto canceledSlot = *scheduler.GetWorkgroupState(90U).waveSlots[0U];
    std::array<std::uint32_t, 32U> conflictAddresses{};
    std::array<std::uint32_t, 32U> data{};
    conflictAddresses[0] = 0U;
    conflictAddresses[1] = 128U;
    const auto pending = LocalMemoryRequest(
        90U, 0U, 900U, AccessKind::Store, 0x3U, conflictAddresses, data);
    CHECK(scheduler.SubmitSharedLocalMemoryRequest(pending).status
        == SubmitStatus::Accepted);
    CHECK(scheduler.FaultWave(90U, 0U));
    CHECK(scheduler.WorkgroupCount() == 1U);
    CHECK(scheduler.UsedSharedLocalBytes() == 256U);
    CHECK(scheduler.GetWorkgroupState(90U).memoryWaitingWaves[0U]);
    CHECK(scheduler.AllocationForSlot(canceledSlot).state
        == cgx1::matrix::VgprAllocationState::Active);
    CHECK(scheduler.CheckInvariants());
    CHECK(scheduler.ServiceSharedLocalMemoryCycle() == 1U);
    CHECK(scheduler.WorkgroupCount() == 1U);
    CHECK(scheduler.CheckInvariants());
    CHECK(scheduler.ServiceSharedLocalMemoryCycle() == 1U);
    CHECK(scheduler.WorkgroupCount() == 0U);
    CHECK(scheduler.UsedSharedLocalBytes() == 0U);
    CHECK(!scheduler.TakeSharedLocalMemoryResponse().has_value());

    CHECK(scheduler.Admit(Demand(93U, 2U, 16U, 2U, 256U))
        == AdmissionFailure::None);
    CHECK(scheduler.SubmitSharedLocalMemoryRequest(LocalMemoryRequest(
        93U, 0U, 903U, AccessKind::Store, 0x3U, conflictAddresses, data)).status
        == SubmitStatus::Accepted);
    CHECK(scheduler.ArriveAtBarrier(93U, {1U}).status == BarrierStatus::Waiting);
    CHECK(scheduler.FaultWave(93U, 0U));
    CHECK(scheduler.BarrierGeneration(93U) == 1U);
    CHECK(scheduler.CanIssue(93U, 1U));
    CHECK(scheduler.GetWorkgroupState(93U).memoryWaitingWaves[0U]);
    CHECK(scheduler.UsedSharedLocalBytes() == 256U);
    CHECK(scheduler.ServiceSharedLocalMemoryCycle() == 1U);
    CHECK(scheduler.ServiceSharedLocalMemoryCycle() == 1U);
    CHECK(!scheduler.TakeSharedLocalMemoryResponse().has_value());
    CHECK(scheduler.WorkgroupCount() == 1U);
    CHECK(scheduler.UsedSharedLocalBytes() == 256U);
    CHECK(scheduler.TerminateWave(93U, 1U));
    CHECK(scheduler.WorkgroupCount() == 0U);
    CHECK(scheduler.UsedSharedLocalBytes() == 0U);

    CHECK(scheduler.Admit(Demand(91U, 1U, 16U, 2U, 128U))
        == AdmissionFailure::None);
    std::array<std::uint32_t, 32U> oneAddress{};
    const auto completed = LocalMemoryRequest(
        91U, 0U, 901U, AccessKind::Load, 0x1U, oneAddress);
    CHECK(scheduler.SubmitSharedLocalMemoryRequest(completed).status
        == SubmitStatus::Accepted);
    CHECK(scheduler.ServiceSharedLocalMemoryCycle() == 1U);
    CHECK(scheduler.KillWorkgroup(91U));
    CHECK(scheduler.WorkgroupCount() == 0U);
    CHECK(!scheduler.TakeSharedLocalMemoryResponse().has_value());
    CHECK(scheduler.UsedSharedLocalBytes() == 0U);

    CHECK(scheduler.Admit(Demand(92U, 1U, 16U, 2U, 256U))
        == AdmissionFailure::None);
    CHECK(scheduler.SubmitSharedLocalMemoryRequest(LocalMemoryRequest(
        92U, 0U, 902U, AccessKind::Load, 0x3U, conflictAddresses)).status
        == SubmitStatus::Accepted);
    CHECK(scheduler.ServiceSharedLocalMemoryCycle() == 1U);
    scheduler.Reset();
    CHECK(scheduler.WorkgroupCount() == 0U);
    CHECK(scheduler.ResidentWaveCount() == 0U);
    CHECK(scheduler.OccupiedVgprRows() == 0U);
    CHECK(scheduler.UsedSharedLocalBytes() == 0U);
    CHECK(!scheduler.TakeSharedLocalMemoryResponse().has_value());
    CHECK(scheduler.CheckInvariants());
    CHECK(scheduler.Admit(Demand(92U, 1U)) == AdmissionFailure::None);
    CHECK(scheduler.KillWorkgroup(92U));
    return 0;
}

int TestRandomizedSharedMemoryScheduling()
{
    ComputeUnitWorkgroupScheduler scheduler(Limits(8U, 64U, 128U, 1024U, 4U, 64U));
    CHECK(scheduler.Admit(Demand(100U, 2U, 16U, 2U, 512U))
        == AdmissionFailure::None);
    CHECK(scheduler.Admit(Demand(101U, 2U, 16U, 2U, 512U))
        == AdmissionFailure::None);
    std::mt19937 random(0x5A17C0DEU);
    std::uint64_t tag = 1000U;
    std::uint32_t completions = 0U;
    std::uint32_t barrierReleases = 0U;
    for (std::uint32_t cycle = 0U; cycle < 5000U; ++cycle)
    {
        const auto group = 100U + (random() % 2U);
        const auto wave = static_cast<std::uint32_t>(random() % 2U);
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
    CHECK(scheduler.KillWorkgroup(100U));
    CHECK(scheduler.KillWorkgroup(101U));
    for (std::uint32_t cycle = 0U; cycle < 8U && scheduler.WorkgroupCount() != 0U; ++cycle)
    {
        (void)scheduler.ServiceSharedLocalMemoryCycle();
        while (scheduler.TakeSharedLocalMemoryResponse())
            ++completions;
    }
    CHECK(scheduler.WorkgroupCount() == 0U);
    CHECK(scheduler.UsedSharedLocalBytes() == 0U);
    CHECK(scheduler.CheckInvariants());
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
                      << cycle << " action " << action << '\n';
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
