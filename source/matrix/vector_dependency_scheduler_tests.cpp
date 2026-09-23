// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include <array>
#include <bitset>
#include <cstdint>
#include <iostream>
#include <random>
#define CHECK(x) do{if(!(x)){std::cerr<<"[fail] " #x " line "<<__LINE__<<'\n';return 1;}}while(false)
struct D{bool raw,waw,war;bool ready()const{return !(raw||waw||war);}};
D Dep(const std::bitset<256>&s,const std::bitset<256>&d,std::uint8_t s0,std::uint8_t s1,std::uint8_t dst){return{d.test(s0)||d.test(s1),d.test(dst),s.test(dst)};}
struct S{std::uint32_t next=0;};int Pick(S&x,const std::array<bool,8>&v,const std::array<bool,8>&r,bool accept){for(std::uint32_t o=0;o<8;o++){auto i=(x.next+o)%8;if(v[i]&&r[i]){if(accept)x.next=(i+1)%8;return static_cast<int>(i);}}return-1;}
int main(){std::bitset<256>s,d;s.set(64);d.set(32);CHECK(Dep(s,d,32,7,9).raw);CHECK(Dep(s,d,7,8,64).war);std::array<bool,8>v{},r{};v[0]=v[5]=1;r[5]=1;S q{};CHECK(Pick(q,v,r,false)==5);CHECK(q.next==0);CHECK(Pick(q,v,r,true)==5);std::mt19937 g(0x5c4ed123U);for(int i=0;i<100000;i++){s.reset();d.reset();for(int b=0;b<256;b++){if((g()&31U)==0)s.set(b);if((g()&31U)==0)d.set(b);}auto a=static_cast<std::uint8_t>(g()),b=static_cast<std::uint8_t>(g()),c=static_cast<std::uint8_t>(g());auto h=Dep(s,d,a,b,c);CHECK(h.raw==(d.test(a)||d.test(b)));CHECK(h.waw==d.test(c));CHECK(h.war==s.test(c));}std::cout<<"[pass] per-wave vector dependency scheduler checks passed.\n";return 0;}
