// Included after the generated Bend and bridge word/limb conversion routines.
bool bend_has_work(uint64_t first_word, unsigned bits) {
  Term result[1];
  if (!spin_chain_has_work((Env){0}, result, LIMBS(first_word), bits)) abort();
  return result[0] != 0;
}

uint64_t bend_position(uint64_t next_word, unsigned bits) {
  Term result[2];
  if (!spin_chain_position((Env){0}, result, LIMBS(next_word), bits)) abort();
  return word(result);
}

bool bend_field_candidate(uint64_t next_word) {
  Term result[1];
  if (!spin_chain_field_candidate((Env){0}, result, LIMBS(next_word))) abort();
  return result[0] != 0;
}
