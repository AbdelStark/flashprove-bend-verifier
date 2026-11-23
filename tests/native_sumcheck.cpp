#include "sumcheck.h"

int main() {
  std::uint64_t residual[] = {6, 0, 0};
  const std::uint64_t point[] = {2, 0, 0};
  const std::uint64_t coefficient[] = {3, 0, 0};
  bend_psc_known(residual, point, coefficient);
  if (residual[0] || residual[1] || residual[2]) return 1;
  bend_psc_horner(residual, point, coefficient);
  return residual[0] != 3 || residual[1] || residual[2];
}
