// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_context.hpp"
#include "command_queue_runtime.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <map>
#include <random>
#include <span>
#include <vector>

#define CHECK(x) do { if (!(x)) { std::cerr << "[fail] " #x " line " << __LINE__; ::cgx1::testing::WriteRandomTestFailureContext(std::cerr); std::cerr << '\n'; return 1; } } while (false)

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
    const auto golden = EncodeWorkgroupDispatchPacket(Descriptor(0x0807060504030201ULL));
    const std::array<std::uint8_t, 52U> expected{
        0x43U, 0x47U, 0x58U, 0x31U, 0x01U, 0x00U, 0x01U, 0x00U,
        0x34U, 0x00U, 0x00U, 0x00U,
        0x01U, 0x02U, 0x03U, 0x04U, 0x05U, 0x06U, 0x07U, 0x08U,
        0x00U, 0x10U, 0x00U, 0x00U, 0x00U, 0x00U, 0x00U, 0x00U,
        0x01U, 0x00U, 0x01U, 0x00U,
        0x00U, 0x00U, 0x00U, 0x00U, 0x00U, 0x00U, 0x00U, 0x00U,
        0x00U, 0x00U, 0x00U, 0x00U,
        0xffU, 0xffU, 0xffU, 0xffU, 0x10U, 0x00U, 0x00U, 0x00U};
    CHECK(std::equal(golden.begin(), golden.end(), expected.begin(), expected.end()));

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

    const auto exactPacketLimit = DecodeWorkgroupDispatchPacket(
        golden, static_cast<std::uint32_t>(golden.size()));
    CHECK(exactPacketLimit.status == PacketDecodeStatus::Decoded);
    const auto packetLimitOneByteShort = DecodeWorkgroupDispatchPacket(
        golden, static_cast<std::uint32_t>(golden.size() - 1U));
    CHECK(packetLimitOneByteShort.status == PacketDecodeStatus::MalformedEnvelope);

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

int TestCommandProcessorPolicyBoundaries()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), DispatchConfig());
    CommandQueueRuntime minimum(scheduler, ProcessorConfig(52U, 1U));
    CHECK(minimum.CheckInvariants());

    CommandQueueRuntime maximum(
        scheduler, ProcessorConfig(kMaximumCommandRingBytesPerContext,
            kMaximumTrackedCommandWorkgroups));
    CHECK(maximum.CheckInvariants());

    bool rejected = false;
    try { CommandQueueRuntime invalid(scheduler, ProcessorConfig(51U, 1U)); }
    catch (const std::invalid_argument&) { rejected = true; }
    CHECK(rejected);

    rejected = false;
    try { CommandQueueRuntime invalid(scheduler, ProcessorConfig(65537U, 1U)); }
    catch (const std::invalid_argument&) { rejected = true; }
    CHECK(rejected);

    rejected = false;
    try { CommandQueueRuntime invalid(scheduler, ProcessorConfig(
        kMaximumCommandRingBytesPerContext,
        kMaximumTrackedCommandWorkgroups + 1U)); }
    catch (const std::invalid_argument&) { rejected = true; }
    CHECK(rejected);
    return 0;
}

int TestReservedFlagsConsumeCompleteFramedPacket()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig());
    {
        auto&& check_action_registerqueuecontext_204_1 = (runtime.RegisterQueueContext(Context(1U)));
        CHECK(check_action_registerqueuecontext_204_1 == QueueRegistrationStatus::Registered);
    }
    auto packet = EncodeWorkgroupDispatchPacket(Descriptor(13U));
    packet[7U] = 1U;
    const auto following = EncodeWorkgroupDispatchPacket(Descriptor(14U));
    {
        auto&& check_action_submitbytes_208_2 = (runtime.SubmitBytes(1U, std::span<const std::uint8_t>(packet.data(), 13U)));
        CHECK(check_action_submitbytes_208_2
        == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_210_3 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_210_3.status == CommandProcessStatus::Incomplete);
    }
    CHECK(!runtime.InspectQueue(1U)->faulted);
    CHECK(runtime.InspectQueue(1U)->consumerBytePosition == 0U);

    {
        auto&& check_action_submitbytes_214_4 = (runtime.SubmitBytes(1U,
        std::span<const std::uint8_t>(packet.data() + 13U, packet.size() - 13U)));
        CHECK(check_action_submitbytes_214_4
        == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_submitbytes_217_5 = (runtime.SubmitBytes(1U, following));
        CHECK(check_action_submitbytes_217_5 == SubmitCommandStatus::Accepted);
    }
    const auto rejected = runtime.ProcessOneCommand();
    CHECK(rejected.status == CommandProcessStatus::RejectedMalformed);
    CHECK(rejected.packetBytePosition == 0U);
    CHECK(runtime.InspectQueue(1U)->unreadBytes == following.size());
    CHECK(runtime.InspectQueue(1U)->consumerBytePosition == packet.size());
    CHECK(!runtime.InspectQueue(1U)->faulted);
    {
        auto&& check_action_processonecommand_224_6 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_224_6.status == CommandProcessStatus::Enqueued);
    }
    const auto completions = runtime.CollectCompletions();
    CHECK(completions.size() == 1U);
    CHECK(completions[0].submissionId == 13U);
    CHECK(completions[0].status == CommandCompletionStatus::MalformedPacket);
    const auto dispatch = runtime.ScheduleOneCycle(true);
    CHECK(dispatch.dispatch.status == DispatchCycleStatus::Admitted);
    CHECK(dispatch.admitted->descriptor.submissionId == 14U);
    {
        auto&& check_action_completelaunch_232_7 = (CompleteLaunch(scheduler, *dispatch.admitted));
        CHECK(check_action_completelaunch_232_7 == 0);
    }
    {
        auto&& check_action_collectcompletions_233_8 = (runtime.CollectCompletions());
        CHECK(FindCompletion(check_action_collectcompletions_233_8, 1U, 14U) != nullptr);
    }
    CHECK(runtime.CheckInvariants());
    return 0;
}

int TestDuplicateSubmissionTokensSameContext()
{
    ComputeUnitDispatchScheduler scheduler(Limits(2U), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig());
    {
        auto&& check_action_registerqueuecontext_242_9 = (runtime.RegisterQueueContext(Context(1U)));
        CHECK(check_action_registerqueuecontext_242_9 == QueueRegistrationStatus::Registered);
    }
    const auto firstPacket = EncodeWorkgroupDispatchPacket(Descriptor(77U, 0x1000U));
    const auto secondPacket = EncodeWorkgroupDispatchPacket(Descriptor(77U, 0x2000U));
    const auto incarnationId = runtime.InspectQueue(1U)->queueIncarnationId;
    {
        auto&& check_action_submitbytes_246_10 = (runtime.SubmitBytes(1U, firstPacket));
        CHECK(check_action_submitbytes_246_10 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_submitbytes_247_11 = (runtime.SubmitBytes(1U, secondPacket));
        CHECK(check_action_submitbytes_247_11 == SubmitCommandStatus::Accepted);
    }
    const auto first = runtime.ProcessOneCommand();
    const auto second = runtime.ProcessOneCommand();
    CHECK(first.status == CommandProcessStatus::Enqueued);
    CHECK(second.status == CommandProcessStatus::Enqueued);
    CHECK(first.packetBytePosition == 0U);
    CHECK(second.packetBytePosition == firstPacket.size());

    auto dispatch = runtime.ScheduleOneCycle(true);
    CHECK(dispatch.dispatch.status == DispatchCycleStatus::Admitted);
    CHECK(dispatch.admitted->descriptor.entryPc == 0x1000U);
    CHECK(dispatch.admitted->queueIncarnationId == incarnationId);
    {
        auto&& check_action_completelaunch_259_12 = (CompleteLaunch(scheduler, *dispatch.admitted));
        CHECK(check_action_completelaunch_259_12 == 0);
    }
    auto completions = runtime.CollectCompletions();
    CHECK(completions.size() == 1U);
    CHECK(completions[0].submissionId == 77U);
    CHECK(completions[0].packetBytePosition == first.packetBytePosition);
    CHECK(completions[0].queueIncarnationId == incarnationId);

    dispatch = runtime.ScheduleOneCycle(true);
    CHECK(dispatch.dispatch.status == DispatchCycleStatus::Admitted);
    CHECK(dispatch.admitted->descriptor.entryPc == 0x2000U);
    CHECK(dispatch.admitted->queueIncarnationId == incarnationId);
    {
        auto&& check_action_completelaunch_270_13 = (CompleteLaunch(scheduler, *dispatch.admitted));
        CHECK(check_action_completelaunch_270_13 == 0);
    }
    completions = runtime.CollectCompletions();
    CHECK(completions.size() == 1U);
    CHECK(completions[0].submissionId == 77U);
    CHECK(completions[0].packetBytePosition == second.packetBytePosition);
    CHECK(completions[0].queueIncarnationId == incarnationId);
    CHECK(runtime.CheckInvariants());
    return 0;
}

int TestBoundedRingBackpressureAndPhysicalWrap()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig(64U));
    {
        auto&& check_action_registerqueuecontext_284_14 = (runtime.RegisterQueueContext(Context(1U)));
        CHECK(check_action_registerqueuecontext_284_14 == QueueRegistrationStatus::Registered);
    }
    const auto packet = EncodeWorkgroupDispatchPacket(Descriptor(7U));
    CHECK(packet.size() == 52U);
    {
        auto&& check_action_submitbytes_287_15 = (runtime.SubmitBytes(1U,
        std::span<const std::uint8_t>(packet.data(), 5U)));
        CHECK(check_action_submitbytes_287_15
        == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_290_16 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_290_16.status == CommandProcessStatus::Incomplete);
    }
    CHECK(runtime.InspectQueue(1U)->consumerBytePosition == 0U);
    {
        auto&& check_action_submitbytes_292_17 = (runtime.SubmitBytes(1U,
        std::span<const std::uint8_t>(packet.data() + 5U, packet.size() - 5U)));
        CHECK(check_action_submitbytes_292_17
        == SubmitCommandStatus::Accepted);
    }
    const auto before = runtime.InspectQueue(1U);
    CHECK(before && before->unreadBytes == 52U && before->producerBytePosition == 52U);
    {
        auto&& check_action_submitbytes_297_18 = (runtime.SubmitBytes(1U, packet));
        CHECK(check_action_submitbytes_297_18 == SubmitCommandStatus::RingFull);
    }
    CHECK(runtime.InspectQueue(1U)->producerBytePosition == 52U);

    const auto parsed = runtime.ProcessOneCommand();
    CHECK(parsed.status == CommandProcessStatus::Enqueued);
    CHECK(parsed.packetBytePosition == 0U);
    auto dispatch = runtime.ScheduleOneCycle(true);
    CHECK(dispatch.dispatch.status == DispatchCycleStatus::Admitted);
    CHECK(dispatch.admitted.has_value());
    {
        auto&& check_action_completelaunch_306_19 = (CompleteLaunch(scheduler, *dispatch.admitted));
        CHECK(check_action_completelaunch_306_19 == 0);
    }
    const auto firstCompletion = runtime.CollectCompletions();
    CHECK(FindCompletion(firstCompletion, 1U, 7U) != nullptr);

    auto secondPacket = EncodeWorkgroupDispatchPacket(Descriptor(8U));
    {
        auto&& check_action_submitbytes_311_20 = (runtime.SubmitBytes(1U,
        std::span<const std::uint8_t>(secondPacket.data(), 13U)));
        CHECK(check_action_submitbytes_311_20
        == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_314_21 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_314_21.status == CommandProcessStatus::Incomplete);
    }
    CHECK(runtime.InspectQueue(1U)->readPhysicalIndex == 52U);
    {
        auto&& check_action_submitbytes_316_22 = (runtime.SubmitBytes(1U,
        std::span<const std::uint8_t>(secondPacket.data() + 13U,
            secondPacket.size() - 13U)));
        CHECK(check_action_submitbytes_316_22 == SubmitCommandStatus::Accepted);
    }
    CHECK(runtime.InspectQueue(1U)->unreadBytes == 52U);
    const auto wrapped = runtime.ProcessOneCommand();
    CHECK(wrapped.status == CommandProcessStatus::Enqueued);
    CHECK(wrapped.packetBytePosition == 52U);
    CHECK(runtime.InspectQueue(1U)->consumerBytePosition == 104U);
    CHECK(runtime.InspectQueue(1U)->readPhysicalIndex == 40U);
    dispatch = runtime.ScheduleOneCycle(true);
    CHECK(dispatch.dispatch.status == DispatchCycleStatus::Admitted);
    {
        auto&& check_action_completelaunch_327_23 = (CompleteLaunch(scheduler, *dispatch.admitted));
        CHECK(check_action_completelaunch_327_23 == 0);
    }
    {
        auto&& check_action_collectcompletions_328_24 = (runtime.CollectCompletions());
        CHECK(FindCompletion(check_action_collectcompletions_328_24, 1U, 8U) != nullptr);
    }
    CHECK(runtime.PendingByteCountTotal() == 0U);
    return 0;
}

int TestQueueUnregisterWaitsForCompletionIdentity()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig());
    {
        auto&& check_action_registerqueuecontext_337_25 = (runtime.RegisterQueueContext(Context(4U)));
        CHECK(check_action_registerqueuecontext_337_25 == QueueRegistrationStatus::Registered);
    }

    auto malformed = EncodeWorkgroupDispatchPacket(Descriptor(41U));
    malformed[51U] = 1U;
    {
        auto&& check_action_submitbytes_341_26 = (runtime.SubmitBytes(4U, malformed));
        CHECK(check_action_submitbytes_341_26 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_342_27 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_342_27.status == CommandProcessStatus::RejectedMalformed);
    }
    {
        auto&& check_action_unregisterqueuecontext_343_28 = (runtime.UnregisterQueueContext(4U));
        CHECK(check_action_unregisterqueuecontext_343_28 == QueueRegistrationStatus::ContextBusy);
    }

    const auto rejected = runtime.CollectCompletions();
    CHECK(FindCompletion(rejected, 4U, 41U) != nullptr);
    CHECK(rejected.size() == 1U);
    {
        auto&& check_action_unregisterqueuecontext_348_29 = (runtime.UnregisterQueueContext(4U));
        CHECK(check_action_unregisterqueuecontext_348_29 == QueueRegistrationStatus::Unregistered);
    }

    const auto replacementContext = Context(4U, 0x333U, 0x444U);
    {
        auto&& check_action_registerqueuecontext_351_30 = (runtime.RegisterQueueContext(replacementContext));
        CHECK(check_action_registerqueuecontext_351_30
        == QueueRegistrationStatus::Registered);
    }
    CHECK(runtime.InspectQueue(4U)->queueIncarnationId
        != rejected[0].queueIncarnationId);
    {
        auto&& check_action_submitbytes_355_31 = (runtime.SubmitBytes(4U, malformed));
        CHECK(check_action_submitbytes_355_31 == SubmitCommandStatus::Accepted);
    }
    const auto malformedAgain = runtime.ProcessOneCommand();
    CHECK(malformedAgain.status == CommandProcessStatus::RejectedMalformed);
    const auto rejectedAgain = runtime.CollectCompletions();
    CHECK(rejectedAgain.size() == 1U);
    CHECK(rejectedAgain[0].queueContextId == rejected[0].queueContextId);
    CHECK(rejectedAgain[0].submissionId == rejected[0].submissionId);
    CHECK(rejectedAgain[0].packetBytePosition == rejected[0].packetBytePosition);
    CHECK(rejectedAgain[0].internalWorkgroupId == rejected[0].internalWorkgroupId);
    CHECK(rejectedAgain[0].status == rejected[0].status);
    CHECK(rejectedAgain[0].queueIncarnationId != rejected[0].queueIncarnationId);
    {
        auto&& check_action_unregisterqueuecontext_366_32 = (runtime.UnregisterQueueContext(4U));
        CHECK(check_action_unregisterqueuecontext_366_32 == QueueRegistrationStatus::Unregistered);
    }

    {
        auto&& check_action_registerqueuecontext_368_33 = (runtime.RegisterQueueContext(replacementContext));
        CHECK(check_action_registerqueuecontext_368_33
        == QueueRegistrationStatus::Registered);
    }
    const auto packet = EncodeWorkgroupDispatchPacket(Descriptor(41U));
    {
        auto&& check_action_submitbytes_371_34 = (runtime.SubmitBytes(4U, packet));
        CHECK(check_action_submitbytes_371_34 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_372_35 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_372_35.status == CommandProcessStatus::Enqueued);
    }
    const auto dispatch = runtime.ScheduleOneCycle(true);
    CHECK(dispatch.admitted.has_value());
    CHECK(dispatch.admitted->processId == replacementContext.processId);
    CHECK(dispatch.admitted->addressSpaceId == replacementContext.addressSpaceId);
    {
        auto&& check_action_completelaunch_377_36 = (CompleteLaunch(scheduler, *dispatch.admitted));
        CHECK(check_action_completelaunch_377_36 == 0);
    }
    {
        auto&& check_action_collectcompletions_378_37 = (runtime.CollectCompletions());
        CHECK(FindCompletion(check_action_collectcompletions_378_37, 4U, 41U) != nullptr);
    }
    CHECK(runtime.CheckInvariants());
    return 0;
}

int TestTerminalResourceAdmissionRejection()
{
    ComputeUnitDispatchScheduler scheduler(Limits(8U), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig());
    {
        auto&& check_action_registerqueuecontext_387_38 = (runtime.RegisterQueueContext(Context(5U)));
        CHECK(check_action_registerqueuecontext_387_38 == QueueRegistrationStatus::Registered);
    }
    const auto impossible = EncodeWorkgroupDispatchPacket(Descriptor(88U, 0x1000U, 9U));
    {
        auto&& check_action_submitbytes_389_39 = (runtime.SubmitBytes(5U, impossible));
        CHECK(check_action_submitbytes_389_39 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_390_40 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_390_40.status == CommandProcessStatus::Enqueued);
    }
    CHECK(runtime.TrackedWorkgroupCount() == 1U);
    const auto rejected = runtime.ScheduleOneCycle(true);
    CHECK(rejected.dispatch.status == DispatchCycleStatus::Rejected);
    CHECK(rejected.dispatch.failure == AdmissionFailure::WorkgroupExceedsResidentWaveCapacity);
    CHECK(!rejected.admitted.has_value());
    CHECK(runtime.TrackedWorkgroupCount() == 0U);
    const auto completions = runtime.CollectCompletions();
    CHECK(completions.size() == 1U);
    CHECK(completions[0].status == CommandCompletionStatus::AdmissionRejected);
    CHECK(completions[0].submissionId == 88U);
    CHECK(completions[0].admissionFailure
        == AdmissionFailure::WorkgroupExceedsResidentWaveCapacity);
    CHECK(runtime.CheckInvariants() && scheduler.CheckInvariants());
    return 0;
}

int TestUnsupportedMalformedAndQueueFaultRecovery()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig());
    {
        auto&& check_action_registerqueuecontext_411_41 = (runtime.RegisterQueueContext(Context(2U)));
        CHECK(check_action_registerqueuecontext_411_41 == QueueRegistrationStatus::Registered);
    }

    auto unsupported = EncodeWorkgroupDispatchPacket(Descriptor(10U));
    unsupported[6] = 2U;
    {
        auto&& check_action_submitbytes_415_42 = (runtime.SubmitBytes(2U, unsupported));
        CHECK(check_action_submitbytes_415_42 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_416_43 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_416_43.status == CommandProcessStatus::RejectedUnsupported);
    }
    auto completions = runtime.CollectCompletions();
    CHECK(completions.size() == 1U);
    CHECK(completions[0].queueContextId == 2U);
    CHECK(completions[0].status
        == CommandCompletionStatus::UnsupportedCommand);

    auto unsupportedOpcode = EncodeWorkgroupDispatchPacket(Descriptor(14U));
    unsupportedOpcode[4U] = 2U;
    {
        auto&& check_action_submitbytes_425_44 = (runtime.SubmitBytes(2U, unsupportedOpcode));
        CHECK(check_action_submitbytes_425_44 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_426_45 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_426_45.status == CommandProcessStatus::RejectedUnsupported);
    }
    completions = runtime.CollectCompletions();
    CHECK(completions.size() == 1U);
    CHECK(completions[0].status == CommandCompletionStatus::UnsupportedCommand);
    CHECK(completions[0].queueContextId == 2U);

    auto malformedPayload = EncodeWorkgroupDispatchPacket(Descriptor(11U));
    malformedPayload[51] = 1U;
    {
        auto&& check_action_submitbytes_434_46 = (runtime.SubmitBytes(2U, malformedPayload));
        CHECK(check_action_submitbytes_434_46 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_435_47 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_435_47.status == CommandProcessStatus::RejectedMalformed);
    }
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
    {
        auto&& check_action_submitbytes_447_48 = (runtime.SubmitBytes(2U, malformedLength));
        CHECK(check_action_submitbytes_447_48 == SubmitCommandStatus::Accepted);
    }
    const auto consumerBefore = runtime.InspectQueue(2U)->consumerBytePosition;
    {
        auto&& check_action_processonecommand_449_49 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_449_49.status == CommandProcessStatus::QueueFaulted);
    }
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
    {
        auto&& check_action_collectcompletions_460_50 = (runtime.CollectCompletions());
        CHECK(check_action_collectcompletions_460_50.size() == 1U);
    }

    auto malformedMagic = EncodeWorkgroupDispatchPacket(Descriptor(13U));
    malformedMagic[0] = 0U;
    {
        auto&& check_action_submitbytes_464_51 = (runtime.SubmitBytes(2U, malformedMagic));
        CHECK(check_action_submitbytes_464_51 == SubmitCommandStatus::Accepted);
    }
    const auto magicConsumerBefore = runtime.InspectQueue(2U)->consumerBytePosition;
    {
        auto&& check_action_processonecommand_466_52 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_466_52.status == CommandProcessStatus::QueueFaulted);
    }
    CHECK(runtime.InspectQueue(2U)->consumerBytePosition == magicConsumerBefore);
    const auto magicReset = runtime.ResetQueueContext(2U);
    CHECK(magicReset.status == QueueResetStatus::Reset);
    CHECK(magicReset.droppedEndBytePosition - magicReset.droppedBeginBytePosition
        == malformedMagic.size());
    {
        auto&& check_action_collectcompletions_472_53 = (runtime.CollectCompletions());
        CHECK(check_action_collectcompletions_472_53.size() == 1U);
    }
    CHECK(runtime.CheckInvariants() && scheduler.CheckInvariants());
    return 0;
}

int TestContextIdentityAndCompletionCorrelation()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig());
    {
        auto&& check_action_registerqueuecontext_481_54 = (runtime.RegisterQueueContext(Context(3U, 0xaaaU, 0xabcU)));
        CHECK(check_action_registerqueuecontext_481_54
        == QueueRegistrationStatus::Registered);
    }
    {
        auto&& check_action_registerqueuecontext_483_55 = (runtime.RegisterQueueContext(Context(4U, 0xbbbU, 0xdefU)));
        CHECK(check_action_registerqueuecontext_483_55
        == QueueRegistrationStatus::Registered);
    }
    const auto first = EncodeWorkgroupDispatchPacket(Descriptor(99U, 0x1000U));
    const auto second = EncodeWorkgroupDispatchPacket(Descriptor(99U, 0x2000U, 2U));
    {
        auto&& check_action_submitbytes_487_56 = (runtime.SubmitBytes(3U, first));
        CHECK(check_action_submitbytes_487_56 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_submitbytes_488_57 = (runtime.SubmitBytes(4U, second));
        CHECK(check_action_submitbytes_488_57 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_489_58 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_489_58.status == CommandProcessStatus::Enqueued);
    }
    {
        auto&& check_action_processonecommand_490_59 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_490_59.status == CommandProcessStatus::Enqueued);
    }

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
            {
                auto&& check_action_terminatewave_520_60 = (scheduler.Workgroups().TerminateWave(id, wave));
                CHECK(check_action_terminatewave_520_60);
            }
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
    {
        auto&& check_action_registerqueuecontext_537_61 = (runtime.RegisterQueueContext(Context(5U)));
        CHECK(check_action_registerqueuecontext_537_61 == QueueRegistrationStatus::Registered);
    }
    const auto first = EncodeWorkgroupDispatchPacket(Descriptor(20U));
    const auto second = EncodeWorkgroupDispatchPacket(Descriptor(21U));
    {
        auto&& check_action_submitbytes_540_62 = (runtime.SubmitBytes(5U, first));
        CHECK(check_action_submitbytes_540_62 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_submitbytes_541_63 = (runtime.SubmitBytes(5U, second));
        CHECK(check_action_submitbytes_541_63 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_542_64 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_542_64.status == CommandProcessStatus::Enqueued);
    }
    const auto unreadBefore = runtime.InspectQueue(5U)->unreadBytes;
    {
        auto&& check_action_processonecommand_544_65 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_544_65.status == CommandProcessStatus::Backpressure);
    }
    CHECK(runtime.InspectQueue(5U)->unreadBytes == unreadBefore);

    const auto admittedFirst = runtime.ScheduleOneCycle(true);
    CHECK(admittedFirst.dispatch.status == DispatchCycleStatus::Admitted);
    {
        auto&& check_action_processonecommand_549_66 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_549_66.status == CommandProcessStatus::Enqueued);
    }
    const auto blocked = runtime.ScheduleOneCycle(true);
    CHECK(blocked.dispatch.status == DispatchCycleStatus::Deferred);
    {
        auto&& check_action_collectcompletions_552_67 = (runtime.CollectCompletions());
        CHECK(check_action_collectcompletions_552_67.empty());
    }
    {
        auto&& check_action_completelaunch_553_68 = (CompleteLaunch(scheduler, *admittedFirst.admitted));
        CHECK(check_action_completelaunch_553_68 == 0);
    }
    {
        auto&& check_action_collectcompletions_554_69 = (runtime.CollectCompletions());
        CHECK(FindCompletion(check_action_collectcompletions_554_69, 5U, 20U) != nullptr);
    }
    const auto admittedSecond = runtime.ScheduleOneCycle(true);
    CHECK(admittedSecond.dispatch.status == DispatchCycleStatus::Admitted);
    {
        auto&& check_action_completelaunch_557_70 = (CompleteLaunch(scheduler, *admittedSecond.admitted));
        CHECK(check_action_completelaunch_557_70 == 0);
    }
    {
        auto&& check_action_collectcompletions_558_71 = (runtime.CollectCompletions());
        CHECK(FindCompletion(check_action_collectcompletions_558_71, 5U, 21U) != nullptr);
    }
    return 0;
}

int TestCompletionTrackingCapacityBackpressure()
{
    ComputeUnitDispatchScheduler scheduler(Limits(), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig(4096U, 1U));
    {
        auto&& check_action_registerqueuecontext_566_72 = (runtime.RegisterQueueContext(Context(5U)));
        CHECK(check_action_registerqueuecontext_566_72 == QueueRegistrationStatus::Registered);
    }
    const auto firstPacket = EncodeWorkgroupDispatchPacket(Descriptor(51U));
    const auto secondPacket = EncodeWorkgroupDispatchPacket(Descriptor(52U));
    {
        auto&& check_action_submitbytes_569_73 = (runtime.SubmitBytes(5U, firstPacket));
        CHECK(check_action_submitbytes_569_73 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_submitbytes_570_74 = (runtime.SubmitBytes(5U, secondPacket));
        CHECK(check_action_submitbytes_570_74 == SubmitCommandStatus::Accepted);
    }

    {
        auto&& check_action_processonecommand_572_75 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_572_75.status == CommandProcessStatus::Enqueued);
    }
    CHECK(runtime.TrackedWorkgroupCount() == 1U);
    {
        auto&& check_action_processonecommand_574_76 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_574_76.status == CommandProcessStatus::Backpressure);
    }
    CHECK(runtime.InspectQueue(5U)->unreadBytes == secondPacket.size());

    auto dispatch = runtime.ScheduleOneCycle(true);
    CHECK(dispatch.admitted.has_value());
    {
        auto&& check_action_completelaunch_579_77 = (CompleteLaunch(scheduler, *dispatch.admitted));
        CHECK(check_action_completelaunch_579_77 == 0);
    }
    {
        auto&& check_action_collectcompletions_580_78 = (runtime.CollectCompletions());
        CHECK(FindCompletion(check_action_collectcompletions_580_78, 5U, 51U) != nullptr);
    }
    CHECK(runtime.TrackedWorkgroupCount() == 0U);

    {
        auto&& check_action_processonecommand_583_79 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_583_79.status == CommandProcessStatus::Enqueued);
    }
    dispatch = runtime.ScheduleOneCycle(true);
    CHECK(dispatch.admitted.has_value());
    {
        auto&& check_action_completelaunch_586_80 = (CompleteLaunch(scheduler, *dispatch.admitted));
        CHECK(check_action_completelaunch_586_80 == 0);
    }
    {
        auto&& check_action_collectcompletions_587_81 = (runtime.CollectCompletions());
        CHECK(FindCompletion(check_action_collectcompletions_587_81, 5U, 52U) != nullptr);
    }
    CHECK(runtime.CheckInvariants());
    return 0;
}

int TestQueueScopedResetAndQuiescentCancellation()
{
    ComputeUnitDispatchScheduler scheduler(Limits(3U), DispatchConfig());
    CommandQueueRuntime runtime(scheduler, ProcessorConfig());
    {
        auto&& check_action_registerqueuecontext_596_82 = (runtime.RegisterQueueContext(Context(6U)));
        CHECK(check_action_registerqueuecontext_596_82 == QueueRegistrationStatus::Registered);
    }
    {
        auto&& check_action_registerqueuecontext_597_83 = (runtime.RegisterQueueContext(Context(7U)));
        CHECK(check_action_registerqueuecontext_597_83 == QueueRegistrationStatus::Registered);
    }

    {
        auto&& check_action_submitbytes_599_84 = (runtime.SubmitBytes(6U,
        EncodeWorkgroupDispatchPacket(Descriptor(30U))));
        CHECK(check_action_submitbytes_599_84 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_601_85 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_601_85.status == CommandProcessStatus::Enqueued);
    }
    const auto active = runtime.ScheduleOneCycle(true);
    CHECK(active.dispatch.status == DispatchCycleStatus::Admitted);
    {
        auto&& check_action_beginwaveexecution_604_86 = (scheduler.Workgroups().BeginWaveExecution(active.admitted->workgroupId, 0U));
        CHECK(check_action_beginwaveexecution_604_86);
    }

    {
        auto&& check_action_submitbytes_606_87 = (runtime.SubmitBytes(6U,
        EncodeWorkgroupDispatchPacket(Descriptor(31U))));
        CHECK(check_action_submitbytes_606_87 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_608_88 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_608_88.status == CommandProcessStatus::Enqueued);
    }
    const std::array<std::uint8_t, 3> partial{1U, 2U, 3U};
    {
        auto&& check_action_submitbytes_610_89 = (runtime.SubmitBytes(6U, partial));
        CHECK(check_action_submitbytes_610_89 == SubmitCommandStatus::Accepted);
    }
    const auto reset = runtime.ResetQueueContext(6U);
    CHECK(reset.status == QueueResetStatus::Reset);
    CHECK(reset.immediateCompletions.size() == 1U);
    CHECK(FindCompletion(reset.immediateCompletions, 6U, 31U) != nullptr);
    CHECK(FindCompletion(reset.immediateCompletions, 6U, 31U)->status
        == CommandCompletionStatus::Cancelled);
    CHECK(reset.droppedEndBytePosition - reset.droppedBeginBytePosition == 3U);
    CHECK(runtime.InspectQueue(6U)->unreadBytes == 0U);
    CHECK(scheduler.Workgroups().WorkgroupCount() == 1U);
    {
        auto&& check_action_collectcompletions_620_90 = (runtime.CollectCompletions());
        CHECK(check_action_collectcompletions_620_90.empty());
    }

    {
        auto&& check_action_submitbytes_622_91 = (runtime.SubmitBytes(7U,
        EncodeWorkgroupDispatchPacket(Descriptor(40U))));
        CHECK(check_action_submitbytes_622_91 == SubmitCommandStatus::Accepted);
    }
    {
        auto&& check_action_processonecommand_624_92 = (runtime.ProcessOneCommand());
        CHECK(check_action_processonecommand_624_92.status == CommandProcessStatus::Enqueued);
    }
    const auto other = runtime.ScheduleOneCycle(true);
    CHECK(other.dispatch.status == DispatchCycleStatus::Admitted);
    CHECK(other.admitted->queueContextId == 7U);
    {
        auto&& check_action_completelaunch_628_93 = (CompleteLaunch(scheduler, *other.admitted));
        CHECK(check_action_completelaunch_628_93 == 0);
    }
    {
        auto&& check_action_collectcompletions_629_94 = (runtime.CollectCompletions());
        CHECK(FindCompletion(check_action_collectcompletions_629_94, 7U, 40U) != nullptr);
    }

    {
        auto&& check_action_completewaveexecution_631_95 = (scheduler.Workgroups().CompleteWaveExecution(active.admitted->workgroupId, 0U));
        CHECK(check_action_completewaveexecution_631_95);
    }
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
        {
            auto&& check_action_registerqueuecontext_645_96 = (runtime.RegisterQueueContext(Context(context)));
            CHECK(check_action_registerqueuecontext_645_96 == QueueRegistrationStatus::Registered);
        }

    constexpr std::uint32_t seed = 0x43475831U;
    std::mt19937 random(seed);
    std::map<std::uint64_t, std::uint32_t> active;
    std::uint32_t completionsSeen = 0U;
    for (std::uint32_t cycle = 0U; cycle < 1800U; ++cycle)
    {
        const auto action = random() % 5U;
        const auto context = static_cast<std::uint8_t>(random() % 4U);
        ::cgx1::testing::SetRandomTestFailureContext(
            "TestRandomizedQueueDispatchAndReuse", seed, cycle,
            (static_cast<std::uint64_t>(action) << 8U) | context);
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
                    {
                        auto&& check_action_terminatewave_691_97 = (scheduler.Workgroups().TerminateWave(iterator->first, wave));
                        CHECK(check_action_terminatewave_691_97);
                    }
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
        ::cgx1::testing::SetRandomTestFailureContext(
            "TestRandomizedQueueDispatchAndReuseDrain", seed, 1800U + cycle,
            runtime.PendingByteCountTotal());
        (void)runtime.ProcessOneCommand();
        const auto scheduled = runtime.ScheduleOneCycle(true);
        if (scheduled.admitted)
        {
            for (std::uint32_t wave = 0U;
                wave < static_cast<std::uint32_t>(scheduled.admitted->descriptor.waves.size());
                ++wave)
            {
                {
                    auto&& check_action_terminatewave_717_98 = (scheduler.Workgroups().TerminateWave(
                    scheduled.admitted->workgroupId, wave));
                    CHECK(check_action_terminatewave_717_98);
                }
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
    ::cgx1::testing::SetRandomTestFailureContext(
        "TestRandomizedQueueDispatchAndReuseFinal", seed, 6800U,
        runtime.PendingByteCountTotal());
    CHECK(runtime.TrackedWorkgroupCount() == 0U);
    CHECK(completionsSeen != 0U);
    ::cgx1::testing::ClearRandomTestFailureContext();
    return 0;
}

} // namespace

int main()
{
    if (TestPacketCodecAndValidation() != 0
        || TestCommandProcessorPolicyBoundaries() != 0
        || TestReservedFlagsConsumeCompleteFramedPacket() != 0
        || TestDuplicateSubmissionTokensSameContext() != 0
        || TestBoundedRingBackpressureAndPhysicalWrap() != 0
        || TestUnsupportedMalformedAndQueueFaultRecovery() != 0
        || TestQueueUnregisterWaitsForCompletionIdentity() != 0
        || TestContextIdentityAndCompletionCorrelation() != 0
        || TestTerminalResourceAdmissionRejection() != 0
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
