#pragma once
#include <cstdint>

extern "C" {
void bend_psc_known(std::uint64_t residual[3], const std::uint64_t moment[3], const std::uint64_t coefficient[3]);
void bend_psc_horner(std::uint64_t value[3], const std::uint64_t point[3], const std::uint64_t coefficient[3]);
}
