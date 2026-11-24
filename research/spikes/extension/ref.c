// Reference for the extension-product chain: native 64-bit limbs, F_p[X]/(X^3 - 2), p = 2^64 - 2^32 + 1.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#define P 0xFFFFFFFF00000001ULL
static inline uint64_t red(__uint128_t x){uint64_t lo=(uint64_t)x,hi=(uint64_t)(x>>64),hh=hi>>32,hl=hi&0xFFFFFFFFULL;uint64_t t0=lo-hh;if(lo<hh)t0-=0xFFFFFFFFULL;uint64_t t1=hl*0xFFFFFFFFULL;uint64_t t2=t0+t1;if(t2<t0)t2+=0xFFFFFFFFULL;if(t2>=P)t2-=P;return t2;}
static inline uint64_t mul(uint64_t a,uint64_t b){return red((__uint128_t)a*b);}
static inline uint64_t add(uint64_t a,uint64_t b){uint64_t s=a+b;if(s<a||s>=P)s-=P;return s;}
int main(int c,char**v){long n=atol(v[1]);
 uint64_t x[3]={((uint64_t)305419896<<32)|2596069104ULL,((uint64_t)19088743<<32)|2309737967ULL,((uint64_t)4275878552ULL<<32)|1985229328ULL};
 uint64_t y[3]={((uint64_t)2616525818ULL<<32)|2952618119ULL,((uint64_t)1109109337<<32)|1539779615ULL,((uint64_t)507698712<<32)|958177034ULL};
 for(long i=0;i<n;i++){uint64_t d1=add(y[1],y[1]),d2=add(y[2],y[2]);
  uint64_t c0=add(add(mul(x[0],y[0]),mul(x[1],d2)),mul(x[2],d1));
  uint64_t c1=add(add(mul(x[0],y[1]),mul(x[1],y[0])),mul(x[2],d2));
  uint64_t c2=add(add(mul(x[0],y[2]),mul(x[1],y[1])),mul(x[2],y[0]));x[0]=c0;x[1]=c1;x[2]=c2;}
 for(int i=0;i<3;i++)printf("%llu %llu%s",(unsigned long long)(x[i]>>32),(unsigned long long)(x[i]&0xFFFFFFFFULL),i<2?" ":"\n");return 0;}
