#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#define P 0xFFFFFFFF00000001ULL
static inline uint64_t mulmod(uint64_t a,uint64_t b){__uint128_t x=(__uint128_t)a*b;uint64_t lo=(uint64_t)x,hi=(uint64_t)(x>>64);uint64_t hh=hi>>32,hl=hi&0xFFFFFFFFULL;uint64_t t0=lo-hh;if(lo<hh)t0-=0xFFFFFFFFULL;uint64_t t1=hl*0xFFFFFFFFULL;uint64_t t2=t0+t1;if(t2<t0)t2+=0xFFFFFFFFULL;if(t2>=P)t2-=P;return t2;}
int main(int c,char**a){long n=atol(a[1]);uint64_t x=((uint64_t)305419896<<32)|2596069104ULL,y=((uint64_t)4275878552ULL<<32)|1985229328ULL;for(long i=0;i<n;i++)x=mulmod(x,y);printf("%llu %llu\n",(unsigned long long)(x>>32),(unsigned long long)(x&0xFFFFFFFFULL));return 0;}
