// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "../control/cgx1_wave_control.hpp"
#include "cgx1_isa.hpp"

#include <cstddef>
#include <cstdint>
#include <span>

namespace cgx1::isa {

enum class ControlStreamStepStatus : std::uint8_t
{
    Executed,
    FetchFault,
    NotControlInstruction,
    UnsupportedOpcode,
    WaveNotRunnable,
    ControlFault
};

struct ControlStreamStepResult
{
    ControlStreamStepStatus status{ControlStreamStepStatus::NotControlInstruction};
    control::ControlResult control{};
};

// Execute provisional fetched Control-class instructions: opcode 0 terminates
// the active lanes, while opcode 1 branches all active lanes by a signed
// 24-bit byte displacement from the next instruction. This bounded reference
// does not model RTL fetch timing.
[[nodiscard]] inline ControlStreamStepResult StepControlInstructionStream(
    std::span<const std::uint32_t> words,
    std::uint64_t image_base,
    control::WaveControlState& wave,
    const control::ControlStackLimits& limits = {})
{
    constexpr std::uint64_t instruction_bytes = sizeof(std::uint32_t);
    constexpr std::uint64_t address_limit = control::kGpuVirtualAddressLimit;
    if ((image_base & (instruction_bytes - 1U)) != 0U
        || image_base >= address_limit
        || !control::IsValidPc(wave.pc)
        || wave.pc < image_base)
    {
        return {ControlStreamStepStatus::FetchFault, {}};
    }

    const std::uint64_t word_index = (wave.pc - image_base) / instruction_bytes;
    if (word_index >= words.size())
        return {ControlStreamStepStatus::FetchFault, {}};

    const BaseInstruction instruction = DecodeBase(words[static_cast<std::size_t>(word_index)]);
    if (instruction.instructionClass != InstructionClass::Control)
        return {ControlStreamStepStatus::NotControlInstruction, {}};
    if (instruction.opcode > 1U)
        return {ControlStreamStepStatus::UnsupportedOpcode, {}};
    if (wave.terminated || wave.faulted || wave.activeMask == 0U)
        return {ControlStreamStepStatus::WaveNotRunnable, {}};

    control::ControlEvent event{};
    if (instruction.opcode == 0U)
    {
        event.kind = control::ControlEventKind::Terminate;
    }
    else
    {
        const std::uint32_t displacement_bits
            = (static_cast<std::uint32_t>(instruction.destination) << 16U)
            | (static_cast<std::uint32_t>(instruction.source0) << 8U)
            | static_cast<std::uint32_t>(instruction.source1);
        std::int64_t displacement = static_cast<std::int64_t>(displacement_bits);
        if ((displacement_bits & 0x00800000U) != 0U)
            displacement -= 0x01000000LL;

        const std::int64_t next_pc = static_cast<std::int64_t>(wave.pc) + instruction_bytes;
        const std::int64_t target = next_pc + displacement;
        const std::uint64_t target_pc = (target < 0)
            ? address_limit
            : static_cast<std::uint64_t>(target);
        event.kind = control::ControlEventKind::Branch;
        event.targetPc = target_pc;
        // This encoding is unconditional, so these branch-event fields are
        // unused by the transition. Keep them valid even at the final PC.
        event.fallthroughPc = target_pc;
        event.joinPc = target_pc;
        event.takenMask = wave.activeMask;
    }

    const control::ControlResult result = control::ApplyControlEvent(wave, event, limits);
    if (!result.accepted)
        return {ControlStreamStepStatus::WaveNotRunnable, result};
    if (result.fault != control::ControlFault::None)
        return {ControlStreamStepStatus::ControlFault, result};
    return {ControlStreamStepStatus::Executed, result};
}

} // namespace cgx1::isa
