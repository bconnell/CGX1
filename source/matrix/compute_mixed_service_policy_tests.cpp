// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include <cstdint>
#include <iostream>
#include <random>
#define CHECK(x) do{if(!(x)){std::cerr<<"[fail] " #x " line "<<__LINE__<<'\n';return 1;}}while(false)
struct P{std::uint32_t limit=4,burst=0;bool pending=false;bool allow(bool v,bool r)const{return !(pending&&(v||r));}void tick(bool m,bool vw,bool va,bool rw,bool ra){bool c=vw||rw,p=va||ra;if(!c){burst=0;pending=false;}else if(pending){if(p){burst=0;pending=false;}}else if(m){if(++burst>=limit)pending=true;}}};
int main(){P p;for(int i=0;i<4;i++){CHECK(p.allow(true,false));p.tick(true,true,false,false,false);}CHECK(!p.allow(true,false));for(int i=0;i<100;i++){p.tick(false,true,false,false,false);CHECK(!p.allow(true,false));}p.tick(false,true,true,false,false);CHECK(p.allow(true,false));for(int i=0;i<4;i++)p.tick(true,false,false,true,false);CHECK(!p.allow(false,true));p.tick(false,false,false,true,true);CHECK(p.allow(false,true));std::mt19937 g(0xfa17c0deU);P q;for(int i=0;i<100000;i++){bool vw=g()&1U,rw=g()&1U,va=vw&&((g()&15U)==0),ra=rw&&((g()&15U)==0),ma=q.allow(vw,rw)&&((g()&3U)==0);if(q.pending&&(vw||rw)&&!(va||ra))CHECK(!q.allow(vw,rw));q.tick(ma,vw,va,rw,ra);}std::cout<<"[pass] compute mixed-service progress policy checks passed.\n";return 0;}
