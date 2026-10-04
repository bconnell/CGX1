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

// Execute the first provisional fetched Control-class instruction. Opcode 0
// terminates the currently active lanes through the shared control reference;
// its three base operand fields are ignored in this provisional encoding.
// This bounded reference does not model RTL fetch timing.
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
    if (instruction.opcode != 0U)
        return {ControlStreamStepStatus::UnsupportedOpcode, {}};
    if (wave.terminated || wave.faulted || wave.activeMask == 0U)
        return {ControlStreamStepStatus::WaveNotRunnable, {}};

    const control::ControlResult result = control::ApplyControlEvent(
        wave,
        control::ControlEvent{.kind = control::ControlEventKind::Terminate},
        limits);
    if (!result.accepted)
        return {ControlStreamStepStatus::WaveNotRunnable, result};
    if (result.fault != control::ControlFault::None)
        return {ControlStreamStepStatus::ControlFault, result};
    return {ControlStreamStepStatus::Executed, result};
}

} // namespace cgx1::isa
