// Test-only projection of an ordered R11.3 claim. The three substitutions
// independently identify its public constant, message masks, and U3 reads.
if (projectAttention) {
  Ex mask = eZ(), cells = eZ();
  for (auto &x : f.s) mask = mask - eS(x.second * mf[x.first], x.first + 1);
  for (auto &x : f.e) {
    const u64 j = trees[x.tree].K * x.row + x.idx;
    cells = cells + x.coef * ePow(eI(3), j);
  }
  Ex row = eS(eS(eZ() - publicPart(f), 257) + mask, 257) + cells;
  projectedAttentionRows = eS(projectedAttentionRows, 257) + row;
}
