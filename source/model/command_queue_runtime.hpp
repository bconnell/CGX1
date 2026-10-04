// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "cu_dispatch_scheduler.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <limits>
#include <map>
#include <optional>
#include <span>
#include <stdexcept>
#include <utility>
#include <vector>

namespace cgx1::compute {

inline constexpr std::uint32_t kCommandPacketHeaderBytes = 12U;
inline constexpr std::uint32_t kWorkgroupDispatchPacketFixedBytes = 44U;
inline constexpr std::uint32_t kMaximumCommandRingBytesPerContext = 65536U;
inline constexpr std::uint32_t kMaximumCommandRingStorageBytes = 4U * 1024U * 1024U;
inline constexpr std::uint32_t kMaximumTrackedCommandWorkgroups = 1024U;
inline constexpr std::uint32_t kCommandPacketMagic = 0x31584743U;
inline constexpr std::uint16_t kWorkgroupDispatchPacketOpcode = 1U;
inline constexpr std::uint8_t kWorkgroupDispatchPacketVersion = 1U;
inline constexpr std::uint32_t kMinimumWorkgroupDispatchPacketBytes =
    kWorkgroupDispatchPacketFixedBytes + 8U;

struct CommandWaveDescriptor
{
    std::uint32_t activeLaneMask = 0U;
    std::uint16_t vgprRegisterCount = 0U;
};

struct WorkgroupDispatchDescriptor
{
    std::uint64_t submissionId = 0U;
    std::uint64_t entryPc = 0U;
    std::uint16_t scalarPredicateUnitsPerWave = 0U;
    std::uint32_t sharedLocalBytes = 0U;
    std::uint32_t otherWorkgroupStateUnits = 0U;
    std::vector<CommandWaveDescriptor> waves;
};

enum class PacketDecodeStatus : std::uint8_t
{
    Decoded = 0U,
    Incomplete,
    Unsupported,
    MalformedEnvelope,
    MalformedPayload
};

struct PacketDecodeResult
{
    PacketDecodeStatus status = PacketDecodeStatus::Incomplete;
    std::uint32_t packetBytes = 0U;
    std::optional<std::uint64_t> submissionId;
    std::optional<WorkgroupDispatchDescriptor> workgroup;
};

namespace command_packet_detail {

inline std::uint16_t Read16(std::span<const std::uint8_t> bytes, std::size_t offset)
{
    return static_cast<std::uint16_t>(bytes[offset])
        | static_cast<std::uint16_t>(static_cast<std::uint16_t>(bytes[offset + 1U]) << 8U);
}

inline std::uint32_t Read32(std::span<const std::uint8_t> bytes, std::size_t offset)
{
    return static_cast<std::uint32_t>(bytes[offset])
        | (static_cast<std::uint32_t>(bytes[offset + 1U]) << 8U)
        | (static_cast<std::uint32_t>(bytes[offset + 2U]) << 16U)
        | (static_cast<std::uint32_t>(bytes[offset + 3U]) << 24U);
}

inline std::uint64_t Read64(std::span<const std::uint8_t> bytes, std::size_t offset)
{
    return static_cast<std::uint64_t>(Read32(bytes, offset))
        | (static_cast<std::uint64_t>(Read32(bytes, offset + 4U)) << 32U);
}

inline void Write16(std::vector<std::uint8_t>& bytes, std::size_t offset, std::uint16_t value)
{
    bytes[offset] = static_cast<std::uint8_t>(value & 0xffU);
    bytes[offset + 1U] = static_cast<std::uint8_t>((value >> 8U) & 0xffU);
}

inline void Write32(std::vector<std::uint8_t>& bytes, std::size_t offset, std::uint32_t value)
{
    for (std::size_t byte = 0U; byte < 4U; ++byte)
        bytes[offset + byte] = static_cast<std::uint8_t>((value >> (byte * 8U)) & 0xffU);
}

inline void Write64(std::vector<std::uint8_t>& bytes, std::size_t offset, std::uint64_t value)
{
    Write32(bytes, offset, static_cast<std::uint32_t>(value & 0xffffffffULL));
    Write32(bytes, offset + 4U, static_cast<std::uint32_t>(value >> 32U));
}

inline bool IsValidDescriptor(const WorkgroupDispatchDescriptor& descriptor)
{
    if (descriptor.waves.empty()
        || descriptor.waves.size() > std::numeric_limits<std::uint16_t>::max()
        || descriptor.waves.size()
            > (std::numeric_limits<std::uint32_t>::max()
                - kWorkgroupDispatchPacketFixedBytes) / 8U
        || descriptor.entryPc >= (1ULL << 57U)
        || (descriptor.entryPc & 0x3U) != 0U)
    {
        return false;
    }
    return std::all_of(descriptor.waves.begin(), descriptor.waves.end(),
        [](const CommandWaveDescriptor& wave)
        {
            return wave.activeLaneMask != 0U
                && wave.vgprRegisterCount != 0U
                && wave.vgprRegisterCount <= kMaximumArchitecturalVgprsPerWave;
        });
}

} // namespace command_packet_detail

[[nodiscard]] inline std::vector<std::uint8_t> EncodeWorkgroupDispatchPacket(
    const WorkgroupDispatchDescriptor& descriptor)
{
    if (!command_packet_detail::IsValidDescriptor(descriptor))
        throw std::invalid_argument("invalid workgroup dispatch descriptor");

    const std::uint64_t packetSize64 = kWorkgroupDispatchPacketFixedBytes
        + static_cast<std::uint64_t>(descriptor.waves.size()) * 8U;
    if (packetSize64 > std::numeric_limits<std::uint32_t>::max())
        throw std::invalid_argument("workgroup dispatch packet is too large");
    const auto packetSize = static_cast<std::uint32_t>(packetSize64);
    std::vector<std::uint8_t> bytes(packetSize, 0U);

    command_packet_detail::Write32(bytes, 0U, kCommandPacketMagic);
    command_packet_detail::Write16(bytes, 4U, kWorkgroupDispatchPacketOpcode);
    bytes[6U] = kWorkgroupDispatchPacketVersion;
    bytes[7U] = 0U;
    command_packet_detail::Write32(bytes, 8U, packetSize);

    command_packet_detail::Write64(bytes, 12U, descriptor.submissionId);
    command_packet_detail::Write64(bytes, 20U, descriptor.entryPc);
    command_packet_detail::Write16(bytes, 28U,
        static_cast<std::uint16_t>(descriptor.waves.size()));
    command_packet_detail::Write16(bytes, 30U, descriptor.scalarPredicateUnitsPerWave);
    command_packet_detail::Write32(bytes, 32U, descriptor.sharedLocalBytes);
    command_packet_detail::Write32(bytes, 36U, descriptor.otherWorkgroupStateUnits);
    command_packet_detail::Write32(bytes, 40U, 0U);
    for (std::size_t wave = 0U; wave < descriptor.waves.size(); ++wave)
    {
        const std::size_t offset = kWorkgroupDispatchPacketFixedBytes + wave * 8U;
        command_packet_detail::Write32(bytes, offset, descriptor.waves[wave].activeLaneMask);
        command_packet_detail::Write16(bytes, offset + 4U,
            descriptor.waves[wave].vgprRegisterCount);
        command_packet_detail::Write16(bytes, offset + 6U, 0U);
    }
    return bytes;
}

[[nodiscard]] inline PacketDecodeResult DecodeWorkgroupDispatchPacket(
    std::span<const std::uint8_t> bytes,
    std::uint32_t maximumPacketBytes)
{
    if (bytes.size() < kCommandPacketHeaderBytes)
        return {};

    const std::uint32_t packetBytes = command_packet_detail::Read32(bytes, 8U);
    if (command_packet_detail::Read32(bytes, 0U) != kCommandPacketMagic
        || packetBytes < kCommandPacketHeaderBytes
        || packetBytes > maximumPacketBytes
        || (packetBytes & 0x3U) != 0U)
    {
        return {PacketDecodeStatus::MalformedEnvelope, packetBytes, std::nullopt, std::nullopt};
    }
    if (bytes.size() < packetBytes)
        return {PacketDecodeStatus::Incomplete, packetBytes, std::nullopt, std::nullopt};
    if (bytes[7U] != 0U)
    {
        const auto submissionId = packetBytes >= 20U
            ? std::optional<std::uint64_t>(command_packet_detail::Read64(bytes, 12U))
            : std::nullopt;
        return {PacketDecodeStatus::MalformedPayload, packetBytes,
            submissionId, std::nullopt};
    }

    const auto opcode = command_packet_detail::Read16(bytes, 4U);
    if (opcode != kWorkgroupDispatchPacketOpcode
        || bytes[6U] != kWorkgroupDispatchPacketVersion)
    {
        return {PacketDecodeStatus::Unsupported, packetBytes, std::nullopt, std::nullopt};
    }
    if (packetBytes < kWorkgroupDispatchPacketFixedBytes)
        return {PacketDecodeStatus::MalformedPayload, packetBytes, std::nullopt, std::nullopt};

    WorkgroupDispatchDescriptor descriptor;
    descriptor.submissionId = command_packet_detail::Read64(bytes, 12U);
    descriptor.entryPc = command_packet_detail::Read64(bytes, 20U);
    descriptor.scalarPredicateUnitsPerWave = command_packet_detail::Read16(bytes, 30U);
    descriptor.sharedLocalBytes = command_packet_detail::Read32(bytes, 32U);
    descriptor.otherWorkgroupStateUnits = command_packet_detail::Read32(bytes, 36U);
    const std::uint16_t waveCount = command_packet_detail::Read16(bytes, 28U);
    const std::uint64_t expectedBytes = kWorkgroupDispatchPacketFixedBytes
        + static_cast<std::uint64_t>(waveCount) * 8U;
    if (command_packet_detail::Read32(bytes, 40U) != 0U
        || waveCount == 0U
        || expectedBytes != packetBytes
        || descriptor.entryPc >= (1ULL << 57U)
        || (descriptor.entryPc & 0x3U) != 0U)
    {
        return {PacketDecodeStatus::MalformedPayload, packetBytes,
            descriptor.submissionId, std::nullopt};
    }

    descriptor.waves.reserve(waveCount);
    for (std::uint32_t wave = 0U; wave < waveCount; ++wave)
    {
        const std::size_t offset = kWorkgroupDispatchPacketFixedBytes
            + static_cast<std::size_t>(wave) * 8U;
        CommandWaveDescriptor waveDescriptor{
            command_packet_detail::Read32(bytes, offset),
            command_packet_detail::Read16(bytes, offset + 4U)};
        if (waveDescriptor.activeLaneMask == 0U
            || waveDescriptor.vgprRegisterCount == 0U
            || waveDescriptor.vgprRegisterCount > kMaximumArchitecturalVgprsPerWave
            || command_packet_detail::Read16(bytes, offset + 6U) != 0U)
        {
            return {PacketDecodeStatus::MalformedPayload, packetBytes,
                descriptor.submissionId, std::nullopt};
        }
        descriptor.waves.push_back(waveDescriptor);
    }
    return {PacketDecodeStatus::Decoded, packetBytes,
        descriptor.submissionId, std::move(descriptor)};
}

struct CommandProcessorPolicy
{
    std::uint32_t ringBytesPerContext = 4096U;
    std::uint32_t maximumTrackedWorkgroups = 512U;
};

enum class SubmitCommandStatus : std::uint8_t
{
    Accepted = 0U,
    UnknownQueueContext,
    QueueFaulted,
    EmptyWrite,
    PacketTooLarge,
    RingFull,
    SequenceExhausted
};

enum class CommandProcessStatus : std::uint8_t
{
    Idle = 0U,
    Incomplete,
    Backpressure,
    Enqueued,
    RejectedUnsupported,
    RejectedMalformed,
    QueueFaulted,
    UnknownQueueContext,
    InternalIdExhausted
};

enum class CommandCompletionStatus : std::uint8_t
{
    Completed = 0U,
    AdmissionRejected,
    UnsupportedCommand,
    MalformedPacket,
    QueueFaulted,
    Cancelled
};

enum class QueueResetStatus : std::uint8_t
{
    Reset = 0U,
    UnknownQueueContext
};

struct CommandProcessResult
{
    CommandProcessStatus status = CommandProcessStatus::Idle;
    std::uint8_t queueContextId = 0U;
    std::uint64_t packetBytePosition = 0U;
    std::uint32_t packetBytes = 0U;
    std::optional<std::uint64_t> submissionId;
    std::optional<std::uint64_t> internalWorkgroupId;
};

struct CommandCompletion
{
    CommandCompletionStatus status = CommandCompletionStatus::Completed;
    std::uint8_t queueContextId = 0U;
    std::optional<std::uint64_t> submissionId;
    std::uint64_t packetBytePosition = 0U;
    std::uint64_t internalWorkgroupId = 0U;
    AdmissionFailure admissionFailure = AdmissionFailure::None;
    std::uint64_t queueIncarnationId = 0U;
};

struct DispatchedWorkgroup
{
    std::uint64_t workgroupId = 0U;
    std::uint8_t queueContextId = 0U;
    std::uint64_t processId = 0U;
    std::uint64_t addressSpaceId = 0U;
    WorkgroupDispatchDescriptor descriptor;
    std::uint64_t queueIncarnationId = 0U;
};

struct CommandDispatchCycle
{
    DispatchCycleResult dispatch;
    std::optional<DispatchedWorkgroup> admitted;
};

struct CommandQueueSnapshot
{
    std::uint8_t queueContextId = 0U;
    bool faulted = false;
    std::uint32_t unreadBytes = 0U;
    std::uint32_t readPhysicalIndex = 0U;
    std::uint64_t producerBytePosition = 0U;
    std::uint64_t consumerBytePosition = 0U;
    std::uint64_t queueIncarnationId = 0U;
};

struct QueueResetResult
{
    QueueResetStatus status = QueueResetStatus::UnknownQueueContext;
    std::uint64_t droppedBeginBytePosition = 0U;
    std::uint64_t droppedEndBytePosition = 0U;
    std::vector<CommandCompletion> immediateCompletions;
};

class CommandQueueRuntime
{
public:
    explicit CommandQueueRuntime(
        ComputeUnitDispatchScheduler& dispatcher,
        CommandProcessorPolicy policy = {})
        : dispatcher_(dispatcher), policy_(policy)
    {
        const std::uint64_t totalRingBytes =
            static_cast<std::uint64_t>(policy_.ringBytesPerContext)
            * kHardwareQueueContextCount;
        if (policy_.ringBytesPerContext < kMinimumWorkgroupDispatchPacketBytes
            || policy_.ringBytesPerContext > kMaximumCommandRingBytesPerContext
            || totalRingBytes > kMaximumCommandRingStorageBytes
            || policy_.maximumTrackedWorkgroups == 0U
            || policy_.maximumTrackedWorkgroups > kMaximumTrackedCommandWorkgroups)
        {
            throw std::invalid_argument("invalid command queue runtime policy");
        }
    }

    [[nodiscard]] QueueRegistrationStatus RegisterQueueContext(
        const DispatchQueueContext& context)
    {
        if (context.contextId < kHardwareQueueContextCount
            && queues_.contains(context.contextId))
        {
            return QueueRegistrationStatus::DuplicateContextId;
        }

        if (context.contextId >= kHardwareQueueContextCount)
            return dispatcher_.RegisterQueueContext(context);
        if (!nextQueueIncarnationId_)
            return QueueRegistrationStatus::IncarnationExhausted;

        const auto queueIncarnationId = *nextQueueIncarnationId_;
        const auto [queue, inserted] = queues_.try_emplace(
            context.contextId, policy_.ringBytesPerContext, queueIncarnationId);
        if (!inserted)
            return QueueRegistrationStatus::DuplicateContextId;

        const auto registration = dispatcher_.RegisterQueueContext(context);
        if (registration != QueueRegistrationStatus::Registered)
            queues_.erase(queue);
        else if (queueIncarnationId == std::numeric_limits<std::uint64_t>::max())
            nextQueueIncarnationId_.reset();
        else
            nextQueueIncarnationId_ = queueIncarnationId + 1U;
        return registration;
    }

    [[nodiscard]] QueueRegistrationStatus UnregisterQueueContext(
        std::uint8_t contextId)
    {
        const auto queue = queues_.find(contextId);
        if (queue == queues_.end())
            return QueueRegistrationStatus::UnknownContext;
        if (queue->second.ring.UnreadBytes() != 0U
            || std::any_of(readyCompletions_.begin(), readyCompletions_.end(),
                [contextId](const CommandCompletion& completion)
                {
                    return completion.queueContextId == contextId;
                })
            || std::any_of(tracked_.begin(), tracked_.end(),
                [contextId](const auto& entry)
                {
                    return entry.second.queueContextId == contextId;
                }))
        {
            return QueueRegistrationStatus::ContextBusy;
        }

        const auto result = dispatcher_.UnregisterQueueContext(contextId);
        if (result == QueueRegistrationStatus::Unregistered)
            queues_.erase(queue);
        return result;
    }

    [[nodiscard]] SubmitCommandStatus SubmitBytes(
        std::uint8_t contextId,
        std::span<const std::uint8_t> bytes)
    {
        const auto queue = queues_.find(contextId);
        if (queue == queues_.end())
            return SubmitCommandStatus::UnknownQueueContext;
        const auto* context = dispatcher_.QueueContext(contextId);
        if (context == nullptr)
            return SubmitCommandStatus::UnknownQueueContext;
        if (context->faulted)
            return SubmitCommandStatus::QueueFaulted;

        return queue->second.ring.Write(bytes);
    }

    [[nodiscard]] CommandProcessResult ProcessOneCommand()
    {
        CommandProcessResult fallback;
        bool hasFallback = false;
        for (std::uint32_t offset = 0U; offset < kHardwareQueueContextCount; ++offset)
        {
            const auto contextId = static_cast<std::uint8_t>(
                (static_cast<std::uint32_t>(nextQueueCursor_) + offset)
                    % kHardwareQueueContextCount);
            const auto queue = queues_.find(contextId);
            if (queue == queues_.end() || queue->second.ring.UnreadBytes() == 0U)
                continue;

            const auto* context = dispatcher_.QueueContext(contextId);
            if (context == nullptr)
            {
                if (!hasFallback)
                {
                    fallback = {CommandProcessStatus::UnknownQueueContext,
                        contextId, queue->second.ring.ConsumerPosition()};
                    hasFallback = true;
                }
                continue;
            }
            if (context->faulted)
            {
                if (!hasFallback)
                {
                    fallback = {CommandProcessStatus::QueueFaulted,
                        contextId, queue->second.ring.ConsumerPosition()};
                    hasFallback = true;
                }
                continue;
            }

            const auto packetBytePosition = queue->second.ring.ConsumerPosition();
            const auto bytes = queue->second.ring.Snapshot();
            const auto decoded = DecodeWorkgroupDispatchPacket(
                bytes, policy_.ringBytesPerContext);
            if (decoded.status == PacketDecodeStatus::Incomplete)
            {
                AdvanceQueueCursor(contextId);
                if (!hasFallback)
                {
                    fallback = {CommandProcessStatus::Incomplete,
                        contextId, packetBytePosition, decoded.packetBytes};
                    hasFallback = true;
                }
                continue;
            }

            if (decoded.status == PacketDecodeStatus::MalformedEnvelope)
            {
                if (!HasCompletionCapacity())
                {
                    AdvanceQueueCursor(contextId);
                    if (!hasFallback)
                    {
                        fallback = {CommandProcessStatus::Backpressure,
                            contextId, packetBytePosition, decoded.packetBytes};
                        hasFallback = true;
                    }
                    continue;
                }
                (void)dispatcher_.SetQueueFaulted(contextId, true);
                readyCompletions_.push_back({CommandCompletionStatus::QueueFaulted,
                    contextId, std::nullopt, packetBytePosition, 0U,
                    AdmissionFailure::None, queue->second.queueIncarnationId});
                AdvanceQueueCursor(contextId);
                return {CommandProcessStatus::QueueFaulted,
                    contextId, packetBytePosition, decoded.packetBytes};
            }

            if (decoded.status == PacketDecodeStatus::Unsupported
                || decoded.status == PacketDecodeStatus::MalformedPayload)
            {
                if (!HasCompletionCapacity())
                {
                    AdvanceQueueCursor(contextId);
                    if (!hasFallback)
                    {
                        fallback = {CommandProcessStatus::Backpressure,
                            contextId, packetBytePosition, decoded.packetBytes,
                            decoded.submissionId};
                        hasFallback = true;
                    }
                    continue;
                }
                queue->second.ring.Consume(decoded.packetBytes);
                const auto completionStatus = decoded.status == PacketDecodeStatus::Unsupported
                    ? CommandCompletionStatus::UnsupportedCommand
                    : CommandCompletionStatus::MalformedPacket;
                readyCompletions_.push_back({completionStatus, contextId,
                    decoded.submissionId, packetBytePosition, 0U,
                    AdmissionFailure::None, queue->second.queueIncarnationId});
                AdvanceQueueCursor(contextId);
                return {decoded.status == PacketDecodeStatus::Unsupported
                        ? CommandProcessStatus::RejectedUnsupported
                        : CommandProcessStatus::RejectedMalformed,
                    contextId, packetBytePosition, decoded.packetBytes,
                    decoded.submissionId};
            }

            if (!decoded.workgroup || !HasCompletionCapacity())
            {
                AdvanceQueueCursor(contextId);
                if (!hasFallback)
                {
                    fallback = {CommandProcessStatus::Backpressure,
                        contextId, packetBytePosition, decoded.packetBytes,
                        decoded.submissionId};
                    hasFallback = true;
                }
                continue;
            }

            if (!nextInternalWorkgroupId_)
            {
                (void)dispatcher_.SetQueueFaulted(contextId, true);
                readyCompletions_.push_back({CommandCompletionStatus::QueueFaulted,
                    contextId, decoded.submissionId, packetBytePosition, 0U,
                    AdmissionFailure::None, queue->second.queueIncarnationId});
                AdvanceQueueCursor(contextId);
                return {CommandProcessStatus::InternalIdExhausted,
                    contextId, packetBytePosition, decoded.packetBytes,
                    decoded.submissionId};
            }

            auto candidateId = nextInternalWorkgroupId_;
            bool shouldBackpressure = false;
            while (candidateId)
            {
                if (tracked_.contains(*candidateId))
                {
                    candidateId = NextInternalId(*candidateId);
                    continue;
                }
                const auto [tracked, inserted] = tracked_.try_emplace(
                    *candidateId,
                    TrackedWorkgroup{contextId, packetBytePosition,
                        queue->second.queueIncarnationId, *decoded.workgroup,
                        false, false});
                if (!inserted)
                {
                    candidateId = NextInternalId(*candidateId);
                    continue;
                }

                const auto enqueue = dispatcher_.EnqueueWorkgroup(
                    contextId, MakeDemand(*candidateId, *decoded.workgroup));
                if (enqueue == EnqueueWorkgroupStatus::Queued)
                {
                    queue->second.ring.Consume(decoded.packetBytes);
                    nextInternalWorkgroupId_ = NextInternalId(*candidateId);
                    AdvanceQueueCursor(contextId);
                    return {CommandProcessStatus::Enqueued, contextId,
                        packetBytePosition, decoded.packetBytes,
                        decoded.submissionId, *candidateId};
                }

                tracked_.erase(tracked);
                if (enqueue == EnqueueWorkgroupStatus::DuplicateWorkgroupId)
                {
                    candidateId = NextInternalId(*candidateId);
                    continue;
                }
                shouldBackpressure = enqueue == EnqueueWorkgroupStatus::QueueFull;
                if (!hasFallback)
                {
                    fallback = {enqueue == EnqueueWorkgroupStatus::QueueFaulted
                            ? CommandProcessStatus::QueueFaulted
                            : (shouldBackpressure
                                ? CommandProcessStatus::Backpressure
                                : CommandProcessStatus::UnknownQueueContext),
                        contextId, packetBytePosition, decoded.packetBytes,
                        decoded.submissionId};
                    hasFallback = true;
                }
                break;
            }

            if (!candidateId && !shouldBackpressure)
            {
                if (HasCompletionCapacity())
                {
                    (void)dispatcher_.SetQueueFaulted(contextId, true);
                    readyCompletions_.push_back({CommandCompletionStatus::QueueFaulted,
                        contextId, decoded.submissionId, packetBytePosition, 0U,
                        AdmissionFailure::None, queue->second.queueIncarnationId});
                    AdvanceQueueCursor(contextId);
                    return {CommandProcessStatus::InternalIdExhausted,
                        contextId, packetBytePosition, decoded.packetBytes,
                        decoded.submissionId};
                }
                if (!hasFallback)
                {
                    fallback = {CommandProcessStatus::Backpressure,
                        contextId, packetBytePosition, decoded.packetBytes,
                        decoded.submissionId};
                    hasFallback = true;
                }
            }
            AdvanceQueueCursor(contextId);
        }
        return hasFallback ? fallback : CommandProcessResult{};
    }

    [[nodiscard]] CommandDispatchCycle ScheduleOneCycle(bool tileEligible)
    {
        CommandDispatchCycle result;
        result.dispatch = dispatcher_.ScheduleOneCycle(tileEligible);
        const auto id = result.dispatch.workgroupId;
        const auto tracked = tracked_.find(id);
        if (tracked == tracked_.end())
            return result;

        if (result.dispatch.status == DispatchCycleStatus::Admitted)
        {
            const auto* context = dispatcher_.QueueContext(tracked->second.queueContextId);
            if (context == nullptr)
                throw std::logic_error("admitted command lost its registered queue context");
            tracked->second.resident = true;
            result.admitted = DispatchedWorkgroup{id,
                tracked->second.queueContextId, context->processId,
                context->addressSpaceId, tracked->second.descriptor,
                tracked->second.queueIncarnationId};
            return result;
        }

        if (result.dispatch.status == DispatchCycleStatus::Rejected
            || result.dispatch.status == DispatchCycleStatus::QueueFaulted)
        {
            const auto completionStatus = result.dispatch.status == DispatchCycleStatus::Rejected
                ? CommandCompletionStatus::AdmissionRejected
                : CommandCompletionStatus::QueueFaulted;
            readyCompletions_.push_back({completionStatus,
                tracked->second.queueContextId,
                tracked->second.descriptor.submissionId,
                tracked->second.packetBytePosition, id,
                result.dispatch.failure, tracked->second.queueIncarnationId});
            tracked_.erase(tracked);
        }
        return result;
    }

    [[nodiscard]] std::vector<CommandCompletion> CollectCompletions()
    {
        const auto retired = dispatcher_.CollectRetiredWorkgroups();
        for (const auto& workgroup : retired)
        {
            const auto tracked = tracked_.find(workgroup.workgroupId);
            if (tracked == tracked_.end())
                continue;
            readyCompletions_.push_back({
                tracked->second.cancellationRequested
                    ? CommandCompletionStatus::Cancelled
                    : CommandCompletionStatus::Completed,
                tracked->second.queueContextId,
                tracked->second.descriptor.submissionId,
                tracked->second.packetBytePosition,
                workgroup.workgroupId,
                AdmissionFailure::None, tracked->second.queueIncarnationId});
            tracked_.erase(tracked);
        }

        std::vector<CommandCompletion> completions;
        completions.reserve(readyCompletions_.size());
        while (!readyCompletions_.empty())
        {
            completions.push_back(std::move(readyCompletions_.front()));
            readyCompletions_.pop_front();
        }
        return completions;
    }

    [[nodiscard]] QueueResetResult ResetQueueContext(std::uint8_t contextId)
    {
        const auto queue = queues_.find(contextId);
        if (queue == queues_.end() || dispatcher_.QueueContext(contextId) == nullptr)
            return {};

        QueueResetResult result;
        result.status = QueueResetStatus::Reset;
        const auto droppedRange = queue->second.ring.DiscardAll();
        result.droppedBeginBytePosition = droppedRange.first;
        result.droppedEndBytePosition = droppedRange.second;

        (void)dispatcher_.SetQueueFaulted(contextId, true);
        const auto cancelled = dispatcher_.CancelQueueContext(contextId);
        for (const auto& workgroup : cancelled)
        {
            const auto tracked = tracked_.find(workgroup.workgroupId);
            if (workgroup.wasResident)
            {
                if (tracked != tracked_.end())
                    tracked->second.cancellationRequested = true;
                continue;
            }

            CommandCompletion completion{
                CommandCompletionStatus::Cancelled, contextId, std::nullopt,
                0U, workgroup.workgroupId, AdmissionFailure::None};
            completion.queueIncarnationId = queue->second.queueIncarnationId;
            if (tracked != tracked_.end())
            {
                completion.submissionId = tracked->second.descriptor.submissionId;
                completion.packetBytePosition = tracked->second.packetBytePosition;
                tracked_.erase(tracked);
            }
            result.immediateCompletions.push_back(completion);
        }
        (void)dispatcher_.SetQueueFaulted(contextId, false);
        return result;
    }

    [[nodiscard]] std::optional<CommandQueueSnapshot> InspectQueue(
        std::uint8_t contextId) const
    {
        const auto queue = queues_.find(contextId);
        if (queue == queues_.end())
            return std::nullopt;
        const auto* context = dispatcher_.QueueContext(contextId);
        if (context == nullptr)
            return std::nullopt;
        return CommandQueueSnapshot{contextId, context->faulted,
            queue->second.ring.UnreadBytes(), queue->second.ring.ReadPhysicalIndex(),
            queue->second.ring.ProducerPosition(), queue->second.ring.ConsumerPosition(),
            queue->second.queueIncarnationId};
    }

    [[nodiscard]] std::uint64_t PendingByteCountTotal() const noexcept
    {
        std::uint64_t total = 0U;
        for (const auto& [contextId, queue] : queues_)
        {
            (void)contextId;
            total += queue.ring.UnreadBytes();
        }
        return total;
    }

    [[nodiscard]] std::uint32_t TrackedWorkgroupCount() const noexcept
    {
        return static_cast<std::uint32_t>(tracked_.size());
    }

    [[nodiscard]] bool CheckInvariants() const
    {
        if (!dispatcher_.CheckInvariants()
            || tracked_.size() + readyCompletions_.size()
                > policy_.maximumTrackedWorkgroups)
        {
            return false;
        }
        for (const auto& [contextId, queue] : queues_)
        {
            (void)queue;
            if (dispatcher_.QueueContext(contextId) == nullptr)
                return false;
        }
        for (const auto& [workgroupId, tracked] : tracked_)
        {
            const auto owner = dispatcher_.QueueContextForWorkgroup(workgroupId);
            if (!owner || *owner != tracked.queueContextId
                || !queues_.contains(tracked.queueContextId))
            {
                return false;
            }
        }
        return true;
    }

private:
    class ByteRing
    {
    public:
        explicit ByteRing(std::uint32_t capacity)
            : bytes_(capacity, 0U)
        {
        }

        [[nodiscard]] SubmitCommandStatus Write(std::span<const std::uint8_t> input)
        {
            if (input.empty())
                return SubmitCommandStatus::EmptyWrite;
            if (input.size() > bytes_.size())
                return SubmitCommandStatus::PacketTooLarge;
            if (input.size() > bytes_.size() - used_)
                return SubmitCommandStatus::RingFull;
            if (input.size() > std::numeric_limits<std::uint64_t>::max() - producerPosition_)
                return SubmitCommandStatus::SequenceExhausted;

            std::size_t position = (head_ + used_) % bytes_.size();
            for (const auto byte : input)
            {
                bytes_[position] = byte;
                position = (position + 1U) % bytes_.size();
            }
            used_ += input.size();
            producerPosition_ += input.size();
            return SubmitCommandStatus::Accepted;
        }

        [[nodiscard]] std::vector<std::uint8_t> Snapshot() const
        {
            std::vector<std::uint8_t> snapshot;
            snapshot.reserve(used_);
            std::size_t position = head_;
            for (std::size_t byte = 0U; byte < used_; ++byte)
            {
                snapshot.push_back(bytes_[position]);
                position = (position + 1U) % bytes_.size();
            }
            return snapshot;
        }

        void Consume(std::uint32_t count)
        {
            if (count > used_)
                throw std::logic_error("command ring consumed beyond its unread bytes");
            head_ = (head_ + count) % bytes_.size();
            used_ -= count;
            consumerPosition_ += count;
        }

        [[nodiscard]] std::pair<std::uint64_t, std::uint64_t> DiscardAll() noexcept
        {
            const auto range = std::pair{consumerPosition_, producerPosition_};
            head_ = (head_ + used_) % bytes_.size();
            consumerPosition_ = producerPosition_;
            used_ = 0U;
            return range;
        }

        [[nodiscard]] std::uint32_t UnreadBytes() const noexcept
        {
            return static_cast<std::uint32_t>(used_);
        }
        [[nodiscard]] std::uint32_t ReadPhysicalIndex() const noexcept
        {
            return static_cast<std::uint32_t>(head_);
        }
        [[nodiscard]] std::uint64_t ProducerPosition() const noexcept
        {
            return producerPosition_;
        }
        [[nodiscard]] std::uint64_t ConsumerPosition() const noexcept
        {
            return consumerPosition_;
        }

    private:
        std::vector<std::uint8_t> bytes_;
        std::size_t head_ = 0U;
        std::size_t used_ = 0U;
        std::uint64_t producerPosition_ = 0U;
        std::uint64_t consumerPosition_ = 0U;
    };

    struct QueueState
    {
        explicit QueueState(std::uint32_t capacity, std::uint64_t queueIncarnation)
            : ring(capacity), queueIncarnationId(queueIncarnation)
        {
        }
        ByteRing ring;
        std::uint64_t queueIncarnationId;
    };

    struct TrackedWorkgroup
    {
        std::uint8_t queueContextId;
        std::uint64_t packetBytePosition;
        std::uint64_t queueIncarnationId;
        WorkgroupDispatchDescriptor descriptor;
        bool resident;
        bool cancellationRequested;
    };

    [[nodiscard]] bool HasCompletionCapacity() const noexcept
    {
        return tracked_.size() + readyCompletions_.size()
            < policy_.maximumTrackedWorkgroups;
    }

    [[nodiscard]] static std::optional<std::uint64_t> NextInternalId(
        std::uint64_t current) noexcept
    {
        if (current == std::numeric_limits<std::uint64_t>::max())
            return std::nullopt;
        return current + 1U;
    }

    [[nodiscard]] static WorkgroupDemand MakeDemand(
        std::uint64_t id,
        const WorkgroupDispatchDescriptor& descriptor)
    {
        WorkgroupDemand demand{};
        demand.id = id;
        demand.waveCount = static_cast<std::uint32_t>(descriptor.waves.size());
        demand.vgprsPerWave = 0U;
        demand.scalarPredicateUnitsPerWave = descriptor.scalarPredicateUnitsPerWave;
        demand.sharedLocalBytes = descriptor.sharedLocalBytes;
        demand.otherWorkgroupStateUnits = descriptor.otherWorkgroupStateUnits;
        demand.vgprRegisterCountsByWave.reserve(descriptor.waves.size());
        for (const auto& wave : descriptor.waves)
            demand.vgprRegisterCountsByWave.push_back(wave.vgprRegisterCount);
        return demand;
    }

    void AdvanceQueueCursor(std::uint8_t contextId) noexcept
    {
        nextQueueCursor_ = static_cast<std::uint8_t>(
            (static_cast<std::uint32_t>(contextId) + 1U)
                % kHardwareQueueContextCount);
    }

    ComputeUnitDispatchScheduler& dispatcher_;
    CommandProcessorPolicy policy_;
    std::map<std::uint8_t, QueueState> queues_;
    std::map<std::uint64_t, TrackedWorkgroup> tracked_;
    std::deque<CommandCompletion> readyCompletions_;
    std::uint8_t nextQueueCursor_ = 0U;
    std::optional<std::uint64_t> nextQueueIncarnationId_ = 1U;
    std::optional<std::uint64_t> nextInternalWorkgroupId_ = 0x8000000000000000ULL;
};

} // namespace cgx1::compute
