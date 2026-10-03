// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace cgx1::control {

inline constexpr std::uint64_t kGpuVirtualAddressLimit = std::uint64_t{1} << 57U;

enum class ControlFault : std::uint8_t
{
    None,
    InvalidPc,
    InvalidLaneMask,
    ControlStackOverflow,
    CallStackOverflow,
    CallStackUnderflow,
    MalformedJoin,
    UnbalancedControl,
    NoRunnableLanes,
    InvalidEvent
};

enum class ControlEventKind : std::uint8_t
{
    Advance,
    Branch,
    Call,
    Return,
    LoopBegin,
    LoopBackedge,
    LoopTest,
    Terminate
};

enum class ControlFrameKind : std::uint8_t
{
    Branch,
    Loop
};

struct ControlStackLimits
{
    std::size_t controlDepth{8U};
    std::size_t callDepth{8U};
};

struct ControlFrame
{
    ControlFrameKind kind{ControlFrameKind::Branch};
    std::uint64_t joinPc{};
    std::uint64_t deferredPc{};
    std::uint64_t testPc{};
    std::uint64_t bodyPc{};
    std::uint64_t exitPc{};
    std::uint32_t deferredMask{};
    std::uint32_t waitingMask{};
    std::uint32_t memberMask{};
    std::size_t callDepth{};
    bool deferredScheduled{};
};

struct WaveControlState
{
    std::uint64_t pc{};
    std::uint32_t liveMask{};
    std::uint32_t activeMask{};
    std::vector<ControlFrame> controlStack;
    std::vector<std::uint64_t> callStack;
    ControlFault lastFault{ControlFault::None};
    bool faulted{};
    bool terminated{};
};

struct ControlEvent
{
    ControlEventKind kind{ControlEventKind::Advance};
    std::uint64_t sequentialPc{};
    std::uint64_t targetPc{};
    std::uint64_t fallthroughPc{};
    std::uint64_t joinPc{};
    std::uint64_t returnPc{};
    std::uint64_t loopTestPc{};
    std::uint64_t loopBodyPc{};
    std::uint64_t loopExitPc{};
    std::uint32_t takenMask{};
    std::uint32_t continueMask{};
};

struct ControlResult
{
    bool accepted{};
    bool becameTerminal{};
    ControlFault fault{ControlFault::None};
};

[[nodiscard]] inline bool IsValidPc(std::uint64_t pc) noexcept
{
    return pc < kGpuVirtualAddressLimit && (pc & 0x3U) == 0U;
}

inline void FaultWave(WaveControlState& state, ControlFault fault) noexcept
{
    state.liveMask = 0U;
    state.activeMask = 0U;
    state.controlStack.clear();
    state.callStack.clear();
    state.lastFault = fault;
    state.faulted = true;
    state.terminated = true;
}

inline void TerminateWave(WaveControlState& state) noexcept
{
    state.liveMask = 0U;
    state.activeMask = 0U;
    state.controlStack.clear();
    state.callStack.clear();
    state.terminated = true;
}

[[nodiscard]] inline WaveControlState InitializeWaveControl(
    std::uint64_t startPc,
    std::uint32_t liveMask)
{
    WaveControlState state{};
    state.pc = startPc;
    state.liveMask = liveMask;
    state.activeMask = liveMask;
    if (!IsValidPc(startPc))
        FaultWave(state, ControlFault::InvalidPc);
    else if (liveMask == 0U)
        FaultWave(state, ControlFault::InvalidLaneMask);
    return state;
}

namespace detail {

[[nodiscard]] inline bool IsPcSetValid(std::initializer_list<std::uint64_t> pcs) noexcept
{
    for (const std::uint64_t pc : pcs)
        if (!IsValidPc(pc)) return false;
    return true;
}

[[nodiscard]] inline bool RestoreCallDepth(WaveControlState& state, std::size_t depth) noexcept
{
    if (state.callStack.size() < depth) return false;
    state.callStack.resize(depth);
    return true;
}

inline bool ResumeEmptyPath(WaveControlState& state)
{
    if (state.controlStack.empty())
    {
        if (state.liveMask == 0U)
            TerminateWave(state);
        else
            FaultWave(state, ControlFault::NoRunnableLanes);
        return false;
    }

    ControlFrame& frame = state.controlStack.back();
    if (frame.kind == ControlFrameKind::Branch)
    {
        const std::uint32_t deferred = frame.deferredMask & state.liveMask;
        const std::uint32_t waiting = frame.waitingMask & state.liveMask;
        if (!frame.deferredScheduled && deferred != 0U)
        {
            if (!RestoreCallDepth(state, frame.callDepth))
            {
                FaultWave(state, ControlFault::UnbalancedControl);
                return false;
            }
            frame.deferredMask = 0U;
            frame.deferredScheduled = true;
            frame.waitingMask = waiting;
            state.activeMask = deferred;
            state.pc = frame.deferredPc;
            return true;
        }

        const std::uint64_t joinPc = frame.joinPc;
        const std::size_t callDepth = frame.callDepth;
        state.controlStack.pop_back();
        if (!RestoreCallDepth(state, callDepth))
        {
            FaultWave(state, ControlFault::UnbalancedControl);
            return false;
        }
        state.activeMask = waiting;
        state.pc = joinPc;
        return true;
    }

    const std::uint32_t waiting = frame.waitingMask & state.liveMask;
    const std::uint32_t members = frame.memberMask & state.liveMask;
    if (waiting != 0U)
    {
        const std::uint64_t exitPc = frame.exitPc;
        const std::size_t callDepth = frame.callDepth;
        if (!RestoreCallDepth(state, callDepth))
        {
            FaultWave(state, ControlFault::UnbalancedControl);
            return false;
        }
        state.controlStack.pop_back();
        state.activeMask = waiting;
        state.pc = exitPc;
        return true;
    }
    if (members == 0U)
    {
        const std::uint64_t exitPc = frame.exitPc;
        const std::size_t callDepth = frame.callDepth;
        if (!RestoreCallDepth(state, callDepth))
        {
            FaultWave(state, ControlFault::UnbalancedControl);
            return false;
        }
        state.controlStack.pop_back();
        state.pc = exitPc;
        return true;
    }
    FaultWave(state, ControlFault::NoRunnableLanes);
    return false;
}

inline void Stabilize(WaveControlState& state, const ControlStackLimits& limits)
{
    const std::size_t iterationLimit = (limits.controlDepth * 3U) + 4U;
    for (std::size_t iteration = 0U; iteration < iterationLimit && !state.terminated; ++iteration)
    {
        if ((state.activeMask & ~state.liveMask) != 0U)
        {
            FaultWave(state, ControlFault::InvalidLaneMask);
            return;
        }
        if (state.liveMask == 0U)
        {
            TerminateWave(state);
            return;
        }
        if (state.activeMask == 0U)
        {
            if (!ResumeEmptyPath(state)) return;
            continue;
        }
        if (state.controlStack.empty()) return;

        ControlFrame& frame = state.controlStack.back();
        if (frame.kind != ControlFrameKind::Branch || frame.joinPc != state.pc)
        {
            for (std::size_t index = 0U; index + 1U < state.controlStack.size(); ++index)
            {
                const ControlFrame& enclosing = state.controlStack[index];
                if (enclosing.kind == ControlFrameKind::Branch && enclosing.joinPc == state.pc)
                {
                    FaultWave(state, ControlFault::MalformedJoin);
                    return;
                }
            }
            return;
        }
        if (state.callStack.size() != frame.callDepth)
        {
            FaultWave(state, ControlFault::UnbalancedControl);
            return;
        }
        if (!frame.deferredScheduled)
        {
            const std::uint32_t deferred = frame.deferredMask & state.liveMask;
            frame.waitingMask |= state.activeMask & state.liveMask;
            if (deferred != 0U)
            {
                frame.deferredMask = 0U;
                frame.deferredScheduled = true;
                state.activeMask = deferred;
                state.pc = frame.deferredPc;
                continue;
            }
            state.activeMask |= frame.waitingMask;
            state.controlStack.pop_back();
            continue;
        }

        state.activeMask |= frame.waitingMask & state.liveMask;
        state.controlStack.pop_back();
    }
    if (!state.terminated && state.controlStack.size() <= limits.controlDepth)
        FaultWave(state, ControlFault::UnbalancedControl);
}

[[nodiscard]] inline ControlResult FinishTransition(
    WaveControlState& state,
    bool wasTerminal,
    const ControlStackLimits& limits)
{
    Stabilize(state, limits);
    return {true, !wasTerminal && state.terminated, state.lastFault};
}

} // namespace detail

[[nodiscard]] inline ControlResult AdvanceAcceptedInstruction(
    WaveControlState& state,
    std::uint64_t sequentialPc,
    const ControlStackLimits& limits = {})
{
    const bool wasTerminal = state.terminated;
    if (wasTerminal) return {false, false, state.lastFault};
    if (!IsValidPc(sequentialPc))
    {
        FaultWave(state, ControlFault::InvalidPc);
        return {true, true, state.lastFault};
    }
    state.pc = sequentialPc;
    return detail::FinishTransition(state, wasTerminal, limits);
}

[[nodiscard]] inline ControlResult ApplyControlEvent(
    WaveControlState& state,
    const ControlEvent& event,
    const ControlStackLimits& limits = {})
{
    const bool wasTerminal = state.terminated;
    if (wasTerminal) return {false, false, state.lastFault};

    switch (event.kind)
    {
    case ControlEventKind::Advance:
        return AdvanceAcceptedInstruction(state, event.sequentialPc, limits);

    case ControlEventKind::Branch:
        if (!detail::IsPcSetValid({event.targetPc, event.fallthroughPc, event.joinPc}))
        {
            FaultWave(state, ControlFault::InvalidPc);
            return {true, true, state.lastFault};
        }
        if ((event.takenMask & ~state.activeMask) != 0U)
        {
            FaultWave(state, ControlFault::InvalidLaneMask);
            return {true, true, state.lastFault};
        }
        if (event.takenMask == 0U)
            state.pc = event.fallthroughPc;
        else if (event.takenMask == state.activeMask || event.targetPc == event.fallthroughPc)
            state.pc = event.targetPc;
        else if (state.controlStack.size() >= limits.controlDepth)
        {
            FaultWave(state, ControlFault::ControlStackOverflow);
            return {true, true, state.lastFault};
        }
        else
        {
            ControlFrame frame{};
            frame.kind = ControlFrameKind::Branch;
            frame.joinPc = event.joinPc;
            frame.deferredPc = event.fallthroughPc;
            frame.deferredMask = state.activeMask & ~event.takenMask;
            frame.callDepth = state.callStack.size();
            state.controlStack.push_back(frame);
            state.activeMask = event.takenMask;
            state.pc = event.targetPc;
        }
        return detail::FinishTransition(state, wasTerminal, limits);

    case ControlEventKind::Call:
        if (!detail::IsPcSetValid({event.targetPc, event.returnPc}))
        {
            FaultWave(state, ControlFault::InvalidPc);
            return {true, true, state.lastFault};
        }
        if (state.callStack.size() >= limits.callDepth)
        {
            FaultWave(state, ControlFault::CallStackOverflow);
            return {true, true, state.lastFault};
        }
        state.callStack.push_back(event.returnPc);
        state.pc = event.targetPc;
        return {true, false, ControlFault::None};

    case ControlEventKind::Return:
        if (state.callStack.empty())
        {
            FaultWave(state, ControlFault::CallStackUnderflow);
            return {true, true, state.lastFault};
        }
        {
            std::size_t protectedCallDepth = 0U;
            for (const ControlFrame& frame : state.controlStack)
                if (frame.callDepth > protectedCallDepth)
                    protectedCallDepth = frame.callDepth;
            if (state.callStack.size() <= protectedCallDepth)
            {
                FaultWave(state, ControlFault::UnbalancedControl);
                return {true, true, state.lastFault};
            }
        }
        state.pc = state.callStack.back();
        state.callStack.pop_back();
        return detail::FinishTransition(state, wasTerminal, limits);

    case ControlEventKind::LoopBegin:
        if (!detail::IsPcSetValid({event.loopTestPc, event.loopBodyPc, event.loopExitPc}))
        {
            FaultWave(state, ControlFault::InvalidPc);
            return {true, true, state.lastFault};
        }
        if (state.activeMask == 0U)
        {
            FaultWave(state, ControlFault::InvalidLaneMask);
            return {true, true, state.lastFault};
        }
        if (state.controlStack.size() >= limits.controlDepth)
        {
            FaultWave(state, ControlFault::ControlStackOverflow);
            return {true, true, state.lastFault};
        }
        {
            ControlFrame frame{};
            frame.kind = ControlFrameKind::Loop;
            frame.testPc = event.loopTestPc;
            frame.bodyPc = event.loopBodyPc;
            frame.exitPc = event.loopExitPc;
            frame.memberMask = state.activeMask;
            frame.callDepth = state.callStack.size();
            state.controlStack.push_back(frame);
        }
        state.pc = event.loopTestPc;
        return {true, false, ControlFault::None};

    case ControlEventKind::LoopBackedge:
        if (state.controlStack.empty()
            || state.controlStack.back().kind != ControlFrameKind::Loop)
        {
            FaultWave(state, ControlFault::MalformedJoin);
            return {true, true, state.lastFault};
        }
        if (state.callStack.size() != state.controlStack.back().callDepth)
        {
            FaultWave(state, ControlFault::UnbalancedControl);
            return {true, true, state.lastFault};
        }
        state.pc = state.controlStack.back().testPc;
        return {true, false, ControlFault::None};

    case ControlEventKind::LoopTest:
        if (state.controlStack.empty()
            || state.controlStack.back().kind != ControlFrameKind::Loop)
        {
            FaultWave(state, ControlFault::MalformedJoin);
            return {true, true, state.lastFault};
        }
        {
            ControlFrame& frame = state.controlStack.back();
            if (state.callStack.size() != frame.callDepth)
            {
                FaultWave(state, ControlFault::UnbalancedControl);
                return {true, true, state.lastFault};
            }
            const std::uint32_t expected = frame.memberMask & state.liveMask & ~frame.waitingMask;
            if (state.activeMask != expected || (event.continueMask & ~state.activeMask) != 0U)
            {
                FaultWave(state, ControlFault::InvalidLaneMask);
                return {true, true, state.lastFault};
            }
            frame.waitingMask |= state.activeMask & ~event.continueMask;
            if (event.continueMask != 0U)
            {
                state.activeMask = event.continueMask;
                state.pc = frame.bodyPc;
                return {true, false, ControlFault::None};
            }
            state.activeMask = frame.waitingMask & state.liveMask;
            state.pc = frame.exitPc;
            state.controlStack.pop_back();
        }
        return detail::FinishTransition(state, wasTerminal, limits);

    case ControlEventKind::Terminate:
        state.liveMask &= ~state.activeMask;
        state.activeMask = 0U;
        for (ControlFrame& frame : state.controlStack)
        {
            frame.deferredMask &= state.liveMask;
            frame.waitingMask &= state.liveMask;
            frame.memberMask &= state.liveMask;
        }
        return detail::FinishTransition(state, wasTerminal, limits);
    }

    FaultWave(state, ControlFault::InvalidEvent);
    return {true, true, state.lastFault};
}

} // namespace cgx1::control
