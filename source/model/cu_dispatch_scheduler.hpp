// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "workgroup_scheduler.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <limits>
#include <map>
#include <optional>
#include <stdexcept>
#include <tuple>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace cgx1::compute {

inline constexpr std::uint32_t kHardwareQueueContextCount = 64U;
inline constexpr std::uint8_t kSchedulerPriorityLevelCount = 8U;

enum class DispatchEngineClass : std::uint8_t
{
    Compute = 0U,
    Graphics
};

struct DispatchQueueContext
{
    std::uint8_t contextId;
    std::uint64_t processId;
    std::uint64_t addressSpaceId;
    std::uint8_t priority;
    DispatchEngineClass engineClass;
    bool faulted;
};

struct DispatchPolicy
{
    // A CU instance tracks only the contexts assigned to it by the global manager.
    std::uint32_t maximumQueueContexts = kHardwareQueueContextCount;
    std::uint32_t pendingWorkgroupsPerContext = 8U;
    std::uint32_t agingIntervalCycles = 64U;
    std::array<std::uint16_t, kSchedulerPriorityLevelCount> priorityWeights{
        1U, 2U, 4U, 8U, 16U, 32U, 64U, 128U};
};

enum class QueueRegistrationStatus : std::uint8_t
{
    Registered = 0U,
    Unregistered,
    InvalidContextId,
    InvalidPriority,
    UnsupportedEngine,
    DuplicateContextId,
    ContextCapacityReached,
    UnknownContext,
    ContextBusy
};

enum class EnqueueWorkgroupStatus : std::uint8_t
{
    Queued = 0U,
    UnknownQueueContext,
    QueueFaulted,
    QueueFull,
    DuplicateWorkgroupId
};

enum class DispatchCycleStatus : std::uint8_t
{
    Idle = 0U,
    TileIneligible,
    Deferred,
    Admitted,
    Rejected,
    QueueFaulted
};

struct DispatchCycleResult
{
    DispatchCycleStatus status = DispatchCycleStatus::Idle;
    std::uint8_t queueContextId = 0U;
    std::uint64_t workgroupId = 0U;
    AdmissionFailure failure = AdmissionFailure::None;
};

struct RetiredDispatchWorkgroup
{
    std::uint8_t queueContextId;
    std::uint64_t workgroupId;
};

struct CancelledDispatchWorkgroup
{
    std::uint8_t queueContextId;
    std::uint64_t workgroupId;
    bool wasResident;
};

class ComputeUnitDispatchScheduler
{
public:
    ComputeUnitDispatchScheduler(CuResourceLimits limits, DispatchPolicy policy = {})
        : workgroups_(limits), policy_(policy)
    {
        if (policy_.maximumQueueContexts == 0U
            || policy_.maximumQueueContexts > kHardwareQueueContextCount
            || policy_.pendingWorkgroupsPerContext == 0U
            || policy_.pendingWorkgroupsPerContext
                > std::numeric_limits<std::uint32_t>::max()
                    / policy_.maximumQueueContexts
            || policy_.agingIntervalCycles == 0U
            || std::any_of(policy_.priorityWeights.begin(), policy_.priorityWeights.end(),
                [](std::uint16_t weight) { return weight == 0U; }))
        {
            throw std::invalid_argument("invalid CU dispatch scheduler policy");
        }
    }

    [[nodiscard]] QueueRegistrationStatus RegisterQueueContext(
        const DispatchQueueContext& context)
    {
        if (context.contextId >= kHardwareQueueContextCount)
            return QueueRegistrationStatus::InvalidContextId;
        if (context.priority >= kSchedulerPriorityLevelCount)
            return QueueRegistrationStatus::InvalidPriority;
        if (context.engineClass != DispatchEngineClass::Compute)
            return QueueRegistrationStatus::UnsupportedEngine;
        if (queues_.contains(context.contextId))
            return QueueRegistrationStatus::DuplicateContextId;
        if (queues_.size() >= policy_.maximumQueueContexts)
            return QueueRegistrationStatus::ContextCapacityReached;

        queues_.emplace(context.contextId, QueueState{context});
        return QueueRegistrationStatus::Registered;
    }

    [[nodiscard]] QueueRegistrationStatus UnregisterQueueContext(
        std::uint8_t contextId)
    {
        const auto found = queues_.find(contextId);
        if (found == queues_.end())
            return QueueRegistrationStatus::UnknownContext;
        if (!found->second.pending.empty()
            || std::any_of(activeQueueByWorkgroup_.begin(), activeQueueByWorkgroup_.end(),
                [contextId](const auto& active)
                {
                    return active.second == contextId;
                }))
        {
            return QueueRegistrationStatus::ContextBusy;
        }
        queues_.erase(found);
        return QueueRegistrationStatus::Unregistered;
    }

    [[nodiscard]] bool SetQueueFaulted(std::uint8_t contextId, bool faulted)
    {
        const auto found = queues_.find(contextId);
        if (found == queues_.end())
            return false;
        found->second.context.faulted = faulted;
        return true;
    }

    [[nodiscard]] EnqueueWorkgroupStatus EnqueueWorkgroup(
        std::uint8_t contextId,
        const WorkgroupDemand& demand)
    {
        const auto found = queues_.find(contextId);
        if (found == queues_.end())
            return EnqueueWorkgroupStatus::UnknownQueueContext;
        if (found->second.context.faulted)
            return EnqueueWorkgroupStatus::QueueFaulted;
        if (found->second.pending.size() >= policy_.pendingWorkgroupsPerContext)
            return EnqueueWorkgroupStatus::QueueFull;
        if (pendingWorkgroupIds_.contains(demand.id)
            || activeQueueByWorkgroup_.contains(demand.id))
        {
            return EnqueueWorkgroupStatus::DuplicateWorkgroupId;
        }

        auto& queue = found->second;
        if (queue.pending.empty())
        {
            queue.waitingCycles = 0U;
            queue.currentCredit = 0;
        }
        queue.pending.push_back(demand);
        pendingWorkgroupIds_.insert(demand.id);
        return EnqueueWorkgroupStatus::Queued;
    }

    [[nodiscard]] DispatchCycleResult ScheduleOneCycle(bool tileEligible)
    {
        if (!tileEligible)
            return {DispatchCycleStatus::TileIneligible, 0U, 0U, AdmissionFailure::None};

        if (std::none_of(queues_.begin(), queues_.end(),
                [](const auto& entry) { return !entry.second.pending.empty(); }))
        {
            return {};
        }

        std::uint64_t totalWeight = 0U;
        for (auto& [id, queue] : queues_)
        {
            (void)id;
            if (queue.pending.empty())
            {
                queue.currentCredit = 0;
                continue;
            }
            if (queue.waitingCycles != std::numeric_limits<std::uint64_t>::max())
                ++queue.waitingCycles;
            const auto effectivePriority = EffectivePriority(queue);
            const std::int64_t weight = policy_.priorityWeights[effectivePriority];
            queue.currentCredit = SaturatingAdd(queue.currentCredit, weight);
            totalWeight += static_cast<std::uint64_t>(weight);
        }

        auto selected = queues_.end();
        std::uint32_t selectedDistance = kHardwareQueueContextCount;
        for (auto iterator = queues_.begin(); iterator != queues_.end(); ++iterator)
        {
            if (iterator->second.pending.empty())
                continue;
            const std::uint32_t distance =
                (static_cast<std::uint32_t>(iterator->first)
                    + kHardwareQueueContextCount - roundRobinCursor_)
                % kHardwareQueueContextCount;
            if (selected == queues_.end()
                || iterator->second.currentCredit > selected->second.currentCredit
                || (iterator->second.currentCredit == selected->second.currentCredit
                    && distance < selectedDistance))
            {
                selected = iterator;
                selectedDistance = distance;
            }
        }

        if (selected == queues_.end())
            return {};

        auto& queue = selected->second;
        queue.currentCredit = SaturatingAdd(
            queue.currentCredit, -static_cast<std::int64_t>(totalWeight));
        roundRobinCursor_ = static_cast<std::uint8_t>(
            (static_cast<std::uint32_t>(selected->first) + 1U)
                % kHardwareQueueContextCount);

        const auto demand = queue.pending.front();
        if (queue.context.faulted)
        {
            ConsumeHead(queue);
            return {DispatchCycleStatus::QueueFaulted,
                selected->first, demand.id, AdmissionFailure::None};
        }

        const auto failure = workgroups_.Admit(demand);
        if (failure == AdmissionFailure::None)
        {
            ConsumeHead(queue);
            activeQueueByWorkgroup_.emplace(demand.id, selected->first);
            return {DispatchCycleStatus::Admitted,
                selected->first, demand.id, AdmissionFailure::None};
        }
        if (IsRetryable(failure))
        {
            return {DispatchCycleStatus::Deferred,
                selected->first, demand.id, failure};
        }

        ConsumeHead(queue);
        return {DispatchCycleStatus::Rejected,
            selected->first, demand.id, failure};
    }

    [[nodiscard]] std::vector<RetiredDispatchWorkgroup> CollectRetiredWorkgroups()
    {
        const auto residentIds = workgroups_.ActiveWorkgroupIds();
        const std::unordered_set<std::uint64_t> residentSet(
            residentIds.begin(), residentIds.end());
        std::vector<RetiredDispatchWorkgroup> retired;
        for (auto iterator = activeQueueByWorkgroup_.begin();
            iterator != activeQueueByWorkgroup_.end();)
        {
            if (residentSet.contains(iterator->first))
            {
                ++iterator;
                continue;
            }
            retired.push_back({iterator->second, iterator->first});
            iterator = activeQueueByWorkgroup_.erase(iterator);
        }
        std::sort(retired.begin(), retired.end(),
            [](const auto& left, const auto& right)
            {
                return left.workgroupId < right.workgroupId;
            });
        return retired;
    }

    [[nodiscard]] std::vector<CancelledDispatchWorkgroup> Reset()
    {
        std::vector<CancelledDispatchWorkgroup> cancelled;
        for (auto& [contextId, queue] : queues_)
        {
            for (const auto& demand : queue.pending)
                cancelled.push_back({contextId, demand.id, false});
            queue.pending.clear();
            queue.waitingCycles = 0U;
            queue.currentCredit = 0;
        }
        for (const auto& [workgroupId, contextId] : activeQueueByWorkgroup_)
            cancelled.push_back({contextId, workgroupId, true});
        std::sort(cancelled.begin(), cancelled.end(),
            [](const auto& left, const auto& right)
            {
                return std::tie(left.wasResident, left.queueContextId, left.workgroupId)
                    < std::tie(right.wasResident, right.queueContextId, right.workgroupId);
            });
        workgroups_.Reset();
        pendingWorkgroupIds_.clear();
        activeQueueByWorkgroup_.clear();
        roundRobinCursor_ = 0U;
        return cancelled;
    }

    [[nodiscard]] std::uint32_t PendingWorkgroupCount() const noexcept
    {
        std::uint32_t count = 0U;
        for (const auto& [id, queue] : queues_)
        {
            (void)id;
            count += static_cast<std::uint32_t>(queue.pending.size());
        }
        return count;
    }

    [[nodiscard]] std::uint32_t PendingWorkgroupCount(
        std::uint8_t contextId) const noexcept
    {
        const auto found = queues_.find(contextId);
        return found == queues_.end()
            ? 0U
            : static_cast<std::uint32_t>(found->second.pending.size());
    }

    [[nodiscard]] const DispatchQueueContext* QueueContext(
        std::uint8_t contextId) const noexcept
    {
        const auto found = queues_.find(contextId);
        return found == queues_.end() ? nullptr : &found->second.context;
    }

    [[nodiscard]] ComputeUnitWorkgroupScheduler& Workgroups() noexcept
    {
        return workgroups_;
    }

    [[nodiscard]] const ComputeUnitWorkgroupScheduler& Workgroups() const noexcept
    {
        return workgroups_;
    }

    [[nodiscard]] bool CheckInvariants() const
    {
        if (!workgroups_.CheckInvariants())
            return false;

        std::unordered_set<std::uint64_t> observedPendingIds;
        std::uint32_t pendingCount = 0U;
        for (const auto& [contextId, queue] : queues_)
        {
            if (contextId >= kHardwareQueueContextCount
                || queue.context.contextId != contextId
                || queue.context.priority >= kSchedulerPriorityLevelCount
                || queue.context.engineClass != DispatchEngineClass::Compute
                || queue.pending.size() > policy_.pendingWorkgroupsPerContext)
            {
                return false;
            }
            pendingCount += static_cast<std::uint32_t>(queue.pending.size());
            for (const auto& demand : queue.pending)
            {
                if (!observedPendingIds.insert(demand.id).second)
                    return false;
            }
        }
        if (pendingCount != pendingWorkgroupIds_.size()
            || observedPendingIds.size() != pendingWorkgroupIds_.size())
        {
            return false;
        }
        for (const auto workgroupId : pendingWorkgroupIds_)
        {
            if (!observedPendingIds.contains(workgroupId)
                || activeQueueByWorkgroup_.contains(workgroupId))
            {
                return false;
            }
        }

        const auto residentIds = workgroups_.ActiveWorkgroupIds();
        for (const auto workgroupId : residentIds)
        {
            const auto active = activeQueueByWorkgroup_.find(workgroupId);
            if (active == activeQueueByWorkgroup_.end()
                || !queues_.contains(active->second))
            {
                return false;
            }
        }
        for (const auto& [workgroupId, contextId] : activeQueueByWorkgroup_)
        {
            if (!queues_.contains(contextId) || pendingWorkgroupIds_.contains(workgroupId))
                return false;
        }
        return true;
    }

private:
    struct QueueState
    {
        explicit QueueState(const DispatchQueueContext& contextValue)
            : context(contextValue)
        {
        }

        DispatchQueueContext context;
        std::deque<WorkgroupDemand> pending;
        std::uint64_t waitingCycles = 0U;
        std::int64_t currentCredit = 0;
    };

    [[nodiscard]] std::uint8_t EffectivePriority(const QueueState& queue) const noexcept
    {
        const std::uint64_t promotions =
            queue.waitingCycles / policy_.agingIntervalCycles;
        const std::uint64_t priority =
            static_cast<std::uint64_t>(queue.context.priority) + promotions;
        return static_cast<std::uint8_t>(std::min<std::uint64_t>(
            priority, kSchedulerPriorityLevelCount - 1U));
    }

    [[nodiscard]] static std::int64_t SaturatingAdd(
        std::int64_t value,
        std::int64_t delta) noexcept
    {
        if (delta > 0 && value > std::numeric_limits<std::int64_t>::max() - delta)
            return std::numeric_limits<std::int64_t>::max();
        if (delta < 0 && value < std::numeric_limits<std::int64_t>::min() - delta)
            return std::numeric_limits<std::int64_t>::min();
        return value + delta;
    }

    [[nodiscard]] static bool IsRetryable(AdmissionFailure failure) noexcept
    {
        switch (failure)
        {
        case AdmissionFailure::BarrierContextsUnavailable:
        case AdmissionFailure::ResidentWaveSlotsUnavailable:
        case AdmissionFailure::VgprCapacityUnavailable:
        case AdmissionFailure::VgprCapacityFragmented:
        case AdmissionFailure::ScalarPredicateStateUnavailable:
        case AdmissionFailure::SharedLocalMemoryUnavailable:
        case AdmissionFailure::OtherWorkgroupStateUnavailable:
        case AdmissionFailure::SharedLocalMemoryFragmented:
            return true;
        default:
            return false;
        }
    }

    void ConsumeHead(QueueState& queue)
    {
        pendingWorkgroupIds_.erase(queue.pending.front().id);
        queue.pending.pop_front();
        queue.waitingCycles = 0U;
        if (queue.pending.empty())
            queue.currentCredit = 0;
    }

    ComputeUnitWorkgroupScheduler workgroups_;
    DispatchPolicy policy_;
    std::map<std::uint8_t, QueueState> queues_;
    std::unordered_set<std::uint64_t> pendingWorkgroupIds_;
    std::unordered_map<std::uint64_t, std::uint8_t> activeQueueByWorkgroup_;
    std::uint8_t roundRobinCursor_ = 0U;
};

} // namespace cgx1::compute
