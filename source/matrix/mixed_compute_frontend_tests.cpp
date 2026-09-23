// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include <cstdint>
#include <iostream>
#define CHECK(x) do{if(!(x)){std::cerr<<"[fail] " #x " line "<<__LINE__<<'\n';return 1;}}while(false)
struct Result{bool matrix,vector;};
Result Issue(bool matrixAccepted,bool vectorValid,bool vectorPipeReady,bool matrixOrdinaryReady){Result r{};r.matrix=matrixAccepted;r.vector=!matrixAccepted&&vectorValid&&vectorPipeReady&&matrixOrdinaryReady;return r;}
bool MatrixRuntime(bool fullWave,bool layoutLegal,bool preflight,bool vectorHazardReady){return !fullWave||!layoutLegal||(preflight&&vectorHazardReady);}
int main(){CHECK(MatrixRuntime(false,true,false,false));CHECK(MatrixRuntime(true,false,false,false));CHECK(!MatrixRuntime(true,true,false,true));CHECK(!MatrixRuntime(true,true,true,false));CHECK(MatrixRuntime(true,true,true,true));for(int m=0;m<2;m++)for(int v=0;v<2;v++)for(int p=0;p<2;p++)for(int o=0;o<2;o++){auto r=Issue(m,v,p,o);CHECK(!(r.matrix&&r.vector));if(m)CHECK(r.matrix&&!r.vector);else if(v&&p&&o)CHECK(r.vector);}std::cout<<"[pass] mixed compute frontend admission checks passed.\n";return 0;}
