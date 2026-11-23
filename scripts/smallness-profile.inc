// Public smallness matrix dimensions and physical owners, after buildLinksH
// has resolved each reference to an earlier segment.
{
  FILE *out = std::fopen(std::getenv("FLASHPROVE_SMALLNESS_LAYOUT"), "wx");
  if (!out) refuse("smallness-layout-destination");
  for (const LinkH &x : linksH) {
    const auto &tl = *x.tl;
    const size_t linear = x.kind == 0 ? hidPlans2[x.g].nLin : x.kind == 1 ? AH2[x.g].nLin : PH2.nLin;
    fprintf(out, "link\t%s\t%zu\t%llu\t%u\n", x.name.c_str(), linear, (unsigned long long)tl.mz, x.ns);
    for (size_t i = 0; i < tl.mats.size(); ++i) {
      const auto &m = tl.mats.at(i);
      const auto &where = x.arrayOf.at(tl.gtTree.at(i));
      fprintf(out, "matrix\t%zu\t%s\t%llu\t%llu\n", where.first, where.second.c_str(),
              (unsigned long long)m.m, (unsigned long long)m.k);
    }
  }
  if (fclose(out)) refuse("smallness-layout-write");
}
