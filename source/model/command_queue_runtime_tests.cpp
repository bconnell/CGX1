// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "command_queue_runtime.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <map>
#include <random>
#include <span>
#include <vector>

#define CHECK(x) do { if (!(x)) { std::cerr << "[fail] " #x " line " << __LINE__ << '\n'; return 1; } } while (false)

using namespace cgx1::compute;

namespace {

CuResourceLimits Limits(std::uint32_t waves = 8U)
{
    return {waves, 64U, 128U, 4096U, 8U, 64U};
}

DispatchPolicy DispatchConfig(std::uint32_t pendingPerContext = 8U)
{
    DispatchPolicy policy;
    policy.maximumQueueContexts = 8U;
    policy.pendingWorkgroupsPerContext = pendingPerContext;
    policy.agingIntervalCycles = 4U;
    return policy;
}

DispatchQueueContext Context(
    std::uint8_t id,
    std::uint64_t process = 0x111U,
    std::uint64_t addressSpace = 0x222U,
    std::uint8_t priority = 3U)
{
    return {id, process, addressSpace, priority, DispatchEngineClass::Compute, false};
}

WorkgroupDispatchDescriptor Descriptor(
    std::uint64_t submission,
    std::uint64_t pc = 0x1000U,
    std::uint32_t waves = 1U,
    std::uint16_t registers = 16U)
{
    WorkgroupDispatchDescriptor descriptor;
    descriptor.submissionId = submission;
    descriptor.entryPc = pc;
    descriptor.scalarPredicateUnitsPerWave = 1U;
    for (std::uint32_t wave = 0U; wave < waves; ++wave)
        descriptor.waves.push_back({0xffffffffU >> (wave % 4U), registers});
    return descriptor;
}

CommandProcessorPolicy ProcessorConfig(std::uint32_t ringBytes = 4096U,
    std::uint32_t tracked = 64U)
{
    return {ringBytes, tracked};
}

int CompleteLaunch(
    ComputeUnitDispatchScheduler& scheduler,
    const DispatchedWorkgroup& launch)
{
    for (std::uint32_t wave = 0U;
        wave < static_cast<std::uint32_t>(launch.descriptor.waves.size()); ++wave)
    {
        if (!scheduler.Workgroups().TerminateWave(launch.workgroupId, wave))
            return 1;
    }
    return 0;
}

const CommandCompletion* FindCompletion(
    const std::vector<CommandCompletion>& completions,
    std::uint8_t context,
    std::uint64_t token)
{
    const auto found = std::find_if(completions.begin(), completions.end(),
        [context, token](const auto& completion)
        {
            return completion.queueContextId == context
                && completion.submissionId == token;
        });
    return found == completions.end() ? nullptr : &*found;
}

int TestPacketCodecAndValidation()
{
    auto descriptor = Descriptor(0x123456789abcdef0ULL, 0x123456789abcu, 3U, 256U);
    descriptor.sharedLocalBytes = 513U;
    descriptor.otherWorkgroupStateUnits = 7U;
    descriptor.scalarPredicateUnitsPerWave = 4U;
    const auto bytes = EncodeWorkgroupDispatchPacket(descriptor);
    CHECK(bytes.size() == 44U + 8U * descriptor.waves.size());
    CHECK(bytes[0] == static_cast<std::uint8_t>('C'));
    CHECK(bytes[1] == static_cast<std::uint8_t>('G'));
    CHECK(bytes[2] == static_cast<std::uint8_t>('X'));
    CHECK(bytes[3] == static_cast<std::uint8_t>('1'));
    CHECK(bytes[4] == 1U && bytes[5] == 0U);
    CHECK(bytes[6] == 1U && bytes[7] == 0U);

    const auto decoded = DecodeWorkgroupDispatchPacket(bytes, 4096U);
    CHECK(decoded.status == PacketDecodeStatus::Decoded);
    CHECK(decoded.packetBytes == bytes.size());
    CHECK(decoded.workgroup.has_value());
    CHECK(decoded.workgroup->submissionId == descriptor.submissionId);
    CHECK(decoded.workgroup->entryPc == descriptor.entryPc);
    CHECK(decoded.workgroup->waves.size() == descriptor.waves.size());
    CHECK(decoded.workgroup->waves[2].activeLaneMask == descriptor.waves[2].activeLaneMask);
    CHECK(decoded.workgroup->waves[2].vgprRegisterCount == 256U);
    CHECK(decoded.workgroup->sharedLocalBytes == 513U);
    CHECK(decoded.workgroup->otherWorkgroupStateUnits == 7U);
    CHECK(decoded.workgroup->scalarPredicateUnitsPerWave == 4U);

    const auto incomplete = DecodeWorkgroupDispatchPacket(
        std::span<const std::uint8_t>(bytes.data(), 5U), 4096U);
    CHECK(incomplete.status == PacketDecodeStatus::Incomplete);

    auto badPc = descriptor;
    badPc.entryPc = 0x1002U;
    bool rejected = false;
    try { (void)EncodeWorkgroupDispatchPacket(badPc); }
    catch (const std::invalid_argument&) { rejected = true; }
    CHECK(rejected);
    auto badMask = descriptor;
    badMask.waves[0].activeLaneMask = 0U;
    rejected = false;
    try { (void)EncodeWorkgroupDispatchPacket(badMask); }
    catch (const std::invalid_argument&) { rejected = true; }
    CHECK(rejected);
    auto badRegisters = descriptor;
    badRegisters.waves[0].vgprRegisterCount = 257U;
    rejected = false;
    try { (void)EncodeWorkgroupDispatchPacket(badRegisters); }
    catch (const std::invalid_argument&) { rejected = true; }
    CHECK(rejected);
    auto tooManyWaves = descriptor;
    tooManyWaves.waves.assign(65536U, {1U, 16U});
    rejected = false;
    try { (void)EncodeWorkgroupDispatchPacket(tooManyWaves); }
    catch (const std::invalid_argument&) { rejected = true; }
    CHECK(rejected);
    return 0;
}

int TestBoundedRingBackpressureAndPhysicalWrap()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig(64U));
    CHECK(runtime.RegisterQueueContext(Context(1U)) == QueueRegistrationStatus::Registered);
    const auto packet = EncodeWorkgroupDispatchPacket(Descriptor(7U));
    CHECK(packet.size() == 52U);
    CHECK(runtime.SubmitBytes(1U,
        std::span<const std::uint8_t>(packet.data(), 5U))
        == SubmitCommandStatus::Accepted);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Incomplete);
    CHECK(runtime.InspectQueue(1U)->consumerBytePosition == 0U);
    CHECK(runtime.SubmitBytes(1U,
        std::span<const std::uint8_t>(packet.data() + 5U, packet.size() - 5U))
        == SubmitCommandStatus::Accepted);
    const auto before = runtime.InspectQueue(1U);
    CHECK(before && before->unreadBytes == 52U && before->producerBytePosition == 52U);
    CHECK(runtime.SubmitBytes(1U, packet) == SubmitCommandStatus::RingFull);
    CHECK(runtime.InspectQueue(1U)->producerBytePosition == 52U);

    const auto parsed = runtime.ProcessOneCommand();
    CHECK(parsed.status == CommandProcessStatus::Enqueued);
    CHECK(parsed.packetBytePosition == 0U);
    auto dispatch = runtime.ScheduleOneCycle(true);
    CHECK(dispatch.dispatch.status == DispatchCycleStatus::Admitted);
    CHECK(dispatch.admitted.has_value());
    CHECK(CompleteLaunch(scheduler, *dispatch.admitted) == 0);
    const auto firstCompletion = runtime.CollectCompletions();
    CHECK(FindCompletion(firstCompletion, 1U, 7U) != nullptr);

    auto secondPacket = EncodeWorkgroupDispatchPacket(Descriptor(8U));
    CHECK(runtime.SubmitBytes(1U,
        std::span<const std::uint8_t>(secondPacket.data(), 13U))
        == SubmitCommandStatus::Accepted);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Incomplete);
    CHECK(runtime.InspectQueue(1U)->readPhysicalIndex == 52U);
    CHECK(runtime.SubmitBytes(1U,
        std::span<const std::uint8_t>(secondPacket.data() + 13U,
            secondPacket.size() - 13U)) == SubmitCommandStatus::Accepted);
    CHECK(runtime.InspectQueue(1U)->unreadBytes == 52U);
    const auto wrapped = runtime.ProcessOneCommand();
    CHECK(wrapped.status == CommandProcessStatus::Enqueued);
    CHECK(wrapped.packetBytePosition == 52U);
    CHECK(runtime.InspectQueue(1U)->consumerBytePosition == 104U);
    CHECK(runtime.InspectQueue(1U)->readPhysicalIndex == 40U);
    dispatch = runtime.ScheduleOneCycle(true);
    CHECK(dispatch.dispatch.status == DispatchCycleStatus::Admitted);
    CHECK(CompleteLaunch(scheduler, *dispatch.admitted) == 0);
    CHECK(FindCompletion(runtime.CollectCompletions(), 1U, 8U) != nullptr);
    CHECK(runtime.PendingByteCountTotal() == 0U);
    return 0;
}

int TestQueueUnregisterWaitsForCompletionIdentity()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig());
    CHECK(runtime.RegisterQueueContext(Context(4U)) == QueueRegistrationStatus::Registered);

    auto malformed = EncodeWorkgroupDispatchPacket(Descriptor(41U));
    malformed[51U] = 1U;
    CHECK(runtime.SubmitBytes(4U, malformed) == SubmitCommandStatus::Accepted);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::RejectedMalformed);
    CHECK(runtime.UnregisterQueueContext(4U) == QueueRegistrationStatus::ContextBusy);

    const auto rejected = runtime.CollectCompletions();
    CHECK(FindCompletion(rejected, 4U, 41U) != nullptr);
    CHECK(runtime.UnregisterQueueContext(4U) == QueueRegistrationStatus::Unregistered);

    const auto replacementContext = Context(4U, 0x333U, 0x444U);
    CHECK(runtime.RegisterQueueContext(replacementContext)
        == QueueRegistrationStatus::Registered);
    const auto packet = EncodeWorkgroupDispatchPacket(Descriptor(41U));
    CHECK(runtime.SubmitBytes(4U, packet) == SubmitCommandStatus::Accepted);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Enqueued);
    const auto dispatch = runtime.ScheduleOneCycle(true);
    CHECK(dispatch.admitted.has_value());
    CHECK(dispatch.admitted->processId == replacementContext.processId);
    CHECK(dispatch.admitted->addressSpaceId == replacementContext.addressSpaceId);
    CHECK(CompleteLaunch(scheduler, *dispatch.admitted) == 0);
    CHECK(FindCompletion(runtime.CollectCompletions(), 4U, 41U) != nullptr);
    CHECK(runtime.CheckInvariants());
    return 0;
}

int TestUnsupportedMalformedAndQueueFaultRecovery()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig());
    CHECK(runtime.RegisterQueueContext(Context(2U)) == QueueRegistrationStatus::Registered);

    auto unsupported = EncodeWorkgroupDispatchPacket(Descriptor(10U));
    unsupported[6] = 2U;
    CHECK(runtime.SubmitBytes(2U, unsupported) == SubmitCommandStatus::Accepted);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::RejectedUnsupported);
    auto completions = runtime.CollectCompletions();
    CHECK(completions.size() == 1U);
    CHECK(completions[0].queueContextId == 2U);
    CHECK(completions[0].status
        == CommandCompletionStatus::UnsupportedCommand);

    auto unsupportedOpcode = EncodeWorkgroupDispatchPacket(Descriptor(14U));
    unsupportedOpcode[4U] = 2U;
    CHECK(runtime.SubmitBytes(2U, unsupportedOpcode) == SubmitCommandStatus::Accepted);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::RejectedUnsupported);
    completions = runtime.CollectCompletions();
    CHECK(completions.size() == 1U);
    CHECK(completions[0].status == CommandCompletionStatus::UnsupportedCommand);
    CHECK(completions[0].queueContextId == 2U);

    auto malformedPayload = EncodeWorkgroupDispatchPacket(Descriptor(11U));
    malformedPayload[51] = 1U;
    CHECK(runtime.SubmitBytes(2U, malformedPayload) == SubmitCommandStatus::Accepted);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::RejectedMalformed);
    completions = runtime.CollectCompletions();
    CHECK(FindCompletion(completions, 2U, 11U) != nullptr);
    CHECK(FindCompletion(completions, 2U, 11U)->status
        == CommandCompletionStatus::MalformedPacket);
    CHECK(!runtime.InspectQueue(2U)->faulted);

    auto malformedLength = EncodeWorkgroupDispatchPacket(Descriptor(12U));
    malformedLength[8U] = 8U;
    malformedLength[9U] = 0U;
    malformedLength[10U] = 0U;
    malformedLength[11U] = 0U;
    CHECK(runtime.SubmitBytes(2U, malformedLength) == SubmitCommandStatus::Accepted);
    const auto consumerBefore = runtime.InspectQueue(2U)->consumerBytePosition;
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::QueueFaulted);
    CHECK(runtime.InspectQueue(2U)->faulted);
    CHECK(runtime.InspectQueue(2U)->consumerBytePosition == consumerBefore);
    CHECK(scheduler.QueueContext(2U)->faulted);
    const auto lengthReset = runtime.ResetQueueContext(2U);
    CHECK(lengthReset.status == QueueResetStatus::Reset);
    CHECK(lengthReset.droppedEndBytePosition - lengthReset.droppedBeginBytePosition
        == malformedLength.size());
    CHECK(!runtime.InspectQueue(2U)->faulted);
    CHECK(!scheduler.QueueContext(2U)->faulted);
    CHECK(runtime.InspectQueue(2U)->unreadBytes == 0U);
    CHECK(runtime.CollectCompletions().size() == 1U);

    auto malformedMagic = EncodeWorkgroupDispatchPacket(Descriptor(13U));
    malformedMagic[0] = 0U;
    CHECK(runtime.SubmitBytes(2U, malformedMagic) == SubmitCommandStatus::Accepted);
    const auto magicConsumerBefore = runtime.InspectQueue(2U)->consumerBytePosition;
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::QueueFaulted);
    CHECK(runtime.InspectQueue(2U)->consumerBytePosition == magicConsumerBefore);
    const auto magicReset = runtime.ResetQueueContext(2U);
    CHECK(magicReset.status == QueueResetStatus::Reset);
    CHECK(magicReset.droppedEndBytePosition - magicReset.droppedBeginBytePosition
        == malformedMagic.size());
    CHECK(runtime.CollectCompletions().size() == 1U);
    CHECK(runtime.CheckInvariants() && scheduler.CheckInvariants());
    return 0;
}

int TestContextIdentityAndCompletionCorrelation()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig());
    CHECK(runtime.RegisterQueueContext(Context(3U, 0xaaaU, 0xabcU))
        == QueueRegistrationStatus::Registered);
    CHECK(runtime.RegisterQueueContext(Context(4U, 0xbbbU, 0xdefU))
        == QueueRegistrationStatus::Registered);
    const auto first = EncodeWorkgroupDispatchPacket(Descriptor(99U, 0x1000U));
    const auto second = EncodeWorkgroupDispatchPacket(Descriptor(99U, 0x2000U, 2U));
    CHECK(runtime.SubmitBytes(3U, first) == SubmitCommandStatus::Accepted);
    CHECK(runtime.SubmitBytes(4U, second) == SubmitCommandStatus::Accepted);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Enqueued);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Enqueued);

    std::map<std::uint64_t, std::uint32_t> launchedWaves;
    for (std::uint32_t i = 0U; i < 2U; ++i)
    {
        const auto cycle = runtime.ScheduleOneCycle(true);
        CHECK(cycle.dispatch.status == DispatchCycleStatus::Admitted);
        CHECK(cycle.admitted.has_value());
        const auto& launch = *cycle.admitted;
        const auto* context = scheduler.QueueContext(launch.queueContextId);
        CHECK(context != nullptr);
        if (launch.queueContextId == 3U)
        {
            CHECK(context->processId == 0xaaaU && context->addressSpaceId == 0xabcU);
            CHECK(launch.descriptor.entryPc == 0x1000U);
        }
        else
        {
            CHECK(launch.queueContextId == 4U);
            CHECK(context->processId == 0xbbbU && context->addressSpaceId == 0xdefU);
            CHECK(launch.descriptor.entryPc == 0x2000U);
            CHECK(launch.descriptor.waves.size() == 2U);
        }
        CHECK(launch.descriptor.submissionId == 99U);
        launchedWaves.emplace(launch.workgroupId,
            static_cast<std::uint32_t>(launch.descriptor.waves.size()));
    }
    for (const auto& [id, count] : launchedWaves)
    {
        for (std::uint32_t wave = 0U; wave < count; ++wave)
            CHECK(scheduler.Workgroups().TerminateWave(id, wave));
    }
    const auto completions = runtime.CollectCompletions();
    CHECK(FindCompletion(completions, 3U, 99U) != nullptr);
    CHECK(FindCompletion(completions, 4U, 99U) != nullptr);
    CHECK(FindCompletion(completions, 3U, 99U)->packetBytePosition
        != FindCompletion(completions, 4U, 99U)->packetBytePosition
        || FindCompletion(completions, 3U, 99U)->queueContextId
            != FindCompletion(completions, 4U, 99U)->queueContextId);
    CHECK(runtime.CheckInvariants() && scheduler.CheckInvariants());
    return 0;
}

int TestDispatcherBackpressureAndResourceRetry()
{
    ComputeUnitDispatchScheduler scheduler(Limits(1U), DispatchConfig(1U));
    CommandQueueRuntime runtime(scheduler, ProcessorConfig());
    CHECK(runtime.RegisterQueueContext(Context(5U)) == QueueRegistrationStatus::Registered);
    const auto first = EncodeWorkgroupDispatchPacket(Descriptor(20U));
    const auto second = EncodeWorkgroupDispatchPacket(Descriptor(21U));
    CHECK(runtime.SubmitBytes(5U, first) == SubmitCommandStatus::Accepted);
    CHECK(runtime.SubmitBytes(5U, second) == SubmitCommandStatus::Accepted);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Enqueued);
    const auto unreadBefore = runtime.InspectQueue(5U)->unreadBytes;
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Backpressure);
    CHECK(runtime.InspectQueue(5U)->unreadBytes == unreadBefore);

    const auto admittedFirst = runtime.ScheduleOneCycle(true);
    CHECK(admittedFirst.dispatch.status == DispatchCycleStatus::Admitted);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Enqueued);
    const auto blocked = runtime.ScheduleOneCycle(true);
    CHECK(blocked.dispatch.status == DispatchCycleStatus::Deferred);
    CHECK(runtime.CollectCompletions().empty());
    CHECK(CompleteLaunch(scheduler, *admittedFirst.admitted) == 0);
    CHECK(FindCompletion(runtime.CollectCompletions(), 5U, 20U) != nullptr);
    const auto admittedSecond = runtime.ScheduleOneCycle(true);
    CHECK(admittedSecond.dispatch.status == DispatchCycleStatus::Admitted);
    CHECK(CompleteLaunch(scheduler, *admittedSecond.admitted) == 0);
    CHECK(FindCompletion(runtime.CollectCompletions(), 5U, 21U) != nullptr);
    return 0;
}

int TestCompletionTrackingCapacityBackpressure()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig(4096U, 1U));
    CHECK(runtime.RegisterQueueContext(Context(5U)) == QueueRegistrationStatus::Registered);
    const auto firstPacket = EncodeWorkgroupDispatchPacket(Descriptor(51U));
    const auto secondPacket = EncodeWorkgroupDispatchPacket(Descriptor(52U));
    CHECK(runtime.SubmitBytes(5U, firstPacket) == SubmitCommandStatus::Accepted);
    CHECK(runtime.SubmitBytes(5U, secondPacket) == SubmitCommandStatus::Accepted);

    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Enqueued);
    CHECK(runtime.TrackedWorkgroupCount() == 1U);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Backpressure);
    CHECK(runtime.InspectQueue(5U)->unreadBytes == secondPacket.size());

    auto dispatch = runtime.ScheduleOneCycle(true);
    CHECK(dispatch.admitted.has_value());
    CHECK(CompleteLaunch(scheduler, *dispatch.admitted) == 0);
    CHECK(FindCompletion(runtime.CollectCompletions(), 5U, 51U) != nullptr);
    CHECK(runtime.TrackedWorkgroupCount() == 0U);

    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Enqueued);
    dispatch = runtime.ScheduleOneCycle(true);
    CHECK(dispatch.admitted.has_value());
    CHECK(CompleteLaunch(scheduler, *dispatch.admitted) == 0);
    CHECK(FindCompletion(runtime.CollectCompletions(), 5U, 52U) != nullptr);
    CHECK(runtime.CheckInvariants());
    return 0;
}

int TestQueueScopedResetAndQuiescentCancellation()
{
    ComputeUnitDispatchScheduler scheduler(Limits(3U), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig());
    CHECK(runtime.RegisterQueueContext(Context(6U)) == QueueRegistrationStatus::Registered);
    CHECK(runtime.RegisterQueueContext(Context(7U)) == QueueRegistrationStatus::Registered);

    CHECK(runtime.SubmitBytes(6U,
        EncodeWorkgroupDispatchPacket(Descriptor(30U))) == SubmitCommandStatus::Accepted);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Enqueued);
    const auto active = runtime.ScheduleOneCycle(true);
    CHECK(active.dispatch.status == DispatchCycleStatus::Admitted);
    CHECK(scheduler.Workgroups().BeginWaveExecution(active.admitted->workgroupId, 0U));

    CHECK(runtime.SubmitBytes(6U,
        EncodeWorkgroupDispatchPacket(Descriptor(31U))) == SubmitCommandStatus::Accepted);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Enqueued);
    const std::array<std::uint8_t, 3> partial{1U, 2U, 3U};
    CHECK(runtime.SubmitBytes(6U, partial) == SubmitCommandStatus::Accepted);
    const auto reset = runtime.ResetQueueContext(6U);
    CHECK(reset.status == QueueResetStatus::Reset);
    CHECK(reset.immediateCompletions.size() == 1U);
    CHECK(FindCompletion(reset.immediateCompletions, 6U, 31U) != nullptr);
    CHECK(FindCompletion(reset.immediateCompletions, 6U, 31U)->status
        == CommandCompletionStatus::Cancelled);
    CHECK(reset.droppedEndBytePosition - reset.droppedBeginBytePosition == 3U);
    CHECK(runtime.InspectQueue(6U)->unreadBytes == 0U);
    CHECK(scheduler.Workgroups().WorkgroupCount() == 1U);
    CHECK(runtime.CollectCompletions().empty());

    CHECK(runtime.SubmitBytes(7U,
        EncodeWorkgroupDispatchPacket(Descriptor(40U))) == SubmitCommandStatus::Accepted);
    CHECK(runtime.ProcessOneCommand().status == CommandProcessStatus::Enqueued);
    const auto other = runtime.ScheduleOneCycle(true);
    CHECK(other.dispatch.status == DispatchCycleStatus::Admitted);
    CHECK(other.admitted->queueContextId == 7U);
    CHECK(CompleteLaunch(scheduler, *other.admitted) == 0);
    CHECK(FindCompletion(runtime.CollectCompletions(), 7U, 40U) != nullptr);

    CHECK(scheduler.Workgroups().CompleteWaveExecution(active.admitted->workgroupId, 0U));
    const auto cancelled = runtime.CollectCompletions();
    const auto* terminal = FindCompletion(cancelled, 6U, 30U);
    CHECK(terminal != nullptr && terminal->status == CommandCompletionStatus::Cancelled);
    CHECK(runtime.TrackedWorkgroupCount() == 0U);
    CHECK(runtime.CheckInvariants() && scheduler.CheckInvariants());
    return 0;
}

int TestRandomizedQueueDispatchAndReuse()
{
    ComputeUnitDispatchScheduler scheduler(Limits(12U), DispatchConfig(8U));
    CommandQueueRuntime runtime(scheduler, ProcessorConfig(1024U, 64U));
    for (std::uint8_t context = 0U; context < 4U; ++context)
        CHECK(runtime.RegisterQueueContext(Context(context)) == QueueRegistrationStatus::Registered);

    std::mt19937 random(0x43475831U);
    std::map<std::uint64_t, std::uint32_t> active;
    std::uint32_t completionsSeen = 0U;
    for (std::uint32_t cycle = 0U; cycle < 1800U; ++cycle)
    {
        const auto action = random() % 5U;
        const auto context = static_cast<std::uint8_t>(random() % 4U);
        if (action <= 1U)
        {
            const auto waves = 1U + random() % 3U;
            auto descriptor = Descriptor(random() % 9U,
                0x1000U + static_cast<std::uint64_t>(cycle % 64U) * 4U,
                waves, static_cast<std::uint16_t>(1U + random() % 32U));
            const auto packet = EncodeWorkgroupDispatchPacket(descriptor);
            const auto written = runtime.SubmitBytes(context, packet);
            CHECK(written == SubmitCommandStatus::Accepted
                || written == SubmitCommandStatus::RingFull);
        }
        else if (action == 2U)
        {
            const auto processed = runtime.ProcessOneCommand();
            CHECK(processed.status != CommandProcessStatus::QueueFaulted);
        }
        else
        {
            const auto scheduled = runtime.ScheduleOneCycle(true);
            if (scheduled.admitted)
            {
                active.emplace(scheduled.admitted->workgroupId,
                    static_cast<std::uint32_t>(scheduled.admitted->descriptor.waves.size()));
            }
        }

        if ((random() % 3U) == 0U)
        {
            for (auto iterator = active.begin(); iterator != active.end();)
            {
                if (!scheduler.Workgroups().WorkgroupCount())
                    break;
                for (std::uint32_t wave = 0U; wave < iterator->second; ++wave)
                    CHECK(scheduler.Workgroups().TerminateWave(iterator->first, wave));
                iterator = active.erase(iterator);
                if ((random() % 2U) != 0U)
                    break;
            }
        }
        completionsSeen += static_cast<std::uint32_t>(runtime.CollectCompletions().size());
        CHECK(runtime.CheckInvariants());
        CHECK(scheduler.CheckInvariants());
    }

    for (std::uint32_t cycle = 0U; cycle < 5000U
        && (runtime.PendingByteCountTotal() != 0U
            || scheduler.PendingWorkgroupCount() != 0U
            || runtime.TrackedWorkgroupCount() != 0U); ++cycle)
    {
        (void)runtime.ProcessOneCommand();
        const auto scheduled = runtime.ScheduleOneCycle(true);
        if (scheduled.admitted)
        {
            for (std::uint32_t wave = 0U;
                wave < static_cast<std::uint32_t>(scheduled.admitted->descriptor.waves.size());
                ++wave)
            {
                CHECK(scheduler.Workgroups().TerminateWave(
                    scheduled.admitted->workgroupId, wave));
            }
        }
        for (const auto& [id, waveCount] : active)
        {
            for (std::uint32_t wave = 0U; wave < waveCount; ++wave)
                (void)scheduler.Workgroups().TerminateWave(id, wave);
        }
        active.clear();
        completionsSeen += static_cast<std::uint32_t>(runtime.CollectCompletions().size());
        CHECK(runtime.CheckInvariants() && scheduler.CheckInvariants());
    }
    CHECK(runtime.PendingByteCountTotal() == 0U);
    CHECK(scheduler.PendingWorkgroupCount() == 0U);
    CHECK(runtime.TrackedWorkgroupCount() == 0U);
    CHECK(completionsSeen != 0U);
    return 0;
}

} // namespace

int main()
{
    if (TestPacketCodecAndValidation() != 0
        || TestBoundedRingBackpressureAndPhysicalWrap() != 0
        || TestUnsupportedMalformedAndQueueFaultRecovery() != 0
        || TestQueueUnregisterWaitsForCompletionIdentity() != 0
        || TestContextIdentityAndCompletionCorrelation() != 0
        || TestDispatcherBackpressureAndResourceRetry() != 0
        || TestCompletionTrackingCapacityBackpressure() != 0
        || TestQueueScopedResetAndQuiescentCancellation() != 0
        || TestRandomizedQueueDispatchAndReuse() != 0)
    {
        return 1;
    }
    std::cout << "[pass] CGX1 bounded command queue/runtime reference checks passed.\n";
    return 0;
}
