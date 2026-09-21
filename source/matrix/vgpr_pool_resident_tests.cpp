// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_matrix_vgpr_pool.hpp"
#include <cstdint>
#include <iostream>
#include <random>
using namespace cgx1::matrix;
#define CHECK(expression) do { if (!(expression)) { std::cerr << "[fail] " << #expression << " at line " << __LINE__ << '\n'; return 1; } } while (false)
template <class F> bool Throws(F&& f){try{f();}catch(const std::exception&){return true;}return false;}
PooledWaveRegister Pattern(std::uint32_t tag){PooledWaveRegister v{};for(std::uint32_t lane=0;lane<kPooledVgprWaveLanes;++lane)v[lane]=(tag<<8U)^lane;return v;}
bool PooledRequestCanReachController(const ResidentWaveVgprPool& pool,const PooledVgprStorage& storage,std::uint32_t waveSlot,std::uint8_t d,std::uint8_t a,std::uint8_t b){if(!IsValidMatrixRegisterLayout(d,a,b))return true;return storage.MatrixPreflight(pool,waveSlot,d,a,b);}
int main(){
 ResidentWaveVgprPool pool(64U,8U); PooledVgprStorage storage(64U);
 CHECK(pool.Reserve(0U,9U)); CHECK(pool.Allocation(0U).physicalRowCount==2U); CHECK(pool.Allocation(0U).architecturalRegisterCount==9U);
 CHECK(storage.InvalidateNextReservedRow(pool,0U)); CHECK(!pool.Sanitized(0U)); CHECK(storage.InvalidateNextReservedRow(pool,0U)); CHECK(pool.Sanitized(0U));
 storage.RestoreWrite(pool,0U,8U,Pattern(0x18U)); CHECK(Throws([&]{storage.RestoreWrite(pool,0U,9U,Pattern(0x19U));})); CHECK(pool.Activate(0U)); CHECK(!pool.RegisterRangeFits(0U,9U,1U)); CHECK(!pool.Release(0U,false)); CHECK(pool.Release(0U,true));
 CHECK(pool.Reserve(1U,72U)); storage.InvalidateReservedAllocation(pool,1U);
 for(std::uint32_t r=64;r<72;++r)storage.RestoreWrite(pool,1U,static_cast<std::uint8_t>(r),Pattern(0xA0U+r));
 for(std::uint32_t r=32;r<40;++r)storage.RestoreWrite(pool,1U,static_cast<std::uint8_t>(r),Pattern(0xC0U+r));
 CHECK(pool.Activate(1U)); CHECK(storage.MatrixPreflight(pool,1U,32U,64U,68U)); CHECK(PooledRequestCanReachController(pool,storage,1U,32U,64U,68U));
 CHECK(!IsValidMatrixRegisterLayout(33U,64U,68U)); CHECK(PooledRequestCanReachController(pool,storage,1U,33U,64U,68U));
 CHECK(pool.Reserve(2U,72U)); storage.InvalidateReservedAllocation(pool,2U);
 for(std::uint32_t r=64;r<72;++r)if(r!=69U)storage.RestoreWrite(pool,2U,static_cast<std::uint8_t>(r),{});
 for(std::uint32_t r=32;r<40;++r)storage.RestoreWrite(pool,2U,static_cast<std::uint8_t>(r),{});
 CHECK(pool.Activate(2U)); CHECK(!storage.MatrixPreflight(pool,2U,32U,64U,68U));
 std::mt19937 random(0xC6A12026U); ResidentWaveVgprPool sp(96U,16U); PooledVgprStorage ss(96U);
 for(std::uint32_t step=0;step<50000U;++step){const std::uint32_t slot=random()%16U;const auto state=sp.Allocation(slot).state;
  if(state==VgprAllocationState::Free){const std::uint32_t count=1U+(random()%256U);if(sp.Reserve(slot,count)){ss.InvalidateReservedAllocation(sp,slot);CHECK(sp.Activate(slot));}}
  else if((random()%5U)==0U){CHECK(sp.Release(slot,true));}
  else if(state==VgprAllocationState::Active){const auto count=sp.Allocation(slot).architecturalRegisterCount;const auto reg=static_cast<std::uint8_t>(random()%count);ss.Write(sp,slot,reg,Pattern(step^(slot<<16U)));CHECK(ss.IsInitialized(sp,slot,reg));CHECK(sp.Translate(slot,reg).bank==(reg%8U));}
  CHECK(sp.InvariantsHold()); CHECK(sp.OccupiedRows()<=sp.PhysicalRows());
 }
 std::cout<<"[pass] exact-count pooled VGPR restore, quiescent release, preflight, illegal-forwarding, and randomized lifecycle checks passed.\n";return 0;
}
