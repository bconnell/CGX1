// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <limits>
#include <list>
#include <optional>
#include <stdexcept>
#include <unordered_map>
#include <utility>
#include <vector>

namespace cgx1::memory
{
inline constexpr std::uint32_t kWaveLaneCount = 32U;
inline constexpr std::uint32_t kDwordBytes = 4U;

enum class AllocationStatus : std::uint8_t
{
    Allocated = 0,
    DuplicateWorkgroupId,
    ExceedsCapacity,
    CapacityUnavailable,
    CapacityFragmented,
    WorkgroupContextsFull
};

enum class AccessKind : std::uint8_t
{
    Load = 0,
    Store
};

enum class SubmitStatus : std::uint8_t
{
    Accepted = 0,
    WaveBusy,
    DuplicateTransactionTag,
    InvalidAccessKind,
    WaveNotIssuable
};

enum class MemoryFault : std::uint8_t
{
    None = 0,
    UnknownWorkgroup,
    MisalignedAddress,
    OutOfBounds
};

struct MemoryRegion
{
    std::uint32_t baseByteAddress = 0U;
    std::uint32_t byteCount = 0U;
};

struct MemoryRequest
{
    std::uint64_t workgroupId = 0U;
    std::uint32_t waveId = 0U;
    std::uint64_t transactionTag = 0U;
    AccessKind access = AccessKind::Load;
    std::uint32_t activeLaneMask = 0U;
    std::array<std::uint32_t, kWaveLaneCount> byteAddresses{};
    std::array<std::uint32_t, kWaveLaneCount> storeData{};
};

struct SubmitResult
{
    SubmitStatus status = SubmitStatus::Accepted;
    MemoryFault fault = MemoryFault::None;
    std::optional<std::uint32_t> faultLane;
};

struct MemoryResponse
{
    std::uint64_t workgroupId = 0U;
    std::uint32_t waveId = 0U;
    std::uint64_t transactionTag = 0U;
    AccessKind access = AccessKind::Load;
    std::uint32_t activeLaneMask = 0U;
    std::array<std::uint32_t, kWaveLaneCount> laneData{};
    MemoryFault fault = MemoryFault::None;
    std::optional<std::uint32_t> faultLane;
};

// Executable reference for a finite CU-local, workgroup-scoped dword memory.
// Bank count and service timing are model parameters, not frozen architecture.
class CuSharedLocalMemory
{
public:
    CuSharedLocalMemory(
        std::size_t capacityBytes,
        std::uint32_t bankCount = kWaveLaneCount,
        std::uint32_t workgroupContextCount = 8U)
        : storage_(capacityBytes, 0U),
          bankCount_(bankCount),
          workgroupContextCount_(workgroupContextCount),
          lastServedSequenceByBank_(bankCount, 0U)
    {
        if (capacityBytes == 0U
            || capacityBytes > std::numeric_limits<std::uint32_t>::max()
            || bankCount == 0U
            || workgroupContextCount == 0U)
        {
            throw std::invalid_argument(
                "shared-memory capacity, bank count, and context count must be valid");
        }
    }

    [[nodiscard]] AllocationStatus AllocateWorkgroup(
        std::uint64_t workgroupId,
        std::uint32_t byteCount)
    {
        if (regions_.contains(workgroupId))
            return AllocationStatus::DuplicateWorkgroupId;
        if (byteCount > storage_.size())
            return AllocationStatus::ExceedsCapacity;
        if (regions_.size() >= workgroupContextCount_)
            return AllocationStatus::WorkgroupContextsFull;
        if (static_cast<std::uint64_t>(allocatedBytes_) + byteCount > storage_.size())
            return AllocationStatus::CapacityUnavailable;

        const auto base = FindAlignedRange(byteCount);
        if (!base)
            return AllocationStatus::CapacityFragmented;

        const auto [iterator, inserted] = regions_.emplace(
            workgroupId,
            MemoryRegion{*base, byteCount});
        (void)iterator;
        if (!inserted)
            return AllocationStatus::DuplicateWorkgroupId;
        allocatedBytes_ += byteCount;
        std::fill_n(storage_.begin() + *base, byteCount, std::uint8_t{0});
        return AllocationStatus::Allocated;
    }

    [[nodiscard]] bool ReleaseWorkgroup(std::uint64_t workgroupId)
    {
        const auto region = regions_.find(workgroupId);
        if (region == regions_.end() || HasOutstandingWorkgroupOperation(workgroupId))
            return false;

        std::fill_n(
            storage_.begin() + region->second.baseByteAddress,
            region->second.byteCount,
            0U);
        allocatedBytes_ -= region->second.byteCount;
        regions_.erase(region);
        return true;
    }

    [[nodiscard]] std::optional<MemoryRegion> AllocationForWorkgroup(
        std::uint64_t workgroupId) const
    {
        const auto region = regions_.find(workgroupId);
        if (region == regions_.end())
            return std::nullopt;
        return region->second;
    }

    [[nodiscard]] std::uint32_t AllocatedBytes() const noexcept
    {
        return allocatedBytes_;
    }

    [[nodiscard]] std::uint32_t PendingRequestCount() const noexcept
    {
        return static_cast<std::uint32_t>(requests_.size());
    }

    [[nodiscard]] bool IsWaveWaiting(
        std::uint64_t workgroupId,
        std::uint32_t waveId) const
    {
        return operationByWave_.contains(WaveKey{workgroupId, waveId});
    }

    [[nodiscard]] SubmitResult Submit(const MemoryRequest& request)
    {
        const auto region = regions_.find(request.workgroupId);
        const WaveKey waveKey{request.workgroupId, request.waveId};
        if (operationByWave_.contains(waveKey))
            return {SubmitStatus::WaveBusy, MemoryFault::None, std::nullopt};
        if (operationByTag_.contains(request.transactionTag))
            return {SubmitStatus::DuplicateTransactionTag, MemoryFault::None, std::nullopt};
        if (request.access != AccessKind::Load && request.access != AccessKind::Store)
            return {SubmitStatus::InvalidAccessKind, MemoryFault::None, std::nullopt};

        auto fault = region == regions_.end()
            ? MemoryFault::UnknownWorkgroup : MemoryFault::None;
        std::optional<std::uint32_t> faultLane;

        for (std::uint32_t lane = 0U;
            region != regions_.end() && fault == MemoryFault::None
                && lane < kWaveLaneCount;
            ++lane)
        {
            if ((request.activeLaneMask & (std::uint32_t{1} << lane)) == 0U)
                continue;
            const auto address = request.byteAddresses[lane];
            if ((address % kDwordBytes) != 0U)
            {
                fault = MemoryFault::MisalignedAddress;
                faultLane = lane;
            }
            if (static_cast<std::uint64_t>(address) + kDwordBytes
                > region->second.byteCount && fault == MemoryFault::None)
            {
                fault = MemoryFault::OutOfBounds;
                faultLane = lane;
            }
        }

        operationByWave_.emplace(waveKey, request.transactionTag);
        operationByTag_.emplace(request.transactionTag, waveKey);
        if (fault != MemoryFault::None)
        {
            responses_.push_back(MemoryResponse{
                request.workgroupId,
                request.waveId,
                request.transactionTag,
                request.access,
                request.activeLaneMask,
                {},
                fault,
                faultLane});
            return {SubmitStatus::Accepted, fault, faultLane};
        }

        PendingRequest pending;
        pending.request = request;
        pending.sequence = nextRequestSequence_++;
        pending.remainingLaneMask = request.activeLaneMask;
        requests_.push_back(std::move(pending));

        if (request.activeLaneMask == 0U)
            FinalizeReadyRequests();
        return {SubmitStatus::Accepted, MemoryFault::None, std::nullopt};
    }

    // Services at most one lane per physical bank in one cycle.
    [[nodiscard]] std::uint32_t ServiceCycle()
    {
        std::uint32_t servicedLaneCount = 0U;
        for (std::uint32_t bank = 0U; bank < bankCount_; ++bank)
        {
            auto selected = requests_.end();
            std::uint32_t selectedLane = 0U;
            std::uint64_t sequenceAfterLast = std::numeric_limits<std::uint64_t>::max();
            std::uint64_t sequenceBeforeLast = std::numeric_limits<std::uint64_t>::max();
            auto laneAfterLast = 0U;
            auto laneBeforeLast = 0U;

            for (auto iterator = requests_.begin(); iterator != requests_.end(); ++iterator)
            {
                const auto region = regions_.find(iterator->request.workgroupId);
                if (region == regions_.end())
                    continue;
                for (std::uint32_t lane = 0U; lane < kWaveLaneCount; ++lane)
                {
                    if ((iterator->remainingLaneMask & (std::uint32_t{1} << lane)) == 0U)
                        continue;
                    const auto physicalAddress = static_cast<std::uint64_t>(
                        region->second.baseByteAddress)
                        + iterator->request.byteAddresses[lane];
                    const auto laneBank = static_cast<std::uint32_t>(
                        (physicalAddress / kDwordBytes) % bankCount_);
                    if (laneBank != bank)
                        continue;

                    if (iterator->sequence > lastServedSequenceByBank_[bank]
                        && iterator->sequence < sequenceAfterLast)
                    {
                        selected = iterator;
                        selectedLane = lane;
                        sequenceAfterLast = iterator->sequence;
                        laneAfterLast = lane;
                    }
                    if (iterator->sequence < sequenceBeforeLast)
                    {
                        sequenceBeforeLast = iterator->sequence;
                        laneBeforeLast = lane;
                    }
                }
            }

            if (selected == requests_.end())
            {
                if (sequenceBeforeLast == std::numeric_limits<std::uint64_t>::max())
                    continue;
                for (auto iterator = requests_.begin(); iterator != requests_.end(); ++iterator)
                {
                    if (iterator->sequence == sequenceBeforeLast)
                    {
                        selected = iterator;
                        selectedLane = laneBeforeLast;
                        break;
                    }
                }
            }
            else
            {
                selectedLane = laneAfterLast;
            }

            if (selected == requests_.end())
                continue;
            ServiceLane(*selected, selectedLane);
            lastServedSequenceByBank_[bank] = selected->sequence;
            ++servicedLaneCount;
        }

        FinalizeReadyRequests();
        return servicedLaneCount;
    }

    [[nodiscard]] std::optional<MemoryResponse> TakeResponse()
    {
        if (responses_.empty())
            return std::nullopt;

        auto response = responses_.front();
        responses_.pop_front();
        ForgetOperation(response.workgroupId, response.waveId, response.transactionTag);
        return response;
    }

    // A terminal wave stops receiving a response, but accepted memory service drains.
    [[nodiscard]] bool CancelWave(std::uint64_t workgroupId, std::uint32_t waveId)
    {
        const WaveKey key{workgroupId, waveId};
        const auto operation = operationByWave_.find(key);
        if (operation == operationByWave_.end())
            return false;

        const auto request = std::find_if(
            requests_.begin(),
            requests_.end(),
            [&](const PendingRequest& item)
            {
                return item.request.workgroupId == workgroupId
                    && item.request.waveId == waveId
                    && item.request.transactionTag == operation->second;
            });
        if (request != requests_.end())
        {
            request->suppressResponse = true;
            return true;
        }

        const auto response = std::find_if(
            responses_.begin(),
            responses_.end(),
            [&](const MemoryResponse& item)
            {
                return item.workgroupId == workgroupId
                    && item.waveId == waveId
                    && item.transactionTag == operation->second;
            });
        if (response == responses_.end())
            return false;
        const auto tag = response->transactionTag;
        responses_.erase(response);
        ForgetOperation(workgroupId, waveId, tag);
        return true;
    }

    void Reset()
    {
        std::fill(storage_.begin(), storage_.end(), 0U);
        regions_.clear();
        requests_.clear();
        responses_.clear();
        operationByWave_.clear();
        operationByTag_.clear();
        std::fill(lastServedSequenceByBank_.begin(), lastServedSequenceByBank_.end(), 0U);
        allocatedBytes_ = 0U;
        nextRequestSequence_ = 1U;
    }

private:
    struct WaveKey
    {
        std::uint64_t workgroupId;
        std::uint32_t waveId;

        friend bool operator==(const WaveKey&, const WaveKey&) = default;
    };

    struct WaveKeyHash
    {
        [[nodiscard]] std::size_t operator()(const WaveKey& key) const noexcept
        {
            const auto groupHash = std::hash<std::uint64_t>{}(key.workgroupId);
            const auto waveHash = std::hash<std::uint32_t>{}(key.waveId);
            return groupHash ^ (waveHash + 0x9e3779b9U + (groupHash << 6U)
                + (groupHash >> 2U));
        }
    };

    struct PendingRequest
    {
        MemoryRequest request;
        std::uint64_t sequence = 0U;
        std::uint32_t remainingLaneMask = 0U;
        std::array<std::uint32_t, kWaveLaneCount> laneData{};
        bool suppressResponse = false;
    };

    [[nodiscard]] std::optional<std::uint32_t> FindAlignedRange(
        std::uint32_t byteCount) const
    {
        std::vector<std::pair<std::uint32_t, std::uint32_t>> ordered;
        ordered.reserve(regions_.size());
        for (const auto& [id, region] : regions_)
        {
            (void)id;
            ordered.emplace_back(region.baseByteAddress, region.byteCount);
        }
        std::sort(ordered.begin(), ordered.end());

        std::uint64_t candidate = 0U;
        for (const auto& [base, size] : ordered)
        {
            candidate = (candidate + (kDwordBytes - 1U))
                & ~static_cast<std::uint64_t>(kDwordBytes - 1U);
            if (candidate + byteCount <= base)
                return static_cast<std::uint32_t>(candidate);
            candidate = std::max<std::uint64_t>(candidate, std::uint64_t{base} + size);
        }
        candidate = (candidate + (kDwordBytes - 1U))
            & ~static_cast<std::uint64_t>(kDwordBytes - 1U);
        if (candidate + byteCount <= storage_.size())
            return static_cast<std::uint32_t>(candidate);
        return std::nullopt;
    }

    [[nodiscard]] bool HasOutstandingWorkgroupOperation(std::uint64_t workgroupId) const
    {
        return std::any_of(
            operationByWave_.begin(),
            operationByWave_.end(),
            [&](const auto& item) { return item.first.workgroupId == workgroupId; });
    }

    void ServiceLane(PendingRequest& pending, std::uint32_t lane)
    {
        const auto region = regions_.find(pending.request.workgroupId);
        if (region == regions_.end())
            throw std::logic_error("pending request lost its workgroup allocation");
        const auto address = static_cast<std::size_t>(region->second.baseByteAddress)
            + pending.request.byteAddresses[lane];
        if (pending.request.access == AccessKind::Store)
        {
            const auto value = pending.request.storeData[lane];
            for (std::uint32_t byte = 0U; byte < kDwordBytes; ++byte)
            {
                storage_[address + byte] = static_cast<std::uint8_t>(
                    (value >> (byte * 8U)) & 0xffU);
            }
        }
        else
        {
            std::uint32_t value = 0U;
            for (std::uint32_t byte = 0U; byte < kDwordBytes; ++byte)
                value |= std::uint32_t{storage_[address + byte]} << (byte * 8U);
            pending.laneData[lane] = value;
        }
        pending.remainingLaneMask &= ~(std::uint32_t{1} << lane);
    }

    void FinalizeReadyRequests()
    {
        for (auto iterator = requests_.begin(); iterator != requests_.end();)
        {
            if (iterator->remainingLaneMask != 0U)
            {
                ++iterator;
                continue;
            }
            if (!iterator->suppressResponse)
            {
                responses_.push_back(MemoryResponse{
                    iterator->request.workgroupId,
                    iterator->request.waveId,
                    iterator->request.transactionTag,
                    iterator->request.access,
                    iterator->request.activeLaneMask,
                    iterator->laneData,
                    MemoryFault::None,
                    std::nullopt});
            }
            else
            {
                ForgetOperation(
                    iterator->request.workgroupId,
                    iterator->request.waveId,
                    iterator->request.transactionTag);
            }
            iterator = requests_.erase(iterator);
        }
    }

    void ForgetOperation(
        std::uint64_t workgroupId,
        std::uint32_t waveId,
        std::uint64_t transactionTag)
    {
        const WaveKey key{workgroupId, waveId};
        const auto wave = operationByWave_.find(key);
        if (wave != operationByWave_.end() && wave->second == transactionTag)
            operationByWave_.erase(wave);
        const auto tag = operationByTag_.find(transactionTag);
        if (tag != operationByTag_.end() && tag->second == key)
            operationByTag_.erase(tag);
    }

    std::vector<std::uint8_t> storage_;
    const std::uint32_t bankCount_;
    const std::uint32_t workgroupContextCount_;
    std::unordered_map<std::uint64_t, MemoryRegion> regions_;
    std::list<PendingRequest> requests_;
    std::deque<MemoryResponse> responses_;
    std::unordered_map<WaveKey, std::uint64_t, WaveKeyHash> operationByWave_;
    std::unordered_map<std::uint64_t, WaveKey> operationByTag_;
    std::vector<std::uint64_t> lastServedSequenceByBank_;
    std::uint32_t allocatedBytes_ = 0U;
    std::uint64_t nextRequestSequence_ = 1U;
};
} // namespace cgx1::memory
