// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include <cstdint>
#include <iostream>
#define CHECK(x) do{if(!(x)){std::cerr<<"[fail] " #x " line "<<__LINE__<<'\n';return 1;}}while(false)
struct P{std::uint32_t limit=2,burst=0;bool pending=false,seen=false;bool allow(bool legal,bool compete)const{return !legal||!compete||!pending;}void tick(bool valid,bool legal,bool ready,bool compete){bool accepted=valid&&legal&&ready&&allow(legal,compete);if(!compete){burst=0;pending=false;seen=false;return;}if(pending){if(ready)seen=true;if(seen&&!ready){burst=0;pending=false;seen=false;}return;}if(accepted&&++burst>=limit)pending=true;}};
int main(){P p;bool a0=0,a16=0,a32=0,a48=0;for(int c=0;c<=49;c++){bool ready=c==0||c==16||c==32||c==48;bool a=ready&&p.allow(true,true);if(c==0)a0=a;if(c==16)a16=a;if(c==32)a32=a;if(c==48)a48=a;p.tick(true,true,ready,true);}CHECK(a0&&a16&&!a32&&a48);p.pending=true;CHECK(p.allow(false,true));std::cout<<"[pass] cadence-accurate matrix service-window checks passed.\n";return 0;}
