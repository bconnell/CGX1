// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#pragma once

#include "cgx1_matrix_banking.hpp"

#include <array>
#include <cstdint>
#include <optional>
#include <stdexcept>
#include <utility>
#include <vector>

namespace cgx1::matrix {

inline constexpr std::uint32_t kArchitecturalVgprsPerWave = 256U;
inline constexpr std::uint32_t kPooledVgprWaveLanes = 32U;
inline constexpr std::uint32_t kVgprRegistersPerPhysicalRow =
    kMatrixRegisterBankClasses;
inline constexpr std::uint32_t kArchitecturalRowsPerWave =
    kArchitecturalVgprsPerWave / kVgprRegistersPerPhysicalRow;

using PooledWaveRegister =
    std::array<std::uint32_t, kPooledVgprWaveLanes>;

enum class VgprAllocationState : std::uint8_t
{
    Free = 0,
    Reserved,
    Active
};

struct ResidentWaveVgprAllocation
{
    VgprAllocationState state = VgprAllocationState::Free;
    std::uint32_t physicalRowBase = 0U;
    std::uint32_t physicalRowCount = 0U;
    bool invalidated = false;
};

struct PhysicalVgprAddress
{
    std::uint32_t row;
    std::uint8_t bank;
};

inline constexpr std::uint32_t VgprRowsForRegisterCount(
    std::uint32_t registerCount)
{
    if (registerCount == 0U || registerCount > kArchitecturalVgprsPerWave)
    {
        throw std::invalid_argument(
            "VGPR allocation register count is out of range");
    }

    return (registerCount + kVgprRegistersPerPhysicalRow - 1U)
        / kVgprRegistersPerPhysicalRow;
}

inline std::optional<std::uint32_t> FindFirstFitVgprRows(
    const std::vector<bool>& occupied,
    std::uint32_t rowsNeeded)
{
    if (rowsNeeded == 0U || rowsNeeded > occupied.size())
    {
        return std::nullopt;
    }

    for (std::uint32_t base = 0U;
         base + rowsNeeded <= occupied.size();
         ++base)
    {
        bool free = true;
        for (std::uint32_t row = 0U; row < rowsNeeded; ++row)
        {
            if (occupied[base + row])
            {
                free = false;
                break;
            }
        }

        if (free)
        {
            return base;
        }
    }

    return std::nullopt;
}

class ResidentWaveVgprPool
{
public:
    ResidentWaveVgprPool(
        std::uint32_t physicalRows,
        std::uint32_t residentWaveSlots)
        : physicalRows_(physicalRows),
          allocations_(residentWaveSlots)
    {
        if (physicalRows == 0U || residentWaveSlots == 0U)
        {
            throw std::invalid_argument(
                "VGPR pool dimensions must be nonzero");
        }
    }

    [[nodiscard]] std::uint32_t PhysicalRows() const noexcept
    {
        return physicalRows_;
    }

    [[nodiscard]] std::uint32_t ResidentWaveSlots() const noexcept
    {
        return static_cast<std::uint32_t>(allocations_.size());
    }

    [[nodiscard]] const ResidentWaveVgprAllocation& Allocation(
        std::uint32_t waveSlot) const
    {
        CheckWaveSlot(waveSlot);
        return allocations_[waveSlot];
    }

    [[nodiscard]] std::uint32_t OccupiedRows() const noexcept
    {
        std::uint32_t rows = 0U;
        for (const auto& allocation : allocations_)
        {
            if (allocation.state != VgprAllocationState::Free)
            {
                rows += allocation.physicalRowCount;
            }
        }
        return rows;
    }

    bool Reserve(
        std::uint32_t waveSlot,
        std::uint32_t registerCount)
    {
        CheckWaveSlot(waveSlot);
        if (allocations_[waveSlot].state != VgprAllocationState::Free)
        {
            return false;
        }

        const std::uint32_t rowsNeeded =
            VgprRowsForRegisterCount(registerCount);
        const auto base =
            FindFirstFitVgprRows(OccupiedBitmap(), rowsNeeded);

        if (!base.has_value())
        {
            return false;
        }

        allocations_[waveSlot] = ResidentWaveVgprAllocation{
            VgprAllocationState::Reserved,
            *base,
            rowsNeeded,
            false};

        return true;
    }

    void MarkInvalidated(std::uint32_t waveSlot)
    {
        CheckWaveSlot(waveSlot);
        auto& allocation = allocations_[waveSlot];

        if (allocation.state != VgprAllocationState::Reserved)
        {
            throw std::logic_error(
                "only a reserved VGPR allocation can be invalidated");
        }

        allocation.invalidated = true;
    }

    bool Activate(std::uint32_t waveSlot)
    {
        CheckWaveSlot(waveSlot);
        auto& allocation = allocations_[waveSlot];

        if (allocation.state != VgprAllocationState::Reserved
            || !allocation.invalidated)
        {
            return false;
        }

        allocation.state = VgprAllocationState::Active;
        return true;
    }

    void Release(std::uint32_t waveSlot)
    {
        CheckWaveSlot(waveSlot);
        allocations_[waveSlot] = ResidentWaveVgprAllocation{};
    }

    [[nodiscard]] bool RegisterRangeFits(
        std::uint32_t waveSlot,
        std::uint32_t registerBase,
        std::uint32_t registerCount) const
    {
        CheckWaveSlot(waveSlot);
        const auto& allocation = allocations_[waveSlot];

        if (allocation.state != VgprAllocationState::Active
            || registerCount == 0U)
        {
            return false;
        }

        const std::uint32_t allocatedRegisters =
            allocation.physicalRowCount * kVgprRegistersPerPhysicalRow;

        return registerBase < allocatedRegisters
            && registerCount <= allocatedRegisters - registerBase;
    }

    [[nodiscard]] bool MatrixFragmentsFit(
        std::uint32_t waveSlot,
        std::uint8_t destinationBase,
        std::uint8_t sourceABase,
        std::uint8_t sourceBBase) const
    {
        if (!IsValidMatrixRegisterLayout(
                destinationBase,
                sourceABase,
                sourceBBase))
        {
            return false;
        }

        return RegisterRangeFits(
                   waveSlot,
                   destinationBase,
                   kMatrixAccumulatorRegistersPerLane)
            && RegisterRangeFits(
                   waveSlot,
                   sourceABase,
                   kMatrixSourceRegistersPerLane)
            && RegisterRangeFits(
                   waveSlot,
                   sourceBBase,
                   kMatrixSourceRegistersPerLane);
    }

    [[nodiscard]] PhysicalVgprAddress Translate(
        std::uint32_t waveSlot,
        std::uint8_t architecturalRegister) const
    {
        if (!RegisterRangeFits(
                waveSlot,
                architecturalRegister,
                1U))
        {
            throw std::out_of_range(
                "architectural VGPR is outside the active wave allocation");
        }

        const auto& allocation = allocations_[waveSlot];

        return PhysicalVgprAddress{
            allocation.physicalRowBase
                + static_cast<std::uint32_t>(architecturalRegister)
                    / kVgprRegistersPerPhysicalRow,
            MatrixRegisterBank(architecturalRegister)};
    }

    [[nodiscard]] bool InvariantsHold() const noexcept
    {
        std::vector<bool> occupied(physicalRows_, false);

        for (const auto& allocation : allocations_)
        {
            if (allocation.state == VgprAllocationState::Free)
            {
                if (allocation.physicalRowCount != 0U
                    || allocation.invalidated)
                {
                    return false;
                }

                continue;
            }

            if (allocation.physicalRowCount == 0U
                || allocation.physicalRowBase >= physicalRows_
                || allocation.physicalRowCount
                    > physicalRows_ - allocation.physicalRowBase)
            {
                return false;
            }

            if (allocation.state == VgprAllocationState::Active
                && !allocation.invalidated)
            {
                return false;
            }

            for (std::uint32_t row = 0U;
                 row < allocation.physicalRowCount;
                 ++row)
            {
                const std::uint32_t physicalRow =
                    allocation.physicalRowBase + row;

                if (occupied[physicalRow])
                {
                    return false;
                }

                occupied[physicalRow] = true;
            }
        }

        return true;
    }

private:
    void CheckWaveSlot(std::uint32_t waveSlot) const
    {
        if (waveSlot >= allocations_.size())
        {
            throw std::out_of_range(
                "resident wave slot is out of range");
        }
    }

    [[nodiscard]] std::vector<bool> OccupiedBitmap() const
    {
        std::vector<bool> occupied(physicalRows_, false);

        for (const auto& allocation : allocations_)
        {
            if (allocation.state == VgprAllocationState::Free)
            {
                continue;
            }

            for (std::uint32_t row = 0U;
                 row < allocation.physicalRowCount;
                 ++row)
            {
                occupied[allocation.physicalRowBase + row] = true;
            }
        }

        return occupied;
    }

    std::uint32_t physicalRows_;
    std::vector<ResidentWaveVgprAllocation> allocations_;
};

class PooledVgprStorage
{
public:
    explicit PooledVgprStorage(std::uint32_t physicalRows)
        : registers_(physicalRows),
          initialized_(physicalRows)
    {
        if (physicalRows == 0U)
        {
            throw std::invalid_argument(
                "pooled VGPR storage must contain physical rows");
        }

        for (auto& row : initialized_)
        {
            row.fill(false);
        }
    }

    void InvalidateReservedAllocation(
        ResidentWaveVgprPool& pool,
        std::uint32_t waveSlot)
    {
        const auto& allocation = pool.Allocation(waveSlot);

        if (allocation.state != VgprAllocationState::Reserved)
        {
            throw std::logic_error(
                "VGPR storage invalidation requires a reserved allocation");
        }

        for (std::uint32_t row = 0U;
             row < allocation.physicalRowCount;
             ++row)
        {
            initialized_[
                allocation.physicalRowBase + row].fill(false);
        }

        pool.MarkInvalidated(waveSlot);
    }

    [[nodiscard]] PooledWaveRegister Read(
        const ResidentWaveVgprPool& pool,
        std::uint32_t waveSlot,
        std::uint8_t architecturalRegister) const
    {
        const auto address =
            pool.Translate(waveSlot, architecturalRegister);

        if (!initialized_[address.row][address.bank])
        {
            throw std::logic_error(
                "VGPR read observed an uninitialized register");
        }

        return registers_[address.row][address.bank];
    }

    [[nodiscard]]
    std::pair<PooledWaveRegister, PooledWaveRegister> ReadPair(
        const ResidentWaveVgprPool& pool,
        std::uint32_t waveSlot,
        std::uint8_t register0,
        std::uint8_t register1) const
    {
        if (register0 == register1)
        {
            const auto value = Read(pool, waveSlot, register0);
            return {value, value};
        }

        if (MatrixRegisterBank(register0)
            == MatrixRegisterBank(register1))
        {
            throw std::logic_error(
                "distinct VGPR reads conflict in one bank class");
        }

        return {
            Read(pool, waveSlot, register0),
            Read(pool, waveSlot, register1)};
    }

    void Write(
        const ResidentWaveVgprPool& pool,
        std::uint32_t waveSlot,
        std::uint8_t architecturalRegister,
        const PooledWaveRegister& value,
        std::uint32_t laneMask = 0xFFFFFFFFU)
    {
        if (laneMask == 0U)
        {
            return;
        }

        const auto address =
            pool.Translate(waveSlot, architecturalRegister);
        auto& destination =
            registers_[address.row][address.bank];

        if (!initialized_[address.row][address.bank])
        {
            destination.fill(0U);
        }

        for (std::uint32_t lane = 0U;
             lane < kPooledVgprWaveLanes;
             ++lane)
        {
            if ((laneMask & (1U << lane)) != 0U)
            {
                destination[lane] = value[lane];
            }
        }

        initialized_[address.row][address.bank] = true;
    }

    [[nodiscard]] bool IsInitialized(
        const ResidentWaveVgprPool& pool,
        std::uint32_t waveSlot,
        std::uint8_t architecturalRegister) const
    {
        const auto address =
            pool.Translate(waveSlot, architecturalRegister);

        return initialized_[address.row][address.bank];
    }

private:
    using PhysicalRow =
        std::array<
            PooledWaveRegister,
            kVgprRegistersPerPhysicalRow>;

    std::vector<PhysicalRow> registers_;
    std::vector<
        std::array<bool, kVgprRegistersPerPhysicalRow>>
        initialized_;
};

struct MatrixCapturedPooledOperands
{
    std::array<
        PooledWaveRegister,
        kMatrixSourceRegistersPerLane> sourceA{};

    std::array<
        PooledWaveRegister,
        kMatrixSourceRegistersPerLane> sourceB{};

    std::array<
        PooledWaveRegister,
        kMatrixAccumulatorRegistersPerLane> accumulator{};
};

inline MatrixCapturedPooledOperands CaptureMatrixOperandsFromPool(
    const ResidentWaveVgprPool& pool,
    const PooledVgprStorage& storage,
    std::uint32_t waveSlot,
    std::uint8_t destinationBase,
    std::uint8_t sourceABase,
    std::uint8_t sourceBBase)
{
    if (!pool.MatrixFragmentsFit(
            waveSlot,
            destinationBase,
            sourceABase,
            sourceBBase))
    {
        throw std::out_of_range(
            "matrix fragments exceed the active pooled VGPR allocation");
    }

    MatrixCapturedPooledOperands captured{};

    for (std::uint32_t cycle = 0U;
         cycle < kMatrixRegisterCaptureCycles;
         ++cycle)
    {
        const auto schedule = MatrixCaptureSchedule(
            cycle,
            sourceABase,
            sourceBBase,
            destinationBase);

        const auto values = storage.ReadPair(
            pool,
            waveSlot,
            schedule.read0.architecturalRegister,
            schedule.read1.architecturalRegister);

        const auto store =
            [&](const MatrixCaptureRead& read,
                const PooledWaveRegister& value)
            {
                switch (read.fragment)
                {
                    case MatrixCaptureFragment::A:
                        captured.sourceA[
                            read.registerOffset] = value;
                        break;

                    case MatrixCaptureFragment::B:
                        captured.sourceB[
                            read.registerOffset] = value;
                        break;

                    case MatrixCaptureFragment::Accumulator:
                        captured.accumulator[
                            read.registerOffset] = value;
                        break;
                }
            };

        store(schedule.read0, values.first);
        store(schedule.read1, values.second);
    }

    return captured;
}

inline void WriteMatrixResultToPool(
    const ResidentWaveVgprPool& pool,
    PooledVgprStorage& storage,
    std::uint32_t waveSlot,
    std::uint8_t destinationBase,
    std::uint32_t writebackCycle,
    const PooledWaveRegister& value)
{
    const auto destination =
        MatrixWritebackRegister(
            writebackCycle,
            destinationBase);

    if (!pool.RegisterRangeFits(
            waveSlot,
            destination,
            1U))
    {
        throw std::out_of_range(
            "matrix writeback exceeds the active pooled VGPR allocation");
    }

    storage.Write(
        pool,
        waveSlot,
        destination,
        value);
}

} // namespace cgx1::matrix
