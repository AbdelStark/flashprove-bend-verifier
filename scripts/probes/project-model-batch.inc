// Evaluate the placed main coefficient of every oracle at the public
// point z[b] = 13+b. Weight by its stable (born segment,message) label.
{
  E cells = E::zero(), masks = E::zero();
  for (size_t i = 0; i < eq.terms.size(); ++i) {
    const ReqTerm &t = eq.terms.at(i);
    const ReqArray *a = layout_.find(t.born, t.array);
    const auto &f = row.forms.at(i);
    const u64 d = t.born + a->message;
    const u64 label = 1 + a->message + (d * (d + 1)) / 2;
    const unsigned bits = S.table_bits(f.oracle, Part::MAIN);
    std::vector<E> coordinates(bits);
    for (unsigned b = 0; b < bits; ++b) coordinates[b] = E::from(from_u64(13 + b));
    cells += E::from(from_u64(label)) * f.c.mle(coordinates.data(), bits);
  }
  for (size_t i = 0; i < eq.on_masks.size(); ++i) masks += E::from(from_u64(i+1)) * eq.on_masks[i];
  std::fputs("model-batch", stdout);
  for (E x : {eq.target, cells, masks}) {
    std::fprintf(stdout, " %016llx%016llx%016llx", (unsigned long long)x.c[0].v,
                 (unsigned long long)x.c[1].v, (unsigned long long)x.c[2].v);
  }
  std::fputc('\n', stdout);
}
