// Before subtracting the token sumcheck's start or adding KT, evaluate
// the lookup join against the same independent public mask and U3 vectors.
{
  const Aff equation = cstart - fo.Cend;
  Ex masks=eZ(), cells=eZ();
  for (const auto &v : equation.s) masks=masks-eS(v.second*F.mf[v.first],v.first+1);
  for (const auto &v : equation.e) cells=cells+v.coef*ePow(eI(3),F.trees[v.tree].K*v.row+v.idx);
  fputs("ff-join",stdout);
  for (Ex v : {eZ()-F.publicPart(equation),masks,cells}) fprintf(stdout," %016llx%016llx%016llx",
    (unsigned long long)v.c[0],(unsigned long long)v.c[1],(unsigned long long)v.c[2]);
  fputc('\n',stdout);
}
