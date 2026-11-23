#pragma once
#include <cstdint>
extern "C" {
void bend_extension_mul(std::uint64_t out[3], std::uint64_t a0, std::uint64_t a1, std::uint64_t a2,
                        std::uint64_t b0, std::uint64_t b1, std::uint64_t b2);
void bend_parent(std::uint32_t out[8], std::uint64_t tag, std::uint64_t index,
                 const std::uint32_t start[8], const std::uint32_t left[8], const std::uint32_t right[8]);
void bend_compress(std::uint64_t h[8], const std::uint64_t m[16],
                   std::uint64_t t0, std::uint64_t t1, bool last);
std::uint64_t bend_reduce(std::uint64_t high, std::uint64_t low);
std::uint64_t bend_mul(std::uint64_t a, std::uint64_t b);
}
#include "chain.h"
#include "sumcheck.h"
