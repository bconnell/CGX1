// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_context.hpp"
#include "cgx1_matrix_vgpr_pool.hpp"
#include <cstdint>
#include <iostream>
#include <random>
using namespace cgx1::matrix;
#define CHECK(expression) do { if (!(expression)) { std::cerr << "[fail] " << #expression << " at line " << __LINE__; ::cgx1::testing::WriteRandomTestFailureContext(std::cerr); std::cerr << '\n'; return 1; } } while (false)
template <class F> bool Throws(F&& f){try{f();}catch(const std::exception&){return true;}return false;}
PooledWaveRegister Pattern(std::uint32_t tag){PooledWaveRegister v{};for(std::uint32_t lane=0;lane<kPooledVgprWaveLanes;++lane)v[lane]=(tag<<8U)^lane;return v;}
bool PooledRequestCanReachController(const ResidentWaveVgprPool& pool,const PooledVgprStorage& storage,std::uint32_t waveSlot,std::uint8_t d,std::uint8_t a,std::uint8_t b){if(!IsValidMatrixRegisterLayout(d,a,b))return true;return storage.MatrixPreflight(pool,waveSlot,d,a,b);}
int main(){
 ResidentWaveVgprPool pool(64U,8U); PooledVgprStorage storage(64U);
 {
     auto&& check_action_reserve_15_1 = (pool.Reserve(0U,9U));
     CHECK(check_action_reserve_15_1);
 } CHECK(pool.Allocation(0U).physicalRowCount==2U); CHECK(pool.Allocation(0U).architecturalRegisterCount==9U);
 CHECK(storage.InvalidateNextReservedRow(pool,0U)); CHECK(!pool.Sanitized(0U)); CHECK(storage.InvalidateNextReservedRow(pool,0U)); CHECK(pool.Sanitized(0U));
 storage.RestoreWrite(pool,0U,8U,Pattern(0x18U));
 const auto restoreWriteThrew = Throws([&]{storage.RestoreWrite(pool,0U,9U,Pattern(0x19U));});
 CHECK(restoreWriteThrew);
 {
    auto&& check_action_activate_17_3 = (pool.Activate(0U));
    CHECK(check_action_activate_17_3);
} CHECK(!pool.RegisterRangeFits(0U,9U,1U)); {
    auto&& check_action_release_17_4 = (pool.Release(0U,false));
    CHECK(!check_action_release_17_4);
} {
    auto&& check_action_release_17_5 = (pool.Release(0U,true));
    CHECK(check_action_release_17_5);
}
 {
     auto&& check_action_reserve_18_6 = (pool.Reserve(1U,72U));
     CHECK(check_action_reserve_18_6);
 } storage.InvalidateReservedAllocation(pool,1U);
 for(std::uint32_t r=64;r<72;++r)storage.RestoreWrite(pool,1U,static_cast<std::uint8_t>(r),Pattern(0xA0U+r));
 for(std::uint32_t r=32;r<40;++r)storage.RestoreWrite(pool,1U,static_cast<std::uint8_t>(r),Pattern(0xC0U+r));
 {
     auto&& check_action_activate_21_7 = (pool.Activate(1U));
     CHECK(check_action_activate_21_7);
 } CHECK(storage.MatrixPreflight(pool,1U,32U,64U,68U)); CHECK(PooledRequestCanReachController(pool,storage,1U,32U,64U,68U));
 CHECK(!IsValidMatrixRegisterLayout(33U,64U,68U)); CHECK(PooledRequestCanReachController(pool,storage,1U,33U,64U,68U));
 {
     auto&& check_action_reserve_23_8 = (pool.Reserve(2U,72U));
     CHECK(check_action_reserve_23_8);
 } storage.InvalidateReservedAllocation(pool,2U);
 for(std::uint32_t r=64;r<72;++r)if(r!=69U)storage.RestoreWrite(pool,2U,static_cast<std::uint8_t>(r),{});
 for(std::uint32_t r=32;r<40;++r)storage.RestoreWrite(pool,2U,static_cast<std::uint8_t>(r),{});
 {
     auto&& check_action_activate_26_9 = (pool.Activate(2U));
     CHECK(check_action_activate_26_9);
 } CHECK(!storage.MatrixPreflight(pool,2U,32U,64U,68U));
 constexpr std::uint32_t seed=0xC6A12026U; std::mt19937 random(seed); ResidentWaveVgprPool sp(96U,16U); PooledVgprStorage ss(96U);
 for(std::uint32_t step=0;step<50000U;++step){const std::uint32_t slot=random()%16U;::cgx1::testing::SetRandomTestFailureContext("ResidentPoolRandomizedLifecycle",seed,step,slot);const auto state=sp.Allocation(slot).state;
  if(state==VgprAllocationState::Free){const std::uint32_t count=1U+(random()%256U);if(sp.Reserve(slot,count)){ss.InvalidateReservedAllocation(sp,slot);{
    auto&& check_action_activate_29_10 = (sp.Activate(slot));
    CHECK(check_action_activate_29_10);
}}}
  else if((random()%5U)==0U){{
    auto&& check_action_release_30_11 = (sp.Release(slot,true));
    CHECK(check_action_release_30_11);
}}
  else if(state==VgprAllocationState::Active){const auto count=sp.Allocation(slot).architecturalRegisterCount;const auto reg=static_cast<std::uint8_t>(random()%count);ss.Write(sp,slot,reg,Pattern(step^(slot<<16U)));CHECK(ss.IsInitialized(sp,slot,reg));CHECK(sp.Translate(slot,reg).bank==(reg%8U));}
  CHECK(sp.InvariantsHold()); CHECK(sp.OccupiedRows()<=sp.PhysicalRows());
 }
 ::cgx1::testing::ClearRandomTestFailureContext();
 std::cout<<"[pass] exact-count pooled VGPR restore, quiescent release, preflight, illegal-forwarding, and randomized lifecycle checks passed.\n";return 0;
}
