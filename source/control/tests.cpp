// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_wave_control.hpp"

#include <cstdint>
#include <iostream>
#include <random>

using namespace cgx1::control;

#define CHECK(x) do { if (!(x)) { std::cerr << "[fail] " #x " line " << __LINE__ << '\n'; return false; } } while (false)

bool TestUniformBranch()
{
    auto state = InitializeWaveControl(0x1000U, 0xFU);
    const auto result = ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Branch,
        .targetPc = 0x2000U,
        .fallthroughPc = 0x1010U,
        .joinPc = 0x2020U,
        .takenMask = 0xFU});
    CHECK(result.accepted && !result.becameTerminal);
    CHECK(state.pc == 0x2000U && state.activeMask == 0xFU && state.liveMask == 0xFU);
    CHECK(state.controlStack.empty());
    return true;
}

bool TestDivergentBranchJoin()
{
    auto state = InitializeWaveControl(0x1000U, 0xFU);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2000U,
        .fallthroughPc = 0x3000U, .joinPc = 0x4000U, .takenMask = 0x3U}).accepted);
    CHECK(state.pc == 0x2000U && state.activeMask == 0x3U && state.controlStack.size() == 1U);
    CHECK(AdvanceAcceptedInstruction(state, 0x4000U).accepted);
    CHECK(state.pc == 0x3000U && state.activeMask == 0xCU);
    CHECK(state.controlStack.back().waitingMask == 0x3U);
    CHECK(AdvanceAcceptedInstruction(state, 0x4000U).accepted);
    CHECK(state.pc == 0x4000U && state.activeMask == 0xFU && state.controlStack.empty());
    return true;
}

bool TestNestedJoinAndTermination()
{
    auto state = InitializeWaveControl(0x1000U, 0xFU);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x1004U,
        .fallthroughPc = 0x2000U, .joinPc = 0x3000U, .takenMask = 0x3U}).accepted);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x1008U,
        .fallthroughPc = 0x1010U, .joinPc = 0x1020U, .takenMask = 0x1U}).accepted);
    const auto terminated = ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::Terminate});
    CHECK(terminated.accepted && !terminated.becameTerminal);
    CHECK(state.liveMask == 0xEU && state.activeMask == 0x2U && state.pc == 0x1010U);
    CHECK(AdvanceAcceptedInstruction(state, 0x1020U).accepted);
    CHECK(state.activeMask == 0x2U && state.liveMask == 0xEU && state.controlStack.size() == 1U);
    CHECK(AdvanceAcceptedInstruction(state, 0x3000U).accepted);
    CHECK(state.pc == 0x2000U && state.activeMask == 0xCU);
    CHECK(state.controlStack.back().waitingMask == 0x2U);
    CHECK(AdvanceAcceptedInstruction(state, 0x3000U).accepted);
    CHECK(state.activeMask == 0xEU && state.liveMask == 0xEU && state.pc == 0x3000U);
    return true;
}

bool TestCallReturn()
{
    auto state = InitializeWaveControl(0x1000U, 0xFU);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x5000U, .returnPc = 0x1010U}).accepted);
    CHECK(state.pc == 0x5000U && state.callStack.size() == 1U);
    CHECK(ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::Return}).accepted);
    CHECK(state.pc == 0x1010U && state.callStack.empty());
    return true;
}

bool TestStaggeredLoopExit()
{
    auto state = InitializeWaveControl(0x1000U, 0xFU);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopBegin, .loopTestPc = 0x1004U,
        .loopBodyPc = 0x1008U, .loopExitPc = 0x1010U}).accepted);
    CHECK(state.pc == 0x1004U && state.controlStack.size() == 1U);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopTest, .continueMask = 0xEU}).accepted);
    CHECK(state.pc == 0x1008U && state.activeMask == 0xEU);
    CHECK(state.controlStack.back().waitingMask == 0x1U);
    CHECK(ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::LoopBackedge}).accepted);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopTest, .continueMask = 0xCU}).accepted);
    CHECK(state.activeMask == 0xCU && state.controlStack.back().waitingMask == 0x3U);
    CHECK(ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::LoopBackedge}).accepted);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopTest, .continueMask = 0U}).accepted);
    CHECK(state.pc == 0x1010U && state.activeMask == 0xFU && state.controlStack.empty());
    return true;
}

bool TestLoopNestedInBranchTermination()
{
    auto state = InitializeWaveControl(0x1000U, 0xFU);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2000U,
        .fallthroughPc = 0x3000U, .joinPc = 0x4000U, .takenMask = 0x3U}).accepted);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopBegin, .loopTestPc = 0x2010U,
        .loopBodyPc = 0x2020U, .loopExitPc = 0x2040U}).accepted);
    CHECK(state.controlStack.size() == 2U);
    CHECK(state.controlStack[0].kind == ControlFrameKind::Branch);
    CHECK(state.controlStack[1].kind == ControlFrameKind::Loop);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopTest, .continueMask = 0x2U}).accepted);
    CHECK(state.activeMask == 0x2U && state.controlStack.back().waitingMask == 0x1U);
    const auto terminated = ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::Terminate});
    CHECK(terminated.accepted && !terminated.becameTerminal);
    CHECK(state.liveMask == 0xDU && state.activeMask == 0x1U && state.pc == 0x2040U);
    CHECK(state.controlStack.size() == 1U && state.controlStack.back().kind == ControlFrameKind::Branch);
    CHECK(AdvanceAcceptedInstruction(state, 0x4000U).accepted);
    CHECK(state.pc == 0x3000U && state.activeMask == 0xCU);
    CHECK(AdvanceAcceptedInstruction(state, 0x4000U).accepted);
    CHECK(state.pc == 0x4000U && state.activeMask == 0xDU && state.liveMask == 0xDU);
    return true;
}

bool TestLoopUnwindRestoresCallDepth()
{
    auto state = InitializeWaveControl(0x1000U, 0xFU);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x2000U, .returnPc = 0x1010U}).accepted);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopBegin, .loopTestPc = 0x2010U,
        .loopBodyPc = 0x2020U, .loopExitPc = 0x2040U}).accepted);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopTest, .continueMask = 0xEU}).accepted);
    CHECK(state.activeMask == 0xEU && state.controlStack.back().waitingMask == 0x1U);
    CHECK(ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x3000U, .returnPc = 0x2030U}).accepted);
    CHECK(ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::Terminate}).accepted);
    CHECK(state.activeMask == 0x1U && state.pc == 0x2040U);
    CHECK(state.callStack.size() == 1U);
    CHECK(ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::Return}).accepted);
    CHECK(state.pc == 0x1010U && state.callStack.empty());
    return true;
}

bool TestMalformedOuterJoinAndProtectedReturns()
{
    auto branchWithOpenLoop = InitializeWaveControl(0x1000U, 0xFU);
    CHECK(ApplyControlEvent(branchWithOpenLoop, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2000U,
        .fallthroughPc = 0x3000U, .joinPc = 0x4000U, .takenMask = 0x3U}).accepted);
    CHECK(ApplyControlEvent(branchWithOpenLoop, ControlEvent{
        .kind = ControlEventKind::LoopBegin, .loopTestPc = 0x2010U,
        .loopBodyPc = 0x2020U, .loopExitPc = 0x2040U}).accepted);
    auto result = AdvanceAcceptedInstruction(branchWithOpenLoop, 0x4000U);
    CHECK(result.becameTerminal && branchWithOpenLoop.lastFault == ControlFault::MalformedJoin);

    auto branchWithOpenBranch = InitializeWaveControl(0x1000U, 0xFU);
    CHECK(ApplyControlEvent(branchWithOpenBranch, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2000U,
        .fallthroughPc = 0x3000U, .joinPc = 0x4000U, .takenMask = 0x3U}).accepted);
    CHECK(ApplyControlEvent(branchWithOpenBranch, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2010U,
        .fallthroughPc = 0x2020U, .joinPc = 0x2030U, .takenMask = 0x1U}).accepted);
    result = AdvanceAcceptedInstruction(branchWithOpenBranch, 0x4000U);
    CHECK(result.becameTerminal && branchWithOpenBranch.lastFault == ControlFault::MalformedJoin);

    auto protectedCaller = InitializeWaveControl(0x1000U, 0xFU);
    CHECK(ApplyControlEvent(protectedCaller, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x2000U, .returnPc = 0x1010U}).accepted);
    CHECK(ApplyControlEvent(protectedCaller, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2010U,
        .fallthroughPc = 0x2020U, .joinPc = 0x2030U, .takenMask = 0x3U}).accepted);
    result = ApplyControlEvent(protectedCaller, ControlEvent{.kind = ControlEventKind::Return});
    CHECK(result.becameTerminal && protectedCaller.lastFault == ControlFault::UnbalancedControl);

    auto loopWithOpenCall = InitializeWaveControl(0x1000U, 0xFU);
    CHECK(ApplyControlEvent(loopWithOpenCall, ControlEvent{
        .kind = ControlEventKind::LoopBegin, .loopTestPc = 0x1010U,
        .loopBodyPc = 0x1020U, .loopExitPc = 0x1030U}).accepted);
    CHECK(ApplyControlEvent(loopWithOpenCall, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x2000U, .returnPc = 0x1024U}).accepted);
    result = ApplyControlEvent(loopWithOpenCall, ControlEvent{.kind = ControlEventKind::LoopBackedge});
    CHECK(result.becameTerminal && loopWithOpenCall.lastFault == ControlFault::UnbalancedControl);
    return true;
}

bool TestInvalidControlFaults()
{
    auto badStart = InitializeWaveControl(0x1001U, 0xFU);
    CHECK(badStart.faulted && badStart.liveMask == 0U);

    auto badMask = InitializeWaveControl(0x1000U, 0x3U);
    auto result = ApplyControlEvent(badMask, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2000U,
        .fallthroughPc = 0x2010U, .joinPc = 0x2020U, .takenMask = 0x4U});
    CHECK(result.accepted && result.becameTerminal && badMask.faulted);

    auto overflow = InitializeWaveControl(0x1000U, 0xFU);
    const ControlStackLimits oneCall{.controlDepth = 8U, .callDepth = 1U};
    CHECK(ApplyControlEvent(overflow, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x2000U, .returnPc = 0x1010U}, oneCall).accepted);
    result = ApplyControlEvent(overflow, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x3000U, .returnPc = 0x2010U}, oneCall);
    CHECK(result.becameTerminal && overflow.faulted);

    auto underflow = InitializeWaveControl(0x1000U, 0xFU);
    result = ApplyControlEvent(underflow, ControlEvent{.kind = ControlEventKind::Return});
    CHECK(result.becameTerminal && underflow.faulted);

    auto badPc = InitializeWaveControl(0x1000U, 0xFU);
    result = ApplyControlEvent(badPc, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2001U,
        .fallthroughPc = 0x2010U, .joinPc = 0x2020U, .takenMask = 0x1U});
    CHECK(result.becameTerminal && badPc.lastFault == ControlFault::InvalidPc);

    auto controlOverflow = InitializeWaveControl(0x1000U, 0xFU);
    const ControlStackLimits oneControl{.controlDepth = 1U, .callDepth = 8U};
    CHECK(ApplyControlEvent(controlOverflow, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2000U,
        .fallthroughPc = 0x3000U, .joinPc = 0x4000U, .takenMask = 0x3U}, oneControl).accepted);
    result = ApplyControlEvent(controlOverflow, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2010U,
        .fallthroughPc = 0x3010U, .joinPc = 0x4010U, .takenMask = 0x1U}, oneControl);
    CHECK(result.becameTerminal && controlOverflow.lastFault == ControlFault::ControlStackOverflow);

    auto loopUnderflow = InitializeWaveControl(0x1000U, 0xFU);
    result = ApplyControlEvent(loopUnderflow, ControlEvent{.kind = ControlEventKind::LoopBackedge});
    CHECK(result.becameTerminal && loopUnderflow.lastFault == ControlFault::MalformedJoin);

    auto unbalanced = InitializeWaveControl(0x1000U, 0xFU);
    CHECK(ApplyControlEvent(unbalanced, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2000U,
        .fallthroughPc = 0x3000U, .joinPc = 0x4000U, .takenMask = 0x3U}).accepted);
    CHECK(ApplyControlEvent(unbalanced, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x5000U, .returnPc = 0x2010U}).accepted);
    result = AdvanceAcceptedInstruction(unbalanced, 0x4000U);
    CHECK(result.becameTerminal && unbalanced.faulted);
    return true;
}

bool TestSeededTransitionInvariants()
{
    std::mt19937 rng(0xC61F10U);
    auto state = InitializeWaveControl(0x1000U, 0xFFFFFFFFU);
    std::uint64_t nextPc = 0x2000U;
    for (unsigned step = 0; step < 20000U; ++step) {
        const std::uint32_t beforeLive = state.liveMask;
        if ((rng() & 1U) != 0U) {
            std::uint32_t taken = static_cast<std::uint32_t>(rng()) & state.activeMask;
            if (taken == 0U || taken == state.activeMask)
                taken ^= state.activeMask & (~state.activeMask + 1U);
            if (taken != 0U && taken != state.activeMask) {
                const auto branch = ApplyControlEvent(state, ControlEvent{
                    .kind = ControlEventKind::Branch, .targetPc = nextPc,
                    .fallthroughPc = nextPc + 4U, .joinPc = nextPc + 8U, .takenMask = taken});
                CHECK(branch.accepted && !branch.becameTerminal);
                const auto firstPath = AdvanceAcceptedInstruction(state, nextPc + 8U);
                CHECK(firstPath.accepted && !firstPath.becameTerminal);
                const auto deferredPath = AdvanceAcceptedInstruction(state, nextPc + 8U);
                CHECK(deferredPath.accepted && !deferredPath.becameTerminal);
                nextPc += 12U;
            } else {
                const auto result = AdvanceAcceptedInstruction(state, nextPc);
                CHECK(result.accepted && !result.becameTerminal);
                nextPc += 4U;
            }
        } else {
            const auto result = AdvanceAcceptedInstruction(state, nextPc);
            CHECK(result.accepted && !result.becameTerminal);
            nextPc += 4U;
        }
        CHECK((state.activeMask & ~state.liveMask) == 0U);
        CHECK((state.liveMask & ~beforeLive) == 0U);
        CHECK((state.pc & 0x3U) == 0U);
        CHECK(state.controlStack.size() <= 8U);
        CHECK(state.callStack.size() <= 8U);
    }
    CHECK(state.controlStack.empty() && state.callStack.empty() && state.liveMask == 0xFFFFFFFFU);
    const auto terminated = ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::Terminate});
    CHECK(terminated.accepted && terminated.becameTerminal && !state.faulted);
    CHECK(state.liveMask == 0U && state.activeMask == 0U && state.controlStack.empty());
    return true;
}

int main()
{
    if (!TestUniformBranch() || !TestDivergentBranchJoin() || !TestNestedJoinAndTermination()
        || !TestCallReturn() || !TestStaggeredLoopExit() || !TestLoopNestedInBranchTermination()
        || !TestLoopUnwindRestoresCallDepth() || !TestMalformedOuterJoinAndProtectedReturns()
        || !TestInvalidControlFaults()
        || !TestSeededTransitionInvariants()) return 1;
    std::cout << "[pass] decoded wave control-flow reference checks passed.\n";
    return 0;
}
