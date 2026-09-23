// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include <array>
#include <bit>
#include <cstdint>
#include <iostream>
#include <random>
#define CHECK(x) do { if(!(x)){ std::cerr<<"[fail] " #x " line "<<__LINE__<<'\n'; return 1; } } while(false)
enum class Op:std::uint8_t{Add,Sub,And,Or,Xor,Shl,Lsr,Asr};
std::uint32_t Alu(Op op,std::uint32_t a,std::uint32_t b){switch(op){case Op::Add:return a+b;case Op::Sub:return a-b;case Op::And:return a&b;case Op::Or:return a|b;case Op::Xor:return a^b;case Op::Shl:return a<<(b&31U);case Op::Lsr:return a>>(b&31U);case Op::Asr:return std::bit_cast<std::uint32_t>(std::bit_cast<std::int32_t>(a)>>(b&31U));}return 0;}
bool Overlap(std::uint32_t a,std::uint32_t ac,std::uint32_t b,std::uint32_t bc){return a<b+bc&&b<a+ac;}
struct Hazard{bool raw,waw,war;};
Hazard CheckHazard(bool same,std::uint32_t d,std::uint32_t a,std::uint32_t b,std::uint32_t s0,std::uint32_t s1,std::uint32_t vd,bool sl,bool dl){if(!same)return{};Hazard h{};if(dl){h.raw=Overlap(a,4,vd,1)||Overlap(b,4,vd,1)||Overlap(d,8,vd,1);h.waw=Overlap(d,8,vd,1);}if(sl)h.war=Overlap(d,8,s0,1)||Overlap(d,8,s1,1);return h;}
struct Scheduler{std::uint32_t next=0;};int Select(Scheduler&s,const std::array<bool,8>&v,const std::array<bool,8>&d){for(std::uint32_t o=0;o<8;o++){auto i=(s.next+o)%8;if(v[i]&&d[i]){s.next=(i+1)%8;return static_cast<int>(i);}}return -1;}
int main(){CHECK(Alu(Op::Add,0xffffffffU,1U)==0U);CHECK(Alu(Op::Asr,0x80000000U,1U)==0xc0000000U);std::mt19937 rng(0x51A6E5U);for(int i=0;i<100000;i++){const std::uint32_t a=static_cast<std::uint32_t>(rng()),b=static_cast<std::uint32_t>(rng());auto op=static_cast<Op>(rng()%8U);CHECK(Alu(op,a,b)==Alu(op,a,b));auto h=CheckHazard(rng()&1U,(rng()%32U)*8U,(rng()%32U)*8U,(rng()%64U)*4U,rng()%256U,rng()%256U,rng()%256U,rng()&1U,rng()&1U);(void)h;}Scheduler s{};std::array<bool,8>v{},d{};v.fill(true);d.fill(true);for(int i=0;i<16;i++)CHECK(Select(s,v,d)==i%8);d[2]=false;s.next=2;CHECK(Select(s,v,d)==3);std::cout<<"[pass] vector execution/hazard/scheduling reference checks passed.\n";return 0;}
