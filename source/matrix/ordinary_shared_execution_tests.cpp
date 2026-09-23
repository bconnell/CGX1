// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include <cstdint>
#include <iostream>
#include <random>
#define CHECK(x) do { if(!(x)){ std::cerr<<"[fail] " #x " line "<<__LINE__<<'\n'; return 1; } } while(false)
struct Addr{std::uint32_t row,bank;bool valid;};
Addr Map(std::uint32_t base,std::uint32_t count,std::uint32_t reg,std::uint32_t rows){const auto row=base+reg/8U;return{row,reg%8U,count>0U&&reg<count&&row<rows};}
enum class Mode{Invalid,Alias,Parallel,Split};
Mode Classify(const Addr&a,const Addr&b,std::uint32_t ra,std::uint32_t rb){if(!a.valid||!b.valid)return Mode::Invalid;if(ra==rb&&a.row==b.row&&a.bank==b.bank)return Mode::Alias;if(a.bank==b.bank)return Mode::Split;return Mode::Parallel;}
struct Arb{bool preferRestore=false;}; enum class Grant{None,MatrixRead,MatrixWrite,OrdinaryRead,OrdinaryWrite,Restore};
Grant Pick(Arb&s,bool mr,bool mw,bool orr,bool orw,bool rr){if(mr&&mw)return Grant::None;if(mr)return Grant::MatrixRead;if(mw)return Grant::MatrixWrite;const bool o=orr||orw;if(o&&rr){const auto g=s.preferRestore?Grant::Restore:(orr?Grant::OrdinaryRead:Grant::OrdinaryWrite);s.preferRestore=!s.preferRestore;return g;}if(orr)return Grant::OrdinaryRead;if(orw)return Grant::OrdinaryWrite;if(rr)return Grant::Restore;return Grant::None;}
bool ReleaseSafe(bool q,bool mb,bool vb,bool mrf,bool vrf,bool split,bool restore){return q&&!mb&&!vb&&!mrf&&!vrf&&!split&&!restore;}
int main(){auto a=Map(3,9,8,64),b=Map(3,9,9,64);CHECK(a.valid&&!b.valid&&a.row==4&&a.bank==0);auto x=Map(2,72,64,128),y=Map(2,72,56,128);CHECK(Classify(x,y,64,56)==Mode::Split);CHECK(Classify(x,x,64,64)==Mode::Alias);Arb s{};CHECK(Pick(s,true,false,true,false,true)==Grant::MatrixRead);int o=0,r=0;for(int i=0;i<1000;i++){auto g=Pick(s,false,false,true,false,true);o+=g==Grant::OrdinaryRead;r+=g==Grant::Restore;}CHECK(o==500&&r==500);CHECK(!ReleaseSafe(true,true,false,false,false,false,false));CHECK(ReleaseSafe(true,false,false,false,false,false,false));std::mt19937 rng(0xC6A12026U);for(int i=0;i<100000;i++){auto count=1U+(rng()%256U),base=rng()%64U,r0=rng()%256U,r1=rng()%256U;auto p0=Map(base,count,r0,128),p1=Map(base,count,r1,128);auto m=Classify(p0,p1,r0,r1);if(r0>=count||r1>=count||p0.row>=128||p1.row>=128)CHECK(m==Mode::Invalid);else if(r0==r1)CHECK(m==Mode::Alias);else if((r0%8U)==(r1%8U))CHECK(m==Mode::Split);else CHECK(m==Mode::Parallel);}std::cout<<"[pass] ordinary/shared pooled VGPR reference checks passed.\n";return 0;}
