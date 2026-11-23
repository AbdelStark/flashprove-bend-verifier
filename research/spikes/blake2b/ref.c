#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
static const uint64_t IV[8]={0x6a09e667f3bcc908ULL,0xbb67ae8584caa73bULL,0x3c6ef372fe94f82bULL,0xa54ff53a5f1d36f1ULL,0x510e527fade682d1ULL,0x9b05688c2b3e6c1fULL,0x1f83d9abfb41bd6bULL,0x5be0cd19137e2179ULL};
static const uint8_t SG[12][16]={{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15},{14,10,4,8,9,15,13,6,1,12,0,2,11,7,5,3},{11,8,12,0,5,2,15,13,10,14,3,6,7,1,9,4},{7,9,3,1,13,12,11,14,2,6,5,10,4,0,15,8},{9,0,5,7,2,4,10,15,14,1,11,12,6,8,3,13},{2,12,6,10,0,11,8,3,4,13,7,5,15,14,1,9},{12,5,1,15,14,13,4,10,0,7,6,3,9,2,8,11},{13,11,7,14,12,1,3,9,5,0,15,4,8,6,2,10},{6,15,14,9,11,3,0,8,12,2,13,7,1,4,10,5},{10,2,8,4,7,6,1,5,15,11,9,14,3,12,13,0},{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15},{14,10,4,8,9,15,13,6,1,12,0,2,11,7,5,3}};
static inline uint64_t rotr(uint64_t x,int n){return (x>>n)|(x<<(64-n));}
#define G(a,b,c,d,x,y) v[a]+=v[b]+x; v[d]=rotr(v[d]^v[a],32); v[c]+=v[d]; v[b]=rotr(v[b]^v[c],24); v[a]+=v[b]+y; v[d]=rotr(v[d]^v[a],16); v[c]+=v[d]; v[b]=rotr(v[b]^v[c],63);
static void F(uint64_t h[8],const uint64_t m[16],uint64_t t,int f){uint64_t v[16];for(int i=0;i<8;i++){v[i]=h[i];v[i+8]=IV[i];}v[12]^=t;if(f)v[14]=~v[14];
 for(int r=0;r<12;r++){const uint8_t*s=SG[r];G(0,4,8,12,m[s[0]],m[s[1]])G(1,5,9,13,m[s[2]],m[s[3]])G(2,6,10,14,m[s[4]],m[s[5]])G(3,7,11,15,m[s[6]],m[s[7]])G(0,5,10,15,m[s[8]],m[s[9]])G(1,6,11,12,m[s[10]],m[s[11]])G(2,7,8,13,m[s[12]],m[s[13]])G(3,4,9,14,m[s[14]],m[s[15]])}
 for(int i=0;i<8;i++)h[i]^=v[i]^v[i+8];}
int main(int c,char**a){long n=c>1?atol(a[1]):1000;uint64_t h[8],m[16];for(int i=0;i<8;i++)h[i]=IV[i];h[0]^=0x01010040;for(int i=0;i<16;i++){m[i]=0;for(int j=0;j<8;j++)m[i]|=(uint64_t)(8*i+j)<<(8*j);}
 for(long i=0;i<n;i++)F(h,m,128,0);for(int i=0;i<8;i++)printf("%016llx ",(unsigned long long)h[i]);printf("\n");return 0;}
