// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell

#include "cgx1_matrix_vgpr_pool.hpp"

#include <array>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <optional>
#include <random>
#include <stdexcept>
#include <vector>

using namespace cgx1::matrix;

template <class Function>
bool Throws(Function&& function)
{
    try
    {
        function();
    }
    catch (const std::exception&)
    {
        return true;
    }

    return false;
}

PooledWaveRegister Pattern(std::uint32_t tag)
{
    PooledWaveRegister value{};

    for (std::uint32_t lane = 0U;
         lane < kPooledVgprWaveLanes;
         ++lane)
    {
        value[lane] = (tag << 8U) ^ lane;
    }

    return value;
}

std::optional<std::uint32_t> ExpectedFirstFit(
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

        for (std::uint32_t row = 0U;
             row < rowsNeeded;
             ++row)
        {
            free = free && !occupied[base + row];
        }

        if (free)
        {
            return base;
        }
    }

    return std::nullopt;
}

int main()
{
    assert(VgprRowsForRegisterCount(1U) == 1U);
    assert(VgprRowsForRegisterCount(8U) == 1U);
    assert(VgprRowsForRegisterCount(9U) == 2U);
    assert(VgprRowsForRegisterCount(256U) == 32U);
    assert(Throws(
        [] { (void)VgprRowsForRegisterCount(0U); }));

    for (std::uint32_t mask = 0U;
         mask < 256U;
         ++mask)
    {
        std::vector<bool> occupied(8U, false);

        for (std::uint32_t row = 0U;
             row < 8U;
             ++row)
        {
            occupied[row] =
                (mask & (1U << row)) != 0U;
        }

        for (std::uint32_t rowsNeeded = 1U;
             rowsNeeded <= 8U;
             ++rowsNeeded)
        {
            assert(
                FindFirstFitVgprRows(
                    occupied,
                    rowsNeeded)
                == ExpectedFirstFit(
                    occupied,
                    rowsNeeded));
        }
    }

    ResidentWaveVgprPool pool(32U, 8U);
    PooledVgprStorage storage(32U);

    assert(pool.Reserve(0U, 72U));
    assert(
        pool.Allocation(0U).state
        == VgprAllocationState::Reserved);
    assert(!pool.Activate(0U));

    assert(Throws(
        [&] {
            (void)pool.Translate(
                0U,
                0U);
        }));

    storage.InvalidateReservedAllocation(
        pool,
        0U);

    assert(pool.Activate(0U));
    assert(!pool.Reserve(0U, 8U));

    assert(pool.MatrixFragmentsFit(
        0U,
        32U,
        64U,
        68U));

    assert(!pool.MatrixFragmentsFit(
        0U,
        72U,
        64U,
        68U));

    for (std::uint32_t reg = 0U;
         reg < 72U;
         ++reg)
    {
        const auto address =
            pool.Translate(
                0U,
                static_cast<std::uint8_t>(reg));

        assert(address.bank == reg % 8U);
        assert(address.row == reg / 8U);
    }

    assert(pool.Reserve(3U, 8U));
    storage.InvalidateReservedAllocation(
        pool,
        3U);
    assert(pool.Activate(3U));

    const auto wave0Register0 =
        pool.Translate(0U, 0U);
    const auto wave3Register0 =
        pool.Translate(3U, 0U);

    assert(
        wave0Register0.bank
        == wave3Register0.bank);

    assert(
        wave0Register0.row
        != wave3Register0.row);

    storage.Write(
        pool,
        3U,
        0U,
        Pattern(0x33U));

    storage.Write(
        pool,
        0U,
        0U,
        Pattern(0x11U));

    assert(
        storage.Read(
            pool,
            3U,
            0U)
        == Pattern(0x33U));

    assert(
        storage.Read(
            pool,
            0U,
            0U)
        == Pattern(0x11U));

    pool.Release(3U);

    for (std::uint32_t reg = 0U;
         reg < 4U;
         ++reg)
    {
        storage.Write(
            pool,
            0U,
            static_cast<std::uint8_t>(64U + reg),
            Pattern(0xA0U + reg));

        storage.Write(
            pool,
            0U,
            static_cast<std::uint8_t>(68U + reg),
            Pattern(0xB0U + reg));
    }

    for (std::uint32_t reg = 0U;
         reg < 8U;
         ++reg)
    {
        storage.Write(
            pool,
            0U,
            static_cast<std::uint8_t>(32U + reg),
            Pattern(0xC0U + reg));
    }

    const auto captured =
        CaptureMatrixOperandsFromPool(
            pool,
            storage,
            0U,
            32U,
            64U,
            68U);

    for (std::uint32_t reg = 0U;
         reg < 4U;
         ++reg)
    {
        assert(
            captured.sourceA[reg]
            == Pattern(0xA0U + reg));

        assert(
            captured.sourceB[reg]
            == Pattern(0xB0U + reg));
    }

    for (std::uint32_t reg = 0U;
         reg < 8U;
         ++reg)
    {
        assert(
            captured.accumulator[reg]
            == Pattern(0xC0U + reg));
    }

    const auto aliased =
        CaptureMatrixOperandsFromPool(
            pool,
            storage,
            0U,
            32U,
            64U,
            64U);

    for (std::uint32_t reg = 0U;
         reg < 4U;
         ++reg)
    {
        assert(
            aliased.sourceA[reg]
            == aliased.sourceB[reg]);
    }

    assert(Throws(
        [&] {
            (void)storage.ReadPair(
                pool,
                0U,
                64U,
                72U);
        }));

    for (std::uint32_t cycle = 0U;
         cycle < 8U;
         ++cycle)
    {
        const auto result =
            Pattern(0xD0U + cycle);

        WriteMatrixResultToPool(
            pool,
            storage,
            0U,
            32U,
            cycle,
            result);

        assert(
            storage.Read(
                pool,
                0U,
                static_cast<std::uint8_t>(
                    32U + cycle))
            == result);
    }

    storage.Write(
        pool,
        0U,
        0U,
        Pattern(0xEEU));

    pool.Release(0U);

    assert(pool.Reserve(1U, 8U));

    assert(
        pool.Allocation(1U).physicalRowBase
        == 0U);

    storage.InvalidateReservedAllocation(
        pool,
        1U);

    assert(pool.Activate(1U));

    assert(Throws(
        [&] {
            (void)storage.Read(
                pool,
                1U,
                0U);
        }));

    const auto partial =
        Pattern(0x44U);

    storage.Write(
        pool,
        1U,
        0U,
        partial,
        1U);

    const auto sanitized =
        storage.Read(
            pool,
            1U,
            0U);

    assert(
        sanitized[0]
        == partial[0]);

    for (std::uint32_t lane = 1U;
         lane < kPooledVgprWaveLanes;
         ++lane)
    {
        assert(sanitized[lane] == 0U);
    }

    pool.Release(1U);

    assert(pool.Reserve(2U, 8U));

    storage.InvalidateReservedAllocation(
        pool,
        2U);

    assert(pool.Activate(2U));

    storage.Write(
        pool,
        2U,
        0U,
        partial,
        0U);

    assert(
        !storage.IsInitialized(
            pool,
            2U,
            0U));

    std::mt19937 random(0xC6A12026U);

    ResidentWaveVgprPool stressPool(
        64U,
        16U);

    PooledVgprStorage stressStorage(64U);

    std::array<std::uint32_t, 16U>
        generations{};

    for (std::uint32_t step = 0U;
         step < 20000U;
         ++step)
    {
        const std::uint32_t slot =
            random() % 16U;

        const auto state =
            stressPool.Allocation(slot).state;

        if (state == VgprAllocationState::Free)
        {
            const std::uint32_t registers =
                1U + (random() % 256U);

            if (stressPool.Reserve(
                    slot,
                    registers))
            {
                stressStorage
                    .InvalidateReservedAllocation(
                        stressPool,
                        slot);

                assert(
                    stressPool.Activate(
                        slot));

                ++generations[slot];
            }
        }
        else if ((random() % 5U) == 0U)
        {
            stressPool.Release(slot);
        }
        else if (
            state
            == VgprAllocationState::Active)
        {
            const std::uint32_t rows =
                stressPool
                    .Allocation(slot)
                    .physicalRowCount;

            const std::uint32_t registers =
                rows * 8U;

            const auto reg =
                static_cast<std::uint8_t>(
                    random() % registers);

            const auto value =
                Pattern(
                    (slot << 16U)
                    ^ generations[slot]
                    ^ step);

            stressStorage.Write(
                stressPool,
                slot,
                reg,
                value);

            assert(
                stressStorage.Read(
                    stressPool,
                    slot,
                    reg)
                == value);

            const auto address =
                stressPool.Translate(
                    slot,
                    reg);

            assert(
                address.bank
                == reg % 8U);
        }

        assert(
            stressPool.InvariantsHold());

        assert(
            stressPool.OccupiedRows()
            <= stressPool.PhysicalRows());
    }

    std::cout
        << "[pass] pooled resident-wave VGPR allocation, "
        << "storage, lifecycle, matrix capture, writeback, "
        << "exhaustive first-fit, and randomized stress "
        << "checks passed.\n";

    return 0;
}
