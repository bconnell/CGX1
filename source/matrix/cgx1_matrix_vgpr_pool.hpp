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
    std::uint32_t architecturalRegisterCount = 0U;
    std::uint32_t invalidatedRows = 0U;
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
            registerCount,
            0U};

        return true;
    }

    bool InvalidationStep(
        std::uint32_t waveSlot,
        std::uint32_t& physicalRow)
    {
        CheckWaveSlot(waveSlot);
        auto& allocation = allocations_[waveSlot];

        if (allocation.state != VgprAllocationState::Reserved
            || allocation.invalidatedRows >= allocation.physicalRowCount)
        {
            return false;
        }

        physicalRow = allocation.physicalRowBase
            + allocation.invalidatedRows;
        ++allocation.invalidatedRows;
        return true;
    }

    [[nodiscard]] bool Sanitized(std::uint32_t waveSlot) const
    {
        CheckWaveSlot(waveSlot);
        const auto& allocation = allocations_[waveSlot];
        return allocation.state == VgprAllocationState::Reserved
            && allocation.physicalRowCount != 0U
            && allocation.invalidatedRows == allocation.physicalRowCount;
    }

    bool Activate(std::uint32_t waveSlot)
    {
        CheckWaveSlot(waveSlot);
        if (!Sanitized(waveSlot))
        {
            return false;
        }

        allocations_[waveSlot].state = VgprAllocationState::Active;
        return true;
    }

    bool Release(
        std::uint32_t waveSlot,
        bool executionQuiescent = true)
    {
        CheckWaveSlot(waveSlot);
        const auto state = allocations_[waveSlot].state;

        if (state == VgprAllocationState::Free)
        {
            return false;
        }
        if (state == VgprAllocationState::Active && !executionQuiescent)
        {
            return false;
        }

        allocations_[waveSlot] = ResidentWaveVgprAllocation{};
        return true;
    }

    [[nodiscard]] bool RegisterRangeFits(
        std::uint32_t waveSlot,
        std::uint32_t registerBase,
        std::uint32_t registerCount) const
    {
        CheckWaveSlot(waveSlot);
        const auto& allocation = allocations_[waveSlot];

        if (allocation.state != VgprAllocationState::Active
            || registerCount == 0U
            || registerBase >= allocation.architecturalRegisterCount)
        {
            return false;
        }

        return registerCount
            <= allocation.architecturalRegisterCount - registerBase;
    }

    [[nodiscard]] bool ReservedRestoreRangeFits(
        std::uint32_t waveSlot,
        std::uint32_t registerBase,
        std::uint32_t registerCount) const
    {
        CheckWaveSlot(waveSlot);
        const auto& allocation = allocations_[waveSlot];

        if (!Sanitized(waveSlot)
            || registerCount == 0U
            || registerBase >= allocation.architecturalRegisterCount)
        {
            return false;
        }

        return registerCount
            <= allocation.architecturalRegisterCount - registerBase;
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
        if (!RegisterRangeFits(waveSlot, architecturalRegister, 1U))
        {
            throw std::out_of_range(
                "architectural VGPR is outside the exact active allocation");
        }

        return TranslateUnchecked(waveSlot, architecturalRegister);
    }

    [[nodiscard]] PhysicalVgprAddress TranslateForRestore(
        std::uint32_t waveSlot,
        std::uint8_t architecturalRegister) const
    {
        if (!ReservedRestoreRangeFits(waveSlot, architecturalRegister, 1U))
        {
            throw std::out_of_range(
                "architectural VGPR is outside the sanitized Reserved allocation");
        }

        return TranslateUnchecked(waveSlot, architecturalRegister);
    }

    [[nodiscard]] bool InvariantsHold() const noexcept
    {
        std::vector<bool> occupied(physicalRows_, false);

        for (const auto& allocation : allocations_)
        {
            if (allocation.state == VgprAllocationState::Free)
            {
                if (allocation.physicalRowCount != 0U
                    || allocation.architecturalRegisterCount != 0U
                    || allocation.invalidatedRows != 0U)
                {
                    return false;
                }
                continue;
            }

            if (allocation.physicalRowCount == 0U
                || allocation.architecturalRegisterCount == 0U
                || allocation.architecturalRegisterCount > kArchitecturalVgprsPerWave
                || VgprRowsForRegisterCount(allocation.architecturalRegisterCount)
                    != allocation.physicalRowCount
                || allocation.physicalRowBase >= physicalRows_
                || allocation.physicalRowCount
                    > physicalRows_ - allocation.physicalRowBase
                || allocation.invalidatedRows > allocation.physicalRowCount)
            {
                return false;
            }

            if (allocation.state == VgprAllocationState::Active
                && allocation.invalidatedRows != allocation.physicalRowCount)
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
    [[nodiscard]] PhysicalVgprAddress TranslateUnchecked(
        std::uint32_t waveSlot,
        std::uint8_t architecturalRegister) const
    {
        const auto& allocation = allocations_[waveSlot];
        return PhysicalVgprAddress{
            allocation.physicalRowBase
                + static_cast<std::uint32_t>(architecturalRegister)
                    / kVgprRegistersPerPhysicalRow,
            MatrixRegisterBank(architecturalRegister)};
    }

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

    bool InvalidateNextReservedRow(
        ResidentWaveVgprPool& pool,
        std::uint32_t waveSlot)
    {
        std::uint32_t physicalRow = 0U;
        if (!pool.InvalidationStep(waveSlot, physicalRow))
        {
            return false;
        }

        initialized_.at(physicalRow).fill(false);
        return true;
    }

    void InvalidateReservedAllocation(
        ResidentWaveVgprPool& pool,
        std::uint32_t waveSlot)
    {
        if (pool.Allocation(waveSlot).state != VgprAllocationState::Reserved)
        {
            throw std::logic_error(
                "VGPR storage invalidation requires a Reserved allocation");
        }

        while (InvalidateNextReservedRow(pool, waveSlot))
        {
        }
    }

    void RestoreWrite(
        const ResidentWaveVgprPool& pool,
        std::uint32_t waveSlot,
        std::uint8_t architecturalRegister,
        const PooledWaveRegister& value)
    {
        const auto address =
            pool.TranslateForRestore(waveSlot, architecturalRegister);
        registers_[address.row][address.bank] = value;
        initialized_[address.row][address.bank] = true;
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

    [[nodiscard]] bool MatrixPreflight(
        const ResidentWaveVgprPool& pool,
        std::uint32_t waveSlot,
        std::uint8_t destinationBase,
        std::uint8_t sourceABase,
        std::uint8_t sourceBBase) const
    {
        if (!pool.MatrixFragmentsFit(
                waveSlot,
                destinationBase,
                sourceABase,
                sourceBBase))
        {
            return false;
        }

        try
        {
            for (std::uint32_t offset = 0U;
                 offset < kMatrixSourceRegistersPerLane;
                 ++offset)
            {
                if (!IsInitialized(
                        pool,
                        waveSlot,
                        static_cast<std::uint8_t>(sourceABase + offset))
                    || !IsInitialized(
                        pool,
                        waveSlot,
                        static_cast<std::uint8_t>(sourceBBase + offset)))
                {
                    return false;
                }
            }

            for (std::uint32_t offset = 0U;
                 offset < kMatrixAccumulatorRegistersPerLane;
                 ++offset)
            {
                if (!IsInitialized(
                        pool,
                        waveSlot,
                        static_cast<std::uint8_t>(destinationBase + offset)))
                {
                    return false;
                }
            }
        }
        catch (const std::exception&)
        {
            return false;
        }

        return true;
    }

private:
    using PhysicalRow =
        std::array<
            PooledWaveRegister,
            kVgprRegistersPerPhysicalRow>;

    std::vector<PhysicalRow> registers_;
    std::vector<std::array<bool, kVgprRegistersPerPhysicalRow>> initialized_;
};

struct MatrixCapturedPooledOperands
{
    std::array<PooledWaveRegister, kMatrixSourceRegistersPerLane> sourceA{};
    std::array<PooledWaveRegister, kMatrixSourceRegistersPerLane> sourceB{};
    std::array<PooledWaveRegister, kMatrixAccumulatorRegistersPerLane> accumulator{};
};

inline MatrixCapturedPooledOperands CaptureMatrixOperandsFromPool(
    const ResidentWaveVgprPool& pool,
    const PooledVgprStorage& storage,
    std::uint32_t waveSlot,
    std::uint8_t destinationBase,
    std::uint8_t sourceABase,
    std::uint8_t sourceBBase)
{
    if (!storage.MatrixPreflight(
            pool,
            waveSlot,
            destinationBase,
            sourceABase,
            sourceBBase))
    {
        throw std::logic_error(
            "matrix pooled-VGPR preflight failed");
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
                        captured.sourceA[read.registerOffset] = value;
                        break;
                    case MatrixCaptureFragment::B:
                        captured.sourceB[read.registerOffset] = value;
                        break;
                    case MatrixCaptureFragment::Accumulator:
                        captured.accumulator[read.registerOffset] = value;
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
        MatrixWritebackRegister(writebackCycle, destinationBase);

    if (!pool.RegisterRangeFits(waveSlot, destination, 1U))
    {
        throw std::out_of_range(
            "matrix writeback exceeds the exact active VGPR allocation");
    }

    storage.Write(pool, waveSlot, destination, value);
}

} // namespace cgx1::matrix
