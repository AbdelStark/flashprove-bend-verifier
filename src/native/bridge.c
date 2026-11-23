// The pinned compiler lowers these allocation-free kernels to U32 arguments
// and an array of Term results. They never enter the scheduler or use its heap.
#define main bend_unused_main
#include "entry.c"
#undef main
#define LIMBS(x) (uint32_t)((x) >> 32), (uint32_t)(x)

static uint64_t word(const Term *out) {
  return ((uint64_t)(uint32_t)out[0] << 32) | (uint32_t)out[1];
}

uint64_t bend_reduce(uint64_t high, uint64_t low) {
  Term result[2];
  if (!spin_goldilocks_Gl_reduce((Env){0}, result, LIMBS(high), LIMBS(low))) abort();
  return word(result);
}

uint64_t bend_mul(uint64_t a, uint64_t b) {
  Term result[2];
  if (!spin_goldilocks_Gl_mul((Env){0}, result, LIMBS(a), LIMBS(b))) abort();
  return word(result);
}

void bend_compress(uint64_t h[8], const uint64_t m[16], uint64_t t0, uint64_t t1, bool last) {
  Term result[16];
  uint32_t flag = last ? UINT32_MAX : 0;
  if (!spin_hashlib_B2b_compress((Env){0}, result,
      LIMBS(h[0]), LIMBS(h[1]), LIMBS(h[2]), LIMBS(h[3]),
      LIMBS(h[4]), LIMBS(h[5]), LIMBS(h[6]), LIMBS(h[7]),
      LIMBS(m[0]), LIMBS(m[1]), LIMBS(m[2]), LIMBS(m[3]),
      LIMBS(m[4]), LIMBS(m[5]), LIMBS(m[6]), LIMBS(m[7]),
      LIMBS(m[8]), LIMBS(m[9]), LIMBS(m[10]), LIMBS(m[11]),
      LIMBS(m[12]), LIMBS(m[13]), LIMBS(m[14]), LIMBS(m[15]),
      LIMBS(t0), LIMBS(t1), flag, flag)) abort();
  for (unsigned i = 0; i < 8; ++i) h[i] = word(&result[2*i]);
}

void bend_extension_mul(uint64_t out[3], uint64_t a0, uint64_t a1, uint64_t a2,
                        uint64_t b0, uint64_t b1, uint64_t b2) {
  Term result[6];
  if (!spin_extension_E3_mul((Env){0}, result,
      LIMBS(a0), LIMBS(a1), LIMBS(a2), LIMBS(b0), LIMBS(b1), LIMBS(b2))) abort();
  for (unsigned i = 0; i < 3; ++i) out[i] = word(&result[2*i]);
}

#define DIGEST(d) (d)[0], (d)[1], (d)[2], (d)[3], (d)[4], (d)[5], (d)[6], (d)[7]

void bend_parent(uint32_t out[8], uint64_t tag, uint64_t index,
                 const uint32_t start[8], const uint32_t left[8], const uint32_t right[8]) {
  Term result[8];
  if (!spin_merkle_parent((Env){0}, result, LIMBS(tag), LIMBS(index),
                          DIGEST(start), DIGEST(left), DIGEST(right))) abort();
  for (unsigned i = 0; i < 8; ++i) out[i] = (uint32_t)result[i];
}

#include "chain.inc"
#include "sumcheck.inc"
