// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_context.hpp"
#include "cgx1_wave_control.hpp"

#include <cstdint>
#include <iostream>
#include <random>

using namespace cgx1::control;

#define CHECK(x) do { if (!(x)) { std::cerr << "[fail] " #x " line " << __LINE__; ::cgx1::testing::WriteRandomTestFailureContext(std::cerr); std::cerr << '\n'; return false; } } while (false)

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
    {
        auto&& check_action_applycontrolevent_32_1 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2000U,
        .fallthroughPc = 0x3000U, .joinPc = 0x4000U, .takenMask = 0x3U}));
        CHECK(check_action_applycontrolevent_32_1.accepted);
    }
    CHECK(state.pc == 0x2000U && state.activeMask == 0x3U && state.controlStack.size() == 1U);
    {
        auto&& check_action_advanceacceptedinstruction_36_2 = (AdvanceAcceptedInstruction(state, 0x4000U));
        CHECK(check_action_advanceacceptedinstruction_36_2.accepted);
    }
    CHECK(state.pc == 0x3000U && state.activeMask == 0xCU);
    CHECK(state.controlStack.back().waitingMask == 0x3U);
    {
        auto&& check_action_advanceacceptedinstruction_39_3 = (AdvanceAcceptedInstruction(state, 0x4000U));
        CHECK(check_action_advanceacceptedinstruction_39_3.accepted);
    }
    CHECK(state.pc == 0x4000U && state.activeMask == 0xFU && state.controlStack.empty());
    return true;
}

bool TestNestedJoinAndTermination()
{
    auto state = InitializeWaveControl(0x1000U, 0xFU);
    {
        auto&& check_action_applycontrolevent_47_4 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x1004U,
        .fallthroughPc = 0x2000U, .joinPc = 0x3000U, .takenMask = 0x3U}));
        CHECK(check_action_applycontrolevent_47_4.accepted);
    }
    {
        auto&& check_action_applycontrolevent_50_5 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x1008U,
        .fallthroughPc = 0x1010U, .joinPc = 0x1020U, .takenMask = 0x1U}));
        CHECK(check_action_applycontrolevent_50_5.accepted);
    }
    const auto terminated = ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::Terminate});
    CHECK(terminated.accepted && !terminated.becameTerminal);
    CHECK(state.liveMask == 0xEU && state.activeMask == 0x2U && state.pc == 0x1010U);
    {
        auto&& check_action_advanceacceptedinstruction_56_6 = (AdvanceAcceptedInstruction(state, 0x1020U));
        CHECK(check_action_advanceacceptedinstruction_56_6.accepted);
    }
    CHECK(state.activeMask == 0x2U && state.liveMask == 0xEU && state.controlStack.size() == 1U);
    {
        auto&& check_action_advanceacceptedinstruction_58_7 = (AdvanceAcceptedInstruction(state, 0x3000U));
        CHECK(check_action_advanceacceptedinstruction_58_7.accepted);
    }
    CHECK(state.pc == 0x2000U && state.activeMask == 0xCU);
    CHECK(state.controlStack.back().waitingMask == 0x2U);
    {
        auto&& check_action_advanceacceptedinstruction_61_8 = (AdvanceAcceptedInstruction(state, 0x3000U));
        CHECK(check_action_advanceacceptedinstruction_61_8.accepted);
    }
    CHECK(state.activeMask == 0xEU && state.liveMask == 0xEU && state.pc == 0x3000U);
    return true;
}

bool TestCallReturn()
{
    auto state = InitializeWaveControl(0x1000U, 0xFU);
    {
        auto&& check_action_applycontrolevent_69_9 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x5000U, .returnPc = 0x1010U}));
        CHECK(check_action_applycontrolevent_69_9.accepted);
    }
    CHECK(state.pc == 0x5000U && state.callStack.size() == 1U);
    {
        auto&& check_action_applycontrolevent_72_10 = (ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::Return}));
        CHECK(check_action_applycontrolevent_72_10.accepted);
    }
    CHECK(state.pc == 0x1010U && state.callStack.empty());
    return true;
}

bool TestStaggeredLoopExit()
{
    auto state = InitializeWaveControl(0x1000U, 0xFU);
    {
        auto&& check_action_applycontrolevent_80_11 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopBegin, .loopTestPc = 0x1004U,
        .loopBodyPc = 0x1008U, .loopExitPc = 0x1010U}));
        CHECK(check_action_applycontrolevent_80_11.accepted);
    }
    CHECK(state.pc == 0x1004U && state.controlStack.size() == 1U);
    {
        auto&& check_action_applycontrolevent_84_12 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopTest, .continueMask = 0xEU}));
        CHECK(check_action_applycontrolevent_84_12.accepted);
    }
    CHECK(state.pc == 0x1008U && state.activeMask == 0xEU);
    CHECK(state.controlStack.back().waitingMask == 0x1U);
    {
        auto&& check_action_applycontrolevent_88_13 = (ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::LoopBackedge}));
        CHECK(check_action_applycontrolevent_88_13.accepted);
    }
    {
        auto&& check_action_applycontrolevent_89_14 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopTest, .continueMask = 0xCU}));
        CHECK(check_action_applycontrolevent_89_14.accepted);
    }
    CHECK(state.activeMask == 0xCU && state.controlStack.back().waitingMask == 0x3U);
    {
        auto&& check_action_applycontrolevent_92_15 = (ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::LoopBackedge}));
        CHECK(check_action_applycontrolevent_92_15.accepted);
    }
    {
        auto&& check_action_applycontrolevent_93_16 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopTest, .continueMask = 0U}));
        CHECK(check_action_applycontrolevent_93_16.accepted);
    }
    CHECK(state.pc == 0x1010U && state.activeMask == 0xFU && state.controlStack.empty());
    return true;
}

bool TestLoopNestedInBranchTermination()
{
    auto state = InitializeWaveControl(0x1000U, 0xFU);
    {
        auto&& check_action_applycontrolevent_102_17 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2000U,
        .fallthroughPc = 0x3000U, .joinPc = 0x4000U, .takenMask = 0x3U}));
        CHECK(check_action_applycontrolevent_102_17.accepted);
    }
    {
        auto&& check_action_applycontrolevent_105_18 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopBegin, .loopTestPc = 0x2010U,
        .loopBodyPc = 0x2020U, .loopExitPc = 0x2040U}));
        CHECK(check_action_applycontrolevent_105_18.accepted);
    }
    CHECK(state.controlStack.size() == 2U);
    CHECK(state.controlStack[0].kind == ControlFrameKind::Branch);
    CHECK(state.controlStack[1].kind == ControlFrameKind::Loop);
    {
        auto&& check_action_applycontrolevent_111_19 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopTest, .continueMask = 0x2U}));
        CHECK(check_action_applycontrolevent_111_19.accepted);
    }
    CHECK(state.activeMask == 0x2U && state.controlStack.back().waitingMask == 0x1U);
    const auto terminated = ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::Terminate});
    CHECK(terminated.accepted && !terminated.becameTerminal);
    CHECK(state.liveMask == 0xDU && state.activeMask == 0x1U && state.pc == 0x2040U);
    CHECK(state.controlStack.size() == 1U && state.controlStack.back().kind == ControlFrameKind::Branch);
    {
        auto&& check_action_advanceacceptedinstruction_118_20 = (AdvanceAcceptedInstruction(state, 0x4000U));
        CHECK(check_action_advanceacceptedinstruction_118_20.accepted);
    }
    CHECK(state.pc == 0x3000U && state.activeMask == 0xCU);
    {
        auto&& check_action_advanceacceptedinstruction_120_21 = (AdvanceAcceptedInstruction(state, 0x4000U));
        CHECK(check_action_advanceacceptedinstruction_120_21.accepted);
    }
    CHECK(state.pc == 0x4000U && state.activeMask == 0xDU && state.liveMask == 0xDU);
    return true;
}

bool TestLoopUnwindRestoresCallDepth()
{
    auto state = InitializeWaveControl(0x1000U, 0xFU);
    {
        auto&& check_action_applycontrolevent_128_22 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x2000U, .returnPc = 0x1010U}));
        CHECK(check_action_applycontrolevent_128_22.accepted);
    }
    {
        auto&& check_action_applycontrolevent_130_23 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopBegin, .loopTestPc = 0x2010U,
        .loopBodyPc = 0x2020U, .loopExitPc = 0x2040U}));
        CHECK(check_action_applycontrolevent_130_23.accepted);
    }
    {
        auto&& check_action_applycontrolevent_133_24 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::LoopTest, .continueMask = 0xEU}));
        CHECK(check_action_applycontrolevent_133_24.accepted);
    }
    CHECK(state.activeMask == 0xEU && state.controlStack.back().waitingMask == 0x1U);
    {
        auto&& check_action_applycontrolevent_136_25 = (ApplyControlEvent(state, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x3000U, .returnPc = 0x2030U}));
        CHECK(check_action_applycontrolevent_136_25.accepted);
    }
    {
        auto&& check_action_applycontrolevent_138_26 = (ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::Terminate}));
        CHECK(check_action_applycontrolevent_138_26.accepted);
    }
    CHECK(state.activeMask == 0x1U && state.pc == 0x2040U);
    CHECK(state.callStack.size() == 1U);
    {
        auto&& check_action_applycontrolevent_141_27 = (ApplyControlEvent(state, ControlEvent{.kind = ControlEventKind::Return}));
        CHECK(check_action_applycontrolevent_141_27.accepted);
    }
    CHECK(state.pc == 0x1010U && state.callStack.empty());
    return true;
}

bool TestMalformedOuterJoinAndProtectedReturns()
{
    auto branchWithOpenLoop = InitializeWaveControl(0x1000U, 0xFU);
    {
        auto&& check_action_applycontrolevent_149_28 = (ApplyControlEvent(branchWithOpenLoop, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2000U,
        .fallthroughPc = 0x3000U, .joinPc = 0x4000U, .takenMask = 0x3U}));
        CHECK(check_action_applycontrolevent_149_28.accepted);
    }
    {
        auto&& check_action_applycontrolevent_152_29 = (ApplyControlEvent(branchWithOpenLoop, ControlEvent{
        .kind = ControlEventKind::LoopBegin, .loopTestPc = 0x2010U,
        .loopBodyPc = 0x2020U, .loopExitPc = 0x2040U}));
        CHECK(check_action_applycontrolevent_152_29.accepted);
    }
    auto result = AdvanceAcceptedInstruction(branchWithOpenLoop, 0x4000U);
    CHECK(result.becameTerminal && branchWithOpenLoop.lastFault == ControlFault::MalformedJoin);

    auto branchWithOpenBranch = InitializeWaveControl(0x1000U, 0xFU);
    {
        auto&& check_action_applycontrolevent_159_30 = (ApplyControlEvent(branchWithOpenBranch, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2000U,
        .fallthroughPc = 0x3000U, .joinPc = 0x4000U, .takenMask = 0x3U}));
        CHECK(check_action_applycontrolevent_159_30.accepted);
    }
    {
        auto&& check_action_applycontrolevent_162_31 = (ApplyControlEvent(branchWithOpenBranch, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2010U,
        .fallthroughPc = 0x2020U, .joinPc = 0x2030U, .takenMask = 0x1U}));
        CHECK(check_action_applycontrolevent_162_31.accepted);
    }
    result = AdvanceAcceptedInstruction(branchWithOpenBranch, 0x4000U);
    CHECK(result.becameTerminal && branchWithOpenBranch.lastFault == ControlFault::MalformedJoin);

    auto protectedCaller = InitializeWaveControl(0x1000U, 0xFU);
    {
        auto&& check_action_applycontrolevent_169_32 = (ApplyControlEvent(protectedCaller, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x2000U, .returnPc = 0x1010U}));
        CHECK(check_action_applycontrolevent_169_32.accepted);
    }
    {
        auto&& check_action_applycontrolevent_171_33 = (ApplyControlEvent(protectedCaller, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2010U,
        .fallthroughPc = 0x2020U, .joinPc = 0x2030U, .takenMask = 0x3U}));
        CHECK(check_action_applycontrolevent_171_33.accepted);
    }
    result = ApplyControlEvent(protectedCaller, ControlEvent{.kind = ControlEventKind::Return});
    CHECK(result.becameTerminal && protectedCaller.lastFault == ControlFault::UnbalancedControl);

    auto loopWithOpenCall = InitializeWaveControl(0x1000U, 0xFU);
    {
        auto&& check_action_applycontrolevent_178_34 = (ApplyControlEvent(loopWithOpenCall, ControlEvent{
        .kind = ControlEventKind::LoopBegin, .loopTestPc = 0x1010U,
        .loopBodyPc = 0x1020U, .loopExitPc = 0x1030U}));
        CHECK(check_action_applycontrolevent_178_34.accepted);
    }
    {
        auto&& check_action_applycontrolevent_181_35 = (ApplyControlEvent(loopWithOpenCall, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x2000U, .returnPc = 0x1024U}));
        CHECK(check_action_applycontrolevent_181_35.accepted);
    }
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
    {
        auto&& check_action_applycontrolevent_201_36 = (ApplyControlEvent(overflow, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x2000U, .returnPc = 0x1010U}, oneCall));
        CHECK(check_action_applycontrolevent_201_36.accepted);
    }
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
    {
        auto&& check_action_applycontrolevent_219_37 = (ApplyControlEvent(controlOverflow, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2000U,
        .fallthroughPc = 0x3000U, .joinPc = 0x4000U, .takenMask = 0x3U}, oneControl));
        CHECK(check_action_applycontrolevent_219_37.accepted);
    }
    result = ApplyControlEvent(controlOverflow, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2010U,
        .fallthroughPc = 0x3010U, .joinPc = 0x4010U, .takenMask = 0x1U}, oneControl);
    CHECK(result.becameTerminal && controlOverflow.lastFault == ControlFault::ControlStackOverflow);

    auto loopUnderflow = InitializeWaveControl(0x1000U, 0xFU);
    result = ApplyControlEvent(loopUnderflow, ControlEvent{.kind = ControlEventKind::LoopBackedge});
    CHECK(result.becameTerminal && loopUnderflow.lastFault == ControlFault::MalformedJoin);

    auto unbalanced = InitializeWaveControl(0x1000U, 0xFU);
    {
        auto&& check_action_applycontrolevent_232_38 = (ApplyControlEvent(unbalanced, ControlEvent{
        .kind = ControlEventKind::Branch, .targetPc = 0x2000U,
        .fallthroughPc = 0x3000U, .joinPc = 0x4000U, .takenMask = 0x3U}));
        CHECK(check_action_applycontrolevent_232_38.accepted);
    }
    {
        auto&& check_action_applycontrolevent_235_39 = (ApplyControlEvent(unbalanced, ControlEvent{
        .kind = ControlEventKind::Call, .targetPc = 0x5000U, .returnPc = 0x2010U}));
        CHECK(check_action_applycontrolevent_235_39.accepted);
    }
    result = AdvanceAcceptedInstruction(unbalanced, 0x4000U);
    CHECK(result.becameTerminal && unbalanced.faulted);
    return true;
}

bool TestSeededTransitionInvariants()
{
    constexpr std::uint32_t seed = 0xC61F10U;
    std::mt19937 rng(seed);
    auto state = InitializeWaveControl(0x1000U, 0xFFFFFFFFU);
    std::uint64_t nextPc = 0x2000U;
    for (unsigned step = 0; step < 20000U; ++step) {
        ::cgx1::testing::SetRandomTestFailureContext(
            "TestSeededTransitionInvariants", seed, step, nextPc);
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
    ::cgx1::testing::ClearRandomTestFailureContext();
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
