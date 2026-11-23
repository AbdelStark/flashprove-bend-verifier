// Test instrumentation inside the pinned forest verifier. Each projected row
// substitutes the public sequence mask[j] = j+1, independent of the witness.
  Ex folded = eZ();
  auto emit = [&](Ex x) { folded = eS(folded,257) + x; };
  for (const auto &r : h.rows) {
    emit(eZ() - F.publicPart(r));
    Ex dot = eZ();
    for (const auto &slot : r.s)
      dot = dot - eS(slot.second * F.mf[slot.first], slot.first + 1);
    emit(dot);
  }
  emit(h.leaves.eps * h.leavesA);
  for (auto it = h.zy.rbegin(); it != h.zy.rend(); ++it) emit(*it);
  for (auto it = h.zx.rbegin(); it != h.zx.rend(); ++it) emit(*it);
  fprintf(stdout, "projected-forest %016llx%016llx%016llx\n", (unsigned long long)folded.c[0],
    (unsigned long long)folded.c[1], (unsigned long long)folded.c[2]);
