// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_context.hpp"
#include "shared_local_memory.hpp"

#include <array>
#include <cstdint>
#include <iostream>
#include <optional>
#include <random>
#include <stdexcept>
#include <string>
#include <string_view>

namespace
{
using cgx1::memory::AccessKind;
using cgx1::memory::AllocationStatus;
using cgx1::memory::CuSharedLocalMemory;
using cgx1::memory::MemoryFault;
using cgx1::memory::MemoryRequest;
using cgx1::memory::MemoryResponse;
using cgx1::memory::SubmitStatus;

void Check(bool condition, std::string_view message)
{
    if (!condition)
    {
        std::cerr << "[fail] " << message;
        ::cgx1::testing::WriteRandomTestFailureContext(std::cerr);
        std::cerr << '\n';
        throw std::runtime_error(std::string(message));
    }
}

MemoryRequest Request(
    std::uint64_t workgroup,
    std::uint32_t wave,
    std::uint64_t tag,
    AccessKind kind,
    std::uint32_t mask,
    const std::array<std::uint32_t, 32>& addresses,
    const std::array<std::uint32_t, 32>& data = {})
{
    return {workgroup, wave, tag, kind, mask, addresses, data};
}

MemoryResponse Complete(CuSharedLocalMemory& memory)
{
    for (std::uint32_t cycle = 0; cycle < 128U; ++cycle)
    {
        if (auto response = memory.TakeResponse())
            return *response;
        (void)memory.ServiceCycle();
    }
    throw std::runtime_error("shared-memory transaction failed to complete");
}

void TestAllocationIsolationAndReuse()
{
    CuSharedLocalMemory memory(128U, 32U, 4U);
    Check(memory.AllocateWorkgroup(10U, 64U) == AllocationStatus::Allocated,
        "first workgroup allocation failed");
    Check(memory.AllocateWorkgroup(20U, 64U) == AllocationStatus::Allocated,
        "second workgroup allocation failed");
    Check(memory.AllocatedBytes() == 128U, "allocated byte accounting is wrong");

    std::array<std::uint32_t, 32> addresses{};
    std::array<std::uint32_t, 32> data{};
    addresses[0] = 0U;
    addresses[1] = 4U;
    data[0] = 0x12345678U;
    data[1] = 0xabcdef01U;
    auto store = Request(10U, 0U, 1U, AccessKind::Store, 0x3U, addresses, data);
    Check(memory.Submit(store).status == SubmitStatus::Accepted,
        "valid store was rejected");
    Check(memory.IsWaveWaiting(10U, 0U), "accepted store did not block its wave");
    Check(!memory.ReleaseWorkgroup(10U), "in-flight workgroup memory was released");
    Check(Complete(memory).transactionTag == 1U, "store response tag changed");
    Check(!memory.IsWaveWaiting(10U, 0U), "consumed store response left a wave blocked");

    const auto otherLoad = Request(20U, 1U, 2U, AccessKind::Load, 0x3U, addresses);
    Check(memory.Submit(otherLoad).status == SubmitStatus::Accepted,
        "load from independent workgroup was rejected");
    const auto otherResponse = Complete(memory);
    Check(otherResponse.laneData[0] == 0U && otherResponse.laneData[1] == 0U,
        "workgroup observed another workgroup's shared data");

    const auto ownLoad = Request(10U, 2U, 3U, AccessKind::Load, 0x3U, addresses);
    Check(memory.Submit(ownLoad).status == SubmitStatus::Accepted,
        "load from owning workgroup was rejected");
    const auto ownResponse = Complete(memory);
    Check(ownResponse.laneData[0] == data[0] && ownResponse.laneData[1] == data[1],
        "shared-memory load returned incorrect lane data");

    Check(memory.ReleaseWorkgroup(10U), "quiescent workgroup release failed");
    Check(memory.AllocateWorkgroup(30U, 64U) == AllocationStatus::Allocated,
        "released range could not be reused");
    const auto reusedLoad = Request(30U, 0U, 4U, AccessKind::Load, 1U, addresses);
    Check(memory.Submit(reusedLoad).status == SubmitStatus::Accepted,
        "load from reused range was rejected");
    Check(Complete(memory).laneData[0] == 0U,
        "reallocated shared memory exposed stale workgroup data");
}

void TestCapacityAndFragmentation()
{
    CuSharedLocalMemory memory(128U, 8U, 4U);
    Check(memory.AllocateWorkgroup(1U, 32U) == AllocationStatus::Allocated,
        "initial region allocation failed");
    Check(memory.AllocateWorkgroup(2U, 32U) == AllocationStatus::Allocated,
        "second region allocation failed");
    Check(memory.AllocateWorkgroup(3U, 32U) == AllocationStatus::Allocated,
        "third region allocation failed");
    Check(memory.AllocateWorkgroup(4U, 129U) == AllocationStatus::ExceedsCapacity,
        "single region larger than the CU was not rejected");
    Check(memory.AllocateWorkgroup(4U, 33U) == AllocationStatus::CapacityUnavailable,
        "aggregate over-capacity demand was not rejected");
    Check(memory.ReleaseWorkgroup(2U), "middle region release failed");
    Check(memory.AllocateWorkgroup(4U, 48U) == AllocationStatus::CapacityFragmented,
        "fragmented capacity was reported as contiguous");
    Check(memory.AllocateWorkgroup(4U, 32U) == AllocationStatus::Allocated,
        "available contiguous hole was not reused");

    CuSharedLocalMemory oneContext(16U, 4U, 1U);
    Check(oneContext.AllocateWorkgroup(8U, 8U) == AllocationStatus::Allocated,
        "single context setup allocation failed");
    Check(oneContext.AllocateWorkgroup(9U, 0U) == AllocationStatus::WorkgroupContextsFull,
        "workgroup context limit was not enforced");
}

void TestBankServiceAndWaitLifecycle()
{
    CuSharedLocalMemory memory(256U, 32U, 4U);
    Check(memory.AllocateWorkgroup(7U, 256U) == AllocationStatus::Allocated,
        "allocation failed");
    std::array<std::uint32_t, 32> addresses{};
    addresses[0] = 0U;
    addresses[1] = 128U; // word 32 aliases bank 0.
    const auto request = Request(7U, 0U, 99U, AccessKind::Store, 0x3U, addresses);
    Check(memory.Submit(request).status == SubmitStatus::Accepted,
        "bank-conflicting request was rejected");
    Check(memory.ServiceCycle() == 1U,
        "one bank serviced multiple colliding lanes in one cycle");
    Check(memory.IsWaveWaiting(7U, 0U), "wave stopped waiting before bank service completed");
    Check(memory.ServiceCycle() == 1U, "second colliding lane was not serviced");
    Check(memory.IsWaveWaiting(7U, 0U), "wave resumed before response consumption");
    const auto response = memory.TakeResponse();
    Check(response.has_value() && response->transactionTag == 99U,
        "completed request did not return its tag");
    Check(!memory.IsWaveWaiting(7U, 0U), "wave stayed blocked after response consumption");

    addresses[0] = 4U;
    addresses[1] = 8U;
    Check(memory.Submit(Request(7U, 0U, 100U, AccessKind::Store, 0x3U, addresses)).status
            == SubmitStatus::Accepted,
        "independent-bank request was rejected");
    Check(memory.ServiceCycle() == 2U,
        "independent banks did not service their lanes in parallel");
    Check(memory.TakeResponse().has_value(), "parallel request did not complete");
}

void TestBankArbitrationProgress()
{
    CuSharedLocalMemory memory(128U, 1U, 4U);
    Check(memory.AllocateWorkgroup(11U, 64U) == AllocationStatus::Allocated,
        "first requester allocation failed");
    std::array<std::uint32_t, 32> firstAddresses{};
    firstAddresses[0] = 0U;
    firstAddresses[1] = 4U;
    std::array<std::uint32_t, 32> secondAddresses{};
    secondAddresses[0] = 8U;
    Check(memory.Submit(Request(
        11U, 0U, 201U, AccessKind::Store, 0x3U, firstAddresses)).status
            == SubmitStatus::Accepted,
        "first competing request was rejected");
    Check(memory.Submit(Request(
        11U, 1U, 202U, AccessKind::Store, 0x1U, secondAddresses)).status
            == SubmitStatus::Accepted,
        "second competing request was rejected");
    Check(memory.ServiceCycle() == 1U, "single bank serviced more than one lane");
    Check(memory.ServiceCycle() == 1U, "round-robin requester did not receive service");
    const auto secondResponse = memory.TakeResponse();
    Check(secondResponse.has_value() && secondResponse->transactionTag == 202U,
        "older conflicting request starved the second requester");
    Check(memory.ServiceCycle() == 1U, "older request did not resume after its peer");
    const auto firstResponse = memory.TakeResponse();
    Check(firstResponse.has_value() && firstResponse->transactionTag == 201U,
        "first requester response was lost or retagged");
}

void TestFaultAtomicityAndLaneMask()
{
    CuSharedLocalMemory memory(64U, 4U, 2U);
    Check(memory.AllocateWorkgroup(50U, 8U) == AllocationStatus::Allocated,
        "small allocation failed");
    std::array<std::uint32_t, 32> addresses{};
    std::array<std::uint32_t, 32> data{};
    addresses[0] = 0U;
    addresses[1] = 8U;
    data[0] = 0x55aa55aaU;
    data[1] = 0xdeadbeefU;
    const auto fault = memory.Submit(
        Request(50U, 0U, 1U, AccessKind::Store, 0x3U, addresses, data));
    Check(fault.status == SubmitStatus::Accepted
            && fault.fault == MemoryFault::OutOfBounds && fault.faultLane == 1U,
        "out-of-range lane did not report a precise fault");
    Check(memory.PendingRequestCount() == 0U,
        "faulting request entered bank service");
    Check(memory.IsWaveWaiting(50U, 0U),
        "faulting request did not retain its tagged completion");
    const auto boundsResponse = Complete(memory);
    Check(boundsResponse.fault == MemoryFault::OutOfBounds
            && boundsResponse.faultLane == 1U,
        "out-of-range fault response lost its lane tag");
    const auto afterBoundsFault = Request(
        50U, 1U, 20U, AccessKind::Load, 0x1U, addresses);
    Check(memory.Submit(afterBoundsFault).status == SubmitStatus::Accepted,
        "post-fault atomicity check load was rejected");
    Check(Complete(memory).laneData[0] == 0U,
        "valid lane was partially stored before a later lane fault");

    addresses[1] = 2U;
    const auto misaligned = memory.Submit(
        Request(50U, 0U, 2U, AccessKind::Store, 0x3U, addresses, data));
    Check(misaligned.status == SubmitStatus::Accepted
            && misaligned.fault == MemoryFault::MisalignedAddress
            && misaligned.faultLane == 1U,
        "misaligned lane did not report a precise fault");
    Check(memory.PendingRequestCount() == 0U,
        "misaligned request caused a side effect");
    Check(Complete(memory).fault == MemoryFault::MisalignedAddress,
        "misaligned fault response was lost");

    addresses[1] = 8U; // Invalid but inactive: it must not fault or access memory.
    Check(memory.Submit(
        Request(50U, 0U, 3U, AccessKind::Store, 0x1U, addresses, data)).status
            == SubmitStatus::Accepted,
        "inactive invalid lane incorrectly faulted");
    Check(memory.ServiceCycle() == 1U, "active lane did not service");
    Check(memory.TakeResponse().has_value(), "masked store did not complete");
    addresses[0] = 0U;
    const auto load = Request(50U, 1U, 4U, AccessKind::Load, 1U, addresses);
    Check(memory.Submit(load).status == SubmitStatus::Accepted,
        "verification load was rejected");
    Check(Complete(memory).laneData[0] == data[0],
        "valid lane store was lost after a later-lane fault");
}

void TestDuplicateWaveTagCancellationAndReset()
{
    CuSharedLocalMemory memory(128U, 8U, 3U);
    Check(memory.AllocateWorkgroup(70U, 128U) == AllocationStatus::Allocated,
        "allocation failed");
    const auto unknown = memory.Submit(
        Request(69U, 0U, 9U, AccessKind::Load, 1U, {}));
    Check(unknown.status == SubmitStatus::Accepted
            && unknown.fault == MemoryFault::UnknownWorkgroup,
        "unknown workgroup did not produce a tagged memory fault");
    Check(Complete(memory).fault == MemoryFault::UnknownWorkgroup,
        "unknown workgroup fault response was lost");
    std::array<std::uint32_t, 32> addresses{};
    addresses[0] = 0U;
    addresses[1] = 32U;
    Check(memory.Submit(Request(70U, 3U, 10U, AccessKind::Load, 0x3U, addresses)).status
            == SubmitStatus::Accepted,
        "initial load was rejected");
    Check(memory.Submit(Request(70U, 3U, 11U, AccessKind::Load, 1U, addresses)).status
            == SubmitStatus::WaveBusy,
        "one wave accepted two outstanding memory operations");
    Check(memory.Submit(Request(70U, 4U, 10U, AccessKind::Load, 1U, addresses)).status
            == SubmitStatus::DuplicateTransactionTag,
        "duplicate outstanding transaction tag was accepted");
    Check(memory.CancelWave(70U, 3U), "terminal wave transaction was not cancelled");
    Check(!memory.ReleaseWorkgroup(70U),
        "workgroup storage was released before accepted memory service drained");
    (void)memory.ServiceCycle();
    (void)memory.ServiceCycle();
    Check(memory.PendingRequestCount() == 0U,
        "cancelled request did not drain accepted memory service");
    Check(!memory.IsWaveWaiting(70U, 3U), "cancelled drained wave remained blocked");
    Check(!memory.TakeResponse().has_value(), "cancelled wave received a stale response");
    Check(memory.ReleaseWorkgroup(70U), "drained workgroup could not release storage");

    Check(memory.AllocateWorkgroup(71U, 128U) == AllocationStatus::Allocated,
        "reallocation after drain failed");
    Check(memory.Submit(Request(71U, 0U, 20U, AccessKind::Load, 1U, addresses)).status
            == SubmitStatus::Accepted,
        "pre-reset verification load was rejected");
    memory.Reset();
    Check(memory.AllocatedBytes() == 0U && memory.PendingRequestCount() == 0U,
        "reset retained capacity or request ownership");
    Check(!memory.IsWaveWaiting(71U, 0U), "reset retained wave memory wait state");
    Check(!memory.TakeResponse().has_value(), "reset retained an old response");
    Check(memory.AllocateWorkgroup(72U, 128U) == AllocationStatus::Allocated,
        "full capacity could not be reused after reset");
}

void TestRandomizedBankedTransactions()
{
    constexpr std::uint32_t seed = 0xC0FFEEU;
    std::mt19937 random(seed);
    CuSharedLocalMemory memory(4096U, 32U, 8U);
    for (std::uint64_t group = 1U; group <= 4U; ++group)
        Check(memory.AllocateWorkgroup(group, 512U) == AllocationStatus::Allocated,
            "randomized setup allocation failed");

    std::uint64_t tag = 1U;
    std::uint32_t completions = 0U;
    for (std::uint32_t cycle = 0U; cycle < 5000U; ++cycle)
    {
        ::cgx1::testing::SetRandomTestFailureContext(
            "TestRandomizedBankedTransactions", seed, cycle);
        for (std::uint32_t attempt = 0U; attempt < 4U; ++attempt)
        {
            const auto group = std::uint64_t{1U} + (random() % 4U);
            const auto wave = static_cast<std::uint32_t>(random() % 8U);
            std::array<std::uint32_t, 32> addresses{};
            std::array<std::uint32_t, 32> data{};
            std::uint32_t mask = 0U;
            for (std::uint32_t lane = 0U; lane < 32U; ++lane)
            {
                if ((random() & 3U) == 0U)
                {
                    mask |= std::uint32_t{1} << lane;
                    addresses[lane] = 4U * (random() % 128U);
                    data[lane] = static_cast<std::uint32_t>(random());
                }
            }
            const auto kind = (random() & 1U) == 0U
                ? AccessKind::Load : AccessKind::Store;
            ::cgx1::testing::SetRandomTestFailureContext(
                "TestRandomizedBankedTransactions", seed, cycle,
                (group << 32U) | (static_cast<std::uint64_t>(wave) << 8U)
                    | (kind == AccessKind::Store ? 1U : 0U));
            const auto status = memory.Submit(Request(
                group, wave, tag++, kind, mask, addresses, data)).status;
            Check(status == SubmitStatus::Accepted || status == SubmitStatus::WaveBusy,
                "randomized valid request reported an unexpected fault");
        }
        (void)memory.ServiceCycle();
        if (memory.TakeResponse())
            ++completions;
        Check(memory.AllocatedBytes() == 2048U,
            "randomized service changed workgroup allocation accounting");
    }
    for (std::uint32_t cycle = 0U; cycle < 128U && memory.PendingRequestCount() != 0U; ++cycle)
    {
        (void)memory.ServiceCycle();
        if (memory.TakeResponse())
            ++completions;
    }
    while (memory.TakeResponse())
        ++completions;
    Check(completions != 0U, "randomized sequence completed no memory requests");
    Check(memory.PendingRequestCount() == 0U,
        "randomized memory requests did not drain");
    for (std::uint64_t group = 1U; group <= 4U; ++group)
        Check(memory.ReleaseWorkgroup(group), "randomized quiescent release failed");
    ::cgx1::testing::ClearRandomTestFailureContext();
}
} // namespace

int main()
{
    try
    {
        TestAllocationIsolationAndReuse();
        TestCapacityAndFragmentation();
        TestBankServiceAndWaitLifecycle();
        TestBankArbitrationProgress();
        TestFaultAtomicityAndLaneMask();
        TestDuplicateWaveTagCancellationAndReset();
        TestRandomizedBankedTransactions();
    }
    catch (const std::exception& error)
    {
        std::cerr << "Shared/local-memory model test failed: " << error.what() << '\n';
        return 1;
    }

    std::cout << "Shared/local-memory model checks passed.\n";
    return 0;
}
