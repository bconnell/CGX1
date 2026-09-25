// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

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
    DuplicateWaveInArrival
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
    std::vector<std::optional<std::uint32_t>> waveSlots;
};

class ComputeUnitWorkgroupScheduler
{
public:
    explicit ComputeUnitWorkgroupScheduler(CuResourceLimits limits)
        : limits_(limits), waveOwners_(limits.residentWaveSlots)
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
        if (demand.vgprsPerWave == 0U
            || demand.vgprsPerWave > kMaximumArchitecturalVgprsPerWave)
        {
            return AdmissionFailure::InvalidVgprDemand;
        }

        const std::uint32_t rowsPerWave = RowsForRegisters(demand.vgprsPerWave);
        const std::uint64_t totalRows =
            static_cast<std::uint64_t>(rowsPerWave) * demand.waveCount;
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

        const auto occupiedRows = OccupiedVgprRowsBitmap();
        const std::uint32_t freeRows = static_cast<std::uint32_t>(
            std::count(occupiedRows.begin(), occupiedRows.end(), false));
        if (freeRows < totalRows)
            return AdmissionFailure::VgprCapacityUnavailable;

        const auto rowBases = PlanVgprRows(
            occupiedRows, demand.waveCount, rowsPerWave);
        if (!rowBases.has_value())
            return AdmissionFailure::VgprCapacityFragmented;

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

        Workgroup workgroup;
        workgroup.demand = demand;
        workgroup.waves.resize(demand.waveCount);
        for (std::uint32_t wave = 0U; wave < demand.waveCount; ++wave)
        {
            workgroup.waves[wave] = Wave{
                freeSlots[wave], (*rowBases)[wave], rowsPerWave, true, false};
        }

        for (std::uint32_t wave = 0U; wave < demand.waveCount; ++wave)
            waveOwners_[freeSlots[wave]] = WaveOwner{demand.id, wave};
        workgroups_.emplace(demand.id, std::move(workgroup));
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

        waveOwners_[wave.slot].reset();
        wave.live = false;
        wave.waiting = false;
        wave.rowCount = 0U;
        const bool anyLive = std::any_of(
            workgroup.waves.begin(), workgroup.waves.end(),
            [](const Wave& candidate) { return candidate.live; });
        if (!anyLive)
        {
            workgroups_.erase(found);
            return true;
        }
        std::uint32_t ignoredReleasedWaveCount = 0U;
        (void)ReleaseBarrierIfComplete(workgroup, ignoredReleasedWaveCount);
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
            && !found->second.waves[waveIndex].waiting;
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
                || wave.rowCount == 0U)
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
            snapshot.waveSlots.push_back(
                wave.live ? std::optional<std::uint32_t>(wave.slot) : std::nullopt);
        }
        return snapshot;
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
        const auto occupied = OccupiedVgprRowsBitmap();
        return static_cast<std::uint32_t>(
            std::count(occupied.begin(), occupied.end(), true));
    }

    [[nodiscard]] std::uint32_t UsedScalarPredicateUnits() const noexcept
    {
        std::uint64_t total = 0U;
        for (const auto& [id, workgroup] : workgroups_)
        {
            (void)id;
            for (const auto& wave : workgroup.waves)
            {
                if (wave.live)
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
            || UsedScalarPredicateUnits() > limits_.scalarPredicateStateUnits
            || UsedSharedLocalBytes() > limits_.sharedLocalBytes
            || UsedOtherWorkgroupUnits() > limits_.otherWorkgroupStateUnits)
        {
            return false;
        }

        std::vector<bool> rows(limits_.pooledVgprRows, false);
        std::vector<bool> observedSlots(waveOwners_.size(), false);
        for (const auto& [id, workgroup] : workgroups_)
        {
            bool anyLive = false;
            bool allLiveWaiting = true;
            for (std::uint32_t local = 0U; local < workgroup.waves.size(); ++local)
            {
                const auto& wave = workgroup.waves[local];
                if (!wave.live)
                {
                    if (wave.waiting)
                        return false;
                    continue;
                }
                anyLive = true;
                allLiveWaiting = allLiveWaiting && wave.waiting;
                if (wave.slot >= waveOwners_.size() || observedSlots[wave.slot]
                    || !waveOwners_[wave.slot].has_value())
                {
                    return false;
                }
                const auto& owner = *waveOwners_[wave.slot];
                if (owner.workgroupId != id || owner.localWaveIndex != local
                    || wave.rowCount == 0U
                    || wave.rowBase + wave.rowCount > rows.size())
                {
                    return false;
                }
                observedSlots[wave.slot] = true;
                for (std::uint32_t row = wave.rowBase;
                     row < wave.rowBase + wave.rowCount;
                     ++row)
                {
                    if (rows[row])
                        return false;
                    rows[row] = true;
                }
            }
            if (!anyLive || allLiveWaiting)
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
        std::uint32_t rowBase;
        std::uint32_t rowCount;
        bool live;
        bool waiting;
    };

    struct Workgroup
    {
        WorkgroupDemand demand{};
        std::vector<Wave> waves;
        std::uint32_t generation = 0U;
    };

    [[nodiscard]] static std::uint32_t RowsForRegisters(std::uint32_t registers)
    {
        return (registers + kVgprRegistersPerPhysicalRow - 1U)
            / kVgprRegistersPerPhysicalRow;
    }

    [[nodiscard]] std::vector<std::uint32_t> FindFreeWaveSlots(
        std::uint32_t requested) const
    {
        std::vector<std::uint32_t> slots;
        slots.reserve(requested);
        for (std::uint32_t slot = 0U; slot < waveOwners_.size(); ++slot)
        {
            if (!waveOwners_[slot].has_value())
                slots.push_back(slot);
            if (slots.size() == requested)
                break;
        }
        return slots;
    }

    [[nodiscard]] std::vector<bool> OccupiedVgprRowsBitmap() const
    {
        std::vector<bool> occupied(limits_.pooledVgprRows, false);
        for (const auto& [id, workgroup] : workgroups_)
        {
            (void)id;
            for (const auto& wave : workgroup.waves)
            {
                if (!wave.live)
                    continue;
                for (std::uint32_t row = wave.rowBase;
                     row < wave.rowBase + wave.rowCount;
                     ++row)
                {
                    occupied[row] = true;
                }
            }
        }
        return occupied;
    }

    [[nodiscard]] static std::optional<std::vector<std::uint32_t>> PlanVgprRows(
        std::vector<bool> occupied,
        std::uint32_t waveCount,
        std::uint32_t rowsPerWave)
    {
        std::vector<std::uint32_t> bases;
        bases.reserve(waveCount);
        for (std::uint32_t wave = 0U; wave < waveCount; ++wave)
        {
            bool found = false;
            for (std::uint32_t base = 0U;
                 base + rowsPerWave <= occupied.size();
                 ++base)
            {
                bool free = true;
                for (std::uint32_t row = 0U; row < rowsPerWave; ++row)
                {
                    if (occupied[base + row])
                    {
                        free = false;
                        break;
                    }
                }
                if (!free)
                    continue;
                bases.push_back(base);
                for (std::uint32_t row = 0U; row < rowsPerWave; ++row)
                    occupied[base + row] = true;
                found = true;
                break;
            }
            if (!found)
                return std::nullopt;
        }
        return bases;
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
        for (const auto& wave : found->second.waves)
        {
            if (wave.live)
                waveOwners_[wave.slot].reset();
        }
        workgroups_.erase(found);
        return true;
    }

    CuResourceLimits limits_;
    std::unordered_map<std::uint64_t, Workgroup> workgroups_;
    std::vector<std::optional<WaveOwner>> waveOwners_;
    std::uint32_t nextIssueSlot_ = 0U;
};

} // namespace cgx1::compute
