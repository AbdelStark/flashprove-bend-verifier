// Project each final norm and logits equation. Substitute mask[j]=j+1 and U3[j]=3^j.
if (G_ == "H:" && (sectionF.find("head: the final norm:") == 0 ||
    sectionF.find("head: the logits against") == 0)) {
  Ex cells = eZ(), masks = eZ();
  for (auto &x : f.e) cells = cells + x.coef * ePow(eI(3), trees[x.tree].K * x.row + x.idx);
  for (auto &x : f.s) masks = masks - eS(x.second * mf[x.first], x.first + 1);
  std::fputs("head-norm", stdout);
  for (Ex x : {eZ() - publicPart(f), masks, cells})
    std::fprintf(stdout, " %016llx%016llx%016llx", (unsigned long long)x.c[0],
        (unsigned long long)x.c[1], (unsigned long long)x.c[2]);
  std::fputc('\n', stdout);
}
