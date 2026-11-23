// Emits configuration-only forest geometry when rebuilding the four profiles.
// Included inside buildLinksH in a temporary copy of vf_segments.inc.
{
  const char *path = std::getenv("FLASHPROVE_SEGMENT_GEOMETRY");
  if (!path) refuse("missing-segment-geometry-destination");
  FILE *out = std::fopen(path, "wx");
  if (!out) refuse("segment-geometry-destination");
  for (const LinkH &link : linksH) {
    auto forest = [&](const char *scope, const HForest &f, const vector<const Call *> &calls, const vector<unsigned> &shifts) {
      if (calls.size() != (size_t)f.NC) refuse("segment-geometry-call-count");
      fprintf(out, "forest\t%s\t%s\t%d\t%d\t%d\t%d\t%zu\n",
              link.name.c_str(), scope, f.dT, f.kT, f.rK, f.cK,
              string(scope) == "main" ? (size_t)0 : link.ns - forestElems(f));
      vector<u64> pads(calls.size(), 0);
      pads[0] = f.emptyKeys();
      for (int tree = 0; tree < f.NT; ++tree)
        pads.at(f.callOf.at(tree)) += f.pub.at(tree);
      for (size_t i = 0; i < calls.size(); ++i) {
        const Call &c = *calls.at(i);
        fprintf(out, "call\t%s\t%d\t%d\t%d\t%llu\t%llu\t%llu\t%u\n", c.name.c_str(),
                c.k, f.first.at(i), f.iota.at(i), (unsigned long long)c.t0,
                (unsigned long long)c.tauAt(c.t0), (unsigned long long)pads.at(i), shifts.empty() ? 0 : shifts.at(i));
      }
    };
    vector<const Call *> calls;
    if (link.kind == 0) {
      for (const auto &c : y.calls) calls.push_back(&c.c);
      forest("main", y.fo, calls, {});
    } else if (link.kind == 1) {
      auto &attention = AH2.at(link.g);
      // The proof verifier binds these pointers immediately before forestPad.
      attention.A.bindTau();
      vector<unsigned> shifts;
      for (const auto &c : attention.A.calls) {
        calls.push_back(&c.c);
        shifts.push_back(c.sh);
      }
      forest("main", attention.fs, calls, shifts);
    } else {
      for (const auto &c : HLy.calls) calls.push_back(&c.c);
      forest("main", HLy.fs, calls, {});
    }
    forest("digits", link.tl->f9, {&link.tl->z[1].c, &link.tl->z[2].c}, {});
  }
  if (std::fclose(out)) refuse("segment-geometry-write");
}
