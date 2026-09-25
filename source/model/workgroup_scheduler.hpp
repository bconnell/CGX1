// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "../matrix/cgx1_matrix_vgpr_pool.hpp"

#include <algorithm>
#include <cstdint>
#include <optional>
#include <stdexcept>
#include <unordered_map>
#include <utility>
#include <vector>

namespace cgx1::compute {

inline constexpr std::uint32_t kVgprRegistersPerPhysicalRow = 8U;
inline constexpr std::uint32_t kMaximumArchitecturalVgprsPerWave = 256U;

struct CuResourceLimits
{
    std::uint32_t residentWaveSlots;
    std::uint32_t pooledVgprRows;
    std::uint32_t scalarPredicateStateUnits;
    std::uint32_t sharedLocalBytes;
    std::uint32_t barrierContexts;
    std::uint32_t otherWorkgroupStateUnits;
};

struct WorkgroupDemand
{
    std::uint64_t id;
    std::uint32_t waveCount;
    std::uint32_t vgprsPerWave;
    std::uint32_t scalarPredicateUnitsPerWave;
    std::uint32_t sharedLocalBytes;
    std::uint32_t otherWorkgroupStateUnits;
    std::vector<std::uint32_t> vgprRegisterCountsByWave;
};

enum class AdmissionFailure : std::uint8_t
{
    None = 0,
    InvalidWaveCount,
    WorkgroupExceedsResidentWaveCapacity,
    DuplicateWorkgroupId,
    BarrierContextsUnavailable,
    InvalidVgprDemand,
    VgprDemandExceedsCuCapacity,
    ResidentWaveSlotsUnavailable,
    VgprCapacityUnavailable,
    VgprCapacityFragmented,
    VgprAllocationFailed,
    ScalarPredicateStateExceedsCuCapacity,
    ScalarPredicateStateUnavailable,
    SharedLocalMemoryExceedsCuCapacity,
    SharedLocalMemoryUnavailable,
    OtherWorkgroupStateExceedsCuCapacity,
    OtherWorkgroupStateUnavailable
};

enum class BarrierStatus : std::uint8_t
{
    Waiting = 0,
    Released,
    InvalidWorkgroup,
    EmptyArrival,
    InvalidWaveIndex,
    WaveAlreadyWaiting,
    DuplicateWaveInArrival,
    WaveBusy
};

struct BarrierResult
{
    BarrierStatus status = BarrierStatus::InvalidWorkgroup;
    std::uint32_t generation = 0U;
    std::uint32_t releasedWaveCount = 0U;
};

struct WorkgroupStateSnapshot
{
    std::uint32_t generation = 0U;
    std::vector<bool> liveWaves;
    std::vector<bool> waitingWaves;
    std::vector<bool> busyWaves;
    std::vector<bool> allocatedWaves;
    std::vector<std::optional<std::uint32_t>> waveSlots;
};

class ComputeUnitWorkgroupScheduler
{
public:
    explicit ComputeUnitWorkgroupScheduler(CuResourceLimits limits)
        : limits_(limits),
          vgprPool_(limits.pooledVgprRows, limits.residentWaveSlots),
          vgprStorage_(limits.pooledVgprRows),
          waveOwners_(limits.residentWaveSlots)
    {
        if (limits_.residentWaveSlots == 0U || limits_.pooledVgprRows == 0U
            || limits_.barrierContexts == 0U)
        {
            throw std::invalid_argument(
                "compute-unit wave, VGPR, and barrier capacities must be nonzero");
        }
    }

    [[nodiscard]] AdmissionFailure Admit(const WorkgroupDemand& demand)
    {
        if (workgroups_.contains(demand.id))
            return AdmissionFailure::DuplicateWorkgroupId;
        if (demand.waveCount == 0U)
            return AdmissionFailure::InvalidWaveCount;
        if (demand.waveCount > limits_.residentWaveSlots)
            return AdmissionFailure::WorkgroupExceedsResidentWaveCapacity;
        if (!demand.vgprRegisterCountsByWave.empty()
            && demand.vgprRegisterCountsByWave.size() != demand.waveCount)
        {
            return AdmissionFailure::InvalidVgprDemand;
        }
        const auto registersForWave = [&](std::uint32_t wave)
        {
            return demand.vgprRegisterCountsByWave.empty()
                ? demand.vgprsPerWave
                : demand.vgprRegisterCountsByWave[wave];
        };
        std::uint64_t totalRows = 0U;
        for (std::uint32_t wave = 0U; wave < demand.waveCount; ++wave)
        {
            const auto registers = registersForWave(wave);
            if (registers == 0U
                || registers > matrix::kArchitecturalVgprsPerWave)
            {
                return AdmissionFailure::InvalidVgprDemand;
            }
            totalRows += matrix::VgprRowsForRegisterCount(registers);
        }
        if (totalRows > limits_.pooledVgprRows)
            return AdmissionFailure::VgprDemandExceedsCuCapacity;

        const std::uint64_t scalarDemand =
            static_cast<std::uint64_t>(demand.scalarPredicateUnitsPerWave)
            * demand.waveCount;
        if (scalarDemand > limits_.scalarPredicateStateUnits)
            return AdmissionFailure::ScalarPredicateStateExceedsCuCapacity;
        if (demand.sharedLocalBytes > limits_.sharedLocalBytes)
            return AdmissionFailure::SharedLocalMemoryExceedsCuCapacity;
        if (demand.otherWorkgroupStateUnits > limits_.otherWorkgroupStateUnits)
            return AdmissionFailure::OtherWorkgroupStateExceedsCuCapacity;
        if (workgroups_.size() >= limits_.barrierContexts)
            return AdmissionFailure::BarrierContextsUnavailable;

        const auto freeSlots = FindFreeWaveSlots(demand.waveCount);
        if (freeSlots.size() != demand.waveCount)
            return AdmissionFailure::ResidentWaveSlotsUnavailable;

        const std::uint32_t freeRows =
            limits_.pooledVgprRows - vgprPool_.OccupiedRows();
        if (freeRows < totalRows)
            return AdmissionFailure::VgprCapacityUnavailable;

        if (UsedScalarPredicateUnits() + scalarDemand
            > limits_.scalarPredicateStateUnits)
        {
            return AdmissionFailure::ScalarPredicateStateUnavailable;
        }
        if (UsedSharedLocalBytes() + demand.sharedLocalBytes
            > limits_.sharedLocalBytes)
        {
            return AdmissionFailure::SharedLocalMemoryUnavailable;
        }
        if (UsedOtherWorkgroupUnits() + demand.otherWorkgroupStateUnits
            > limits_.otherWorkgroupStateUnits)
        {
            return AdmissionFailure::OtherWorkgroupStateUnavailable;
        }

        // Allocate all potentially throwing scheduler metadata before touching
        // the authoritative VGPR pool. The provisional entry is private to
        // this synchronous call until its waves are committed below.
        Workgroup stagedWorkgroup;
        stagedWorkgroup.demand = demand;
        stagedWorkgroup.waves.reserve(demand.waveCount);
        for (std::uint32_t wave = 0U; wave < demand.waveCount; ++wave)
        {
            stagedWorkgroup.waves.push_back(
                Wave{freeSlots[wave], false, false, false, false});
        }
        auto [staged, inserted] =
            workgroups_.emplace(demand.id, std::move(stagedWorkgroup));
        if (!inserted)
            return AdmissionFailure::DuplicateWorkgroupId;

        // Keep ownership private until every wave has a real, sanitized,
        // active allocation from the authoritative first-fit pool.
        std::uint32_t reserved = 0U;
        try
        {
            for (std::uint32_t wave = 0U; wave < demand.waveCount; ++wave)
            {
                if (!vgprPool_.Reserve(
                        freeSlots[wave], registersForWave(wave)))
                {
                    RollbackAllocations(freeSlots, reserved);
                    workgroups_.erase(staged);
                    return AdmissionFailure::VgprCapacityFragmented;
                }
                ++reserved;
            }

            for (const auto slot : freeSlots)
                vgprStorage_.InvalidateReservedAllocation(vgprPool_, slot);
            for (const auto slot : freeSlots)
            {
                if (!vgprPool_.Activate(slot))
                {
                    RollbackAllocations(freeSlots, reserved);
                    workgroups_.erase(staged);
                    return AdmissionFailure::VgprAllocationFailed;
                }
            }
        }
        catch (const std::exception&)
        {
            RollbackAllocations(freeSlots, reserved);
            workgroups_.erase(staged);
            return AdmissionFailure::VgprAllocationFailed;
        }

        // All operations after pool activation are non-allocating POD updates.
        for (std::uint32_t wave = 0U; wave < demand.waveCount; ++wave)
        {
            staged->second.waves[wave].live = true;
            staged->second.waves[wave].resourceHeld = true;
            waveOwners_[freeSlots[wave]] = WaveOwner{demand.id, wave};
        }
        return AdmissionFailure::None;
    }

    [[nodiscard]] BarrierResult ArriveAtBarrier(
        std::uint64_t workgroupId,
        const std::vector<std::uint32_t>& waveIndices)
    {
        const auto found = workgroups_.find(workgroupId);
        if (found == workgroups_.end())
            return {BarrierStatus::InvalidWorkgroup, 0U, 0U};
        auto& workgroup = found->second;
        if (waveIndices.empty())
            return {BarrierStatus::EmptyArrival, workgroup.generation, 0U};

        std::vector<bool> mentioned(workgroup.waves.size(), false);
        for (const auto waveIndex : waveIndices)
        {
            if (waveIndex >= workgroup.waves.size())
                return {BarrierStatus::InvalidWaveIndex, workgroup.generation, 0U};
            if (mentioned[waveIndex])
                return {BarrierStatus::DuplicateWaveInArrival, workgroup.generation, 0U};
            mentioned[waveIndex] = true;
            const auto& wave = workgroup.waves[waveIndex];
            if (!wave.live)
                return {BarrierStatus::InvalidWaveIndex, workgroup.generation, 0U};
            if (wave.waiting)
                return {BarrierStatus::WaveAlreadyWaiting, workgroup.generation, 0U};
            if (wave.busy)
                return {BarrierStatus::WaveBusy, workgroup.generation, 0U};
        }

        for (const auto waveIndex : waveIndices)
            workgroup.waves[waveIndex].waiting = true;

        std::uint32_t releasedWaveCount = 0U;
        if (ReleaseBarrierIfComplete(workgroup, releasedWaveCount))
        {
            return {
                BarrierStatus::Released,
                workgroup.generation,
                releasedWaveCount};
        }
        return {BarrierStatus::Waiting, workgroup.generation, 0U};
    }

    bool TerminateWave(std::uint64_t workgroupId, std::uint32_t waveIndex)
    {
        const auto found = workgroups_.find(workgroupId);
        if (found == workgroups_.end() || waveIndex >= found->second.waves.size())
            return false;
        auto& workgroup = found->second;
        auto& wave = workgroup.waves[waveIndex];
        if (!wave.live)
            return false;

        wave.live = false;
        wave.waiting = false;
        if (!wave.busy)
            ReleaseWaveResources(wave);
        std::uint32_t ignoredReleasedWaveCount = 0U;
        (void)ReleaseBarrierIfComplete(workgroup, ignoredReleasedWaveCount);
        EraseIfResourcesReleased(found);
        return true;
    }

    bool FaultWave(std::uint64_t workgroupId, std::uint32_t waveIndex)
    {
        return TerminateWave(workgroupId, waveIndex);
    }

    bool BeginWaveExecution(std::uint64_t workgroupId, std::uint32_t waveIndex)
    {
        const auto found = workgroups_.find(workgroupId);
        if (found == workgroups_.end() || waveIndex >= found->second.waves.size())
            return false;
        auto& wave = found->second.waves[waveIndex];
        if (!wave.live || wave.waiting || wave.busy)
            return false;
        wave.busy = true;
        return true;
    }

    bool CompleteWaveExecution(std::uint64_t workgroupId, std::uint32_t waveIndex)
    {
        const auto found = workgroups_.find(workgroupId);
        if (found == workgroups_.end() || waveIndex >= found->second.waves.size())
            return false;
        auto& workgroup = found->second;
        auto& wave = workgroup.waves[waveIndex];
        if (!wave.busy)
            return false;
        wave.busy = false;
        if (!wave.live)
            ReleaseWaveResources(wave);
        EraseIfResourcesReleased(found);
        return true;
    }

    bool KillWorkgroup(std::uint64_t workgroupId)
    {
        return DestroyWorkgroup(workgroupId);
    }

    bool FaultWorkgroup(std::uint64_t workgroupId)
    {
        return DestroyWorkgroup(workgroupId);
    }

    void Reset()
    {
        workgroups_.clear();
        std::fill(waveOwners_.begin(), waveOwners_.end(), std::nullopt);
        vgprPool_.Reset();
        vgprStorage_.Reset();
        nextIssueSlot_ = 0U;
    }

    [[nodiscard]] bool CanIssue(
        std::uint64_t workgroupId,
        std::uint32_t waveIndex) const noexcept
    {
        const auto found = workgroups_.find(workgroupId);
        return found != workgroups_.end()
            && waveIndex < found->second.waves.size()
            && found->second.waves[waveIndex].live
            && !found->second.waves[waveIndex].waiting
            && !found->second.waves[waveIndex].busy;
    }

    [[nodiscard]] std::optional<std::uint32_t> SelectIssuableWave(
        const std::vector<bool>& dependencyReady,
        bool accepted = true)
    {
        if (dependencyReady.size() != waveOwners_.size())
            throw std::invalid_argument(
                "dependency-ready vector must match resident-wave slots");
        for (std::uint32_t offset = 0U; offset < waveOwners_.size(); ++offset)
        {
            const std::uint32_t slot =
                (nextIssueSlot_ + offset) % static_cast<std::uint32_t>(waveOwners_.size());
            if (!waveOwners_[slot].has_value() || !dependencyReady[slot])
                continue;
            const auto& owner = *waveOwners_[slot];
            if (!CanIssue(owner.workgroupId, owner.localWaveIndex))
                continue;
            if (accepted)
            {
                nextIssueSlot_ = (slot + 1U)
                    % static_cast<std::uint32_t>(waveOwners_.size());
            }
            return slot;
        }
        return std::nullopt;
    }

    [[nodiscard]] bool AllLiveWavesResident(std::uint64_t workgroupId) const noexcept
    {
        const auto found = workgroups_.find(workgroupId);
        if (found == workgroups_.end())
            return false;
        for (std::uint32_t local = 0U; local < found->second.waves.size(); ++local)
        {
            const auto& wave = found->second.waves[local];
            if (!wave.live)
                continue;
            if (wave.slot >= waveOwners_.size() || !waveOwners_[wave.slot].has_value())
                return false;
            const auto& owner = *waveOwners_[wave.slot];
            if (owner.workgroupId != workgroupId || owner.localWaveIndex != local
                || !wave.resourceHeld
                || vgprPool_.Allocation(wave.slot).state
                    != matrix::VgprAllocationState::Active)
            {
                return false;
            }
        }
        return true;
    }

    [[nodiscard]] WorkgroupStateSnapshot GetWorkgroupState(
        std::uint64_t workgroupId) const
    {
        const auto found = workgroups_.find(workgroupId);
        if (found == workgroups_.end())
            throw std::out_of_range("workgroup is not resident");
        WorkgroupStateSnapshot snapshot;
        snapshot.generation = found->second.generation;
        for (const auto& wave : found->second.waves)
        {
            snapshot.liveWaves.push_back(wave.live);
            snapshot.waitingWaves.push_back(wave.waiting);
            snapshot.busyWaves.push_back(wave.busy);
            snapshot.allocatedWaves.push_back(wave.resourceHeld);
            snapshot.waveSlots.push_back(
                wave.resourceHeld
                    ? std::optional<std::uint32_t>(wave.slot)
                    : std::nullopt);
        }
        return snapshot;
    }

    [[nodiscard]] const matrix::ResidentWaveVgprAllocation& AllocationForWave(
        std::uint64_t workgroupId,
        std::uint32_t waveIndex) const
    {
        const auto found = workgroups_.find(workgroupId);
        if (found == workgroups_.end() || waveIndex >= found->second.waves.size()
            || !found->second.waves[waveIndex].resourceHeld)
        {
            throw std::out_of_range("wave has no resident VGPR allocation");
        }
        return vgprPool_.Allocation(found->second.waves[waveIndex].slot);
    }

    [[nodiscard]] const matrix::ResidentWaveVgprAllocation& AllocationForSlot(
        std::uint32_t waveSlot) const
    {
        return vgprPool_.Allocation(waveSlot);
    }

    bool RestoreVgpr(
        std::uint64_t workgroupId,
        std::uint32_t waveIndex,
        std::uint8_t architecturalRegister,
        const matrix::PooledWaveRegister& value)
    {
        const auto found = workgroups_.find(workgroupId);
        if (found == workgroups_.end() || waveIndex >= found->second.waves.size())
            return false;
        const auto& wave = found->second.waves[waveIndex];
        if (!wave.resourceHeld
            || vgprPool_.Allocation(wave.slot).state
                != matrix::VgprAllocationState::Active)
        {
            return false;
        }
        try
        {
            vgprStorage_.Write(
                vgprPool_, wave.slot, architecturalRegister, value);
        }
        catch (const std::exception&)
        {
            return false;
        }
        return true;
    }

    [[nodiscard]] matrix::PooledWaveRegister ReadVgpr(
        std::uint64_t workgroupId,
        std::uint32_t waveIndex,
        std::uint8_t architecturalRegister) const
    {
        const auto found = workgroups_.find(workgroupId);
        if (found == workgroups_.end() || waveIndex >= found->second.waves.size()
            || !found->second.waves[waveIndex].resourceHeld)
        {
            throw std::logic_error("wave has no resident VGPR allocation");
        }
        return vgprStorage_.Read(
            vgprPool_, found->second.waves[waveIndex].slot,
            architecturalRegister);
    }

    [[nodiscard]] std::uint32_t BarrierGeneration(std::uint64_t workgroupId) const
    {
        const auto found = workgroups_.find(workgroupId);
        if (found == workgroups_.end())
            throw std::out_of_range("workgroup is not resident");
        return found->second.generation;
    }

    [[nodiscard]] std::vector<std::uint64_t> ActiveWorkgroupIds() const
    {
        std::vector<std::uint64_t> ids;
        ids.reserve(workgroups_.size());
        for (const auto& [id, ignored] : workgroups_)
        {
            (void)ignored;
            ids.push_back(id);
        }
        std::sort(ids.begin(), ids.end());
        return ids;
    }

    [[nodiscard]] std::uint32_t WorkgroupCount() const noexcept
    {
        return static_cast<std::uint32_t>(workgroups_.size());
    }

    [[nodiscard]] std::uint32_t ResidentWaveCount() const noexcept
    {
        return static_cast<std::uint32_t>(std::count_if(
            waveOwners_.begin(), waveOwners_.end(),
            [](const auto& owner) { return owner.has_value(); }));
    }

    [[nodiscard]] std::uint32_t OccupiedVgprRows() const noexcept
    {
        return vgprPool_.OccupiedRows();
    }

    [[nodiscard]] std::uint32_t UsedScalarPredicateUnits() const noexcept
    {
        std::uint64_t total = 0U;
        for (const auto& [id, workgroup] : workgroups_)
        {
            (void)id;
            for (const auto& wave : workgroup.waves)
            {
                if (wave.resourceHeld)
                    total += workgroup.demand.scalarPredicateUnitsPerWave;
            }
        }
        return static_cast<std::uint32_t>(total);
    }

    [[nodiscard]] std::uint32_t UsedSharedLocalBytes() const noexcept
    {
        std::uint64_t total = 0U;
        for (const auto& [id, workgroup] : workgroups_)
        {
            (void)id;
            total += workgroup.demand.sharedLocalBytes;
        }
        return static_cast<std::uint32_t>(total);
    }

    [[nodiscard]] std::uint32_t UsedOtherWorkgroupUnits() const noexcept
    {
        std::uint64_t total = 0U;
        for (const auto& [id, workgroup] : workgroups_)
        {
            (void)id;
            total += workgroup.demand.otherWorkgroupStateUnits;
        }
        return static_cast<std::uint32_t>(total);
    }

    [[nodiscard]] bool CheckInvariants() const
    {
        if (workgroups_.size() > limits_.barrierContexts
            || ResidentWaveCount() > limits_.residentWaveSlots
            || OccupiedVgprRows() > limits_.pooledVgprRows
            || !vgprPool_.InvariantsHold()
            || UsedScalarPredicateUnits() > limits_.scalarPredicateStateUnits
            || UsedSharedLocalBytes() > limits_.sharedLocalBytes
            || UsedOtherWorkgroupUnits() > limits_.otherWorkgroupStateUnits)
        {
            return false;
        }

        std::vector<bool> observedSlots(waveOwners_.size(), false);
        for (const auto& [id, workgroup] : workgroups_)
        {
            bool anyResourceHeld = false;
            bool anyLive = false;
            bool allLiveWaiting = true;
            for (std::uint32_t local = 0U; local < workgroup.waves.size(); ++local)
            {
                const auto& wave = workgroup.waves[local];
                if (wave.waiting && (!wave.live || wave.busy))
                    return false;
                anyLive = anyLive || wave.live;
                if (!wave.live)
                {
                    if (wave.waiting || wave.busy && !wave.resourceHeld)
                        return false;
                }
                if (wave.live)
                    allLiveWaiting = allLiveWaiting && wave.waiting;

                if (!wave.resourceHeld)
                {
                    if (wave.live || wave.busy)
                        return false;
                    continue;
                }

                anyResourceHeld = true;
                if (wave.slot >= waveOwners_.size() || observedSlots[wave.slot]
                    || !waveOwners_[wave.slot].has_value()
                    || vgprPool_.Allocation(wave.slot).state
                        != matrix::VgprAllocationState::Active)
                    return false;
                const auto& owner = *waveOwners_[wave.slot];
                if (owner.workgroupId != id || owner.localWaveIndex != local)
                {
                    return false;
                }
                observedSlots[wave.slot] = true;
            }
            if (!anyResourceHeld || (anyLive && allLiveWaiting))
                return false;
        }

        for (std::uint32_t slot = 0U; slot < waveOwners_.size(); ++slot)
        {
            if (waveOwners_[slot].has_value() != observedSlots[slot])
                return false;
        }
        return true;
    }

private:
    struct WaveOwner
    {
        std::uint64_t workgroupId;
        std::uint32_t localWaveIndex;
    };

    struct Wave
    {
        std::uint32_t slot;
        bool live;
        bool waiting;
        bool busy;
        bool resourceHeld;
    };

    struct Workgroup
    {
        WorkgroupDemand demand{};
        std::vector<Wave> waves;
        std::uint32_t generation = 0U;
    };

    [[nodiscard]] std::vector<std::uint32_t> FindFreeWaveSlots(
        std::uint32_t requested) const
    {
        std::vector<std::uint32_t> slots;
        slots.reserve(requested);
        for (std::uint32_t slot = 0U; slot < waveOwners_.size(); ++slot)
        {
            if (!waveOwners_[slot].has_value()
                && vgprPool_.Allocation(slot).state
                    == matrix::VgprAllocationState::Free)
                slots.push_back(slot);
            if (slots.size() == requested)
                break;
        }
        return slots;
    }

    void RollbackAllocations(
        const std::vector<std::uint32_t>& slots,
        std::uint32_t count) noexcept
    {
        for (std::uint32_t index = 0U; index < count; ++index)
        {
            const auto slot = slots[index];
            if (vgprPool_.Allocation(slot).state
                != matrix::VgprAllocationState::Free)
                (void)vgprPool_.Release(slot, true);
        }
    }

    void ReleaseWaveResources(Wave& wave)
    {
        if (!wave.resourceHeld)
            return;
        if (wave.busy || !vgprPool_.Release(wave.slot, !wave.busy))
            throw std::logic_error("attempted to release a busy VGPR allocation");
        waveOwners_[wave.slot].reset();
        wave.resourceHeld = false;
    }

    using WorkgroupIterator = std::unordered_map<std::uint64_t, Workgroup>::iterator;

    void EraseIfResourcesReleased(WorkgroupIterator found)
    {
        const bool anyResourcesHeld = std::any_of(
            found->second.waves.begin(), found->second.waves.end(),
            [](const Wave& wave) { return wave.resourceHeld; });
        if (!anyResourcesHeld)
            workgroups_.erase(found);
    }

    [[nodiscard]] bool ReleaseBarrierIfComplete(
        Workgroup& workgroup,
        std::uint32_t& releasedWaveCount)
    {
        bool anyLive = false;
        bool allArrived = true;
        std::uint32_t arrivedCount = 0U;
        for (const auto& wave : workgroup.waves)
        {
            if (!wave.live)
                continue;
            anyLive = true;
            allArrived = allArrived && wave.waiting;
            arrivedCount += wave.waiting ? 1U : 0U;
        }
        if (!anyLive || !allArrived)
            return false;
        for (auto& wave : workgroup.waves)
        {
            if (wave.live)
                wave.waiting = false;
        }
        ++workgroup.generation;
        releasedWaveCount = arrivedCount;
        return true;
    }

    bool DestroyWorkgroup(std::uint64_t workgroupId)
    {
        const auto found = workgroups_.find(workgroupId);
        if (found == workgroups_.end())
            return false;
        auto& workgroup = found->second;
        for (auto& wave : workgroup.waves)
        {
            wave.live = false;
            wave.waiting = false;
            if (!wave.busy)
                ReleaseWaveResources(wave);
        }
        EraseIfResourcesReleased(found);
        return true;
    }

    CuResourceLimits limits_;
    matrix::ResidentWaveVgprPool vgprPool_;
    matrix::PooledVgprStorage vgprStorage_;
    std::unordered_map<std::uint64_t, Workgroup> workgroups_;
    std::vector<std::optional<WaveOwner>> waveOwners_;
    std::uint32_t nextIssueSlot_ = 0U;
};

} // namespace cgx1::compute
