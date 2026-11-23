#define E3_LIMBS(x) LIMBS(x[0]), LIMBS(x[1]), LIMBS(x[2])

void bend_psc_known(uint64_t residual[3], const uint64_t moment[3], const uint64_t coefficient[3]) {
  Term result[6];
  if (!spin_sumcheck_known((Env){0}, result, E3_LIMBS(residual), E3_LIMBS(moment), E3_LIMBS(coefficient))) abort();
  for (unsigned i = 0; i < 3; ++i) residual[i] = word(&result[2*i]);
}

void bend_psc_horner(uint64_t value[3], const uint64_t point[3], const uint64_t coefficient[3]) {
  Term result[6];
  if (!spin_sumcheck_horner((Env){0}, result, E3_LIMBS(value), E3_LIMBS(point), E3_LIMBS(coefficient))) abort();
  for (unsigned i = 0; i < 3; ++i) value[i] = word(&result[2*i]);
}
#undef E3_LIMBS
