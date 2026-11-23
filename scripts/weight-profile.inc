// Executed only by the configuration-only planner in the temporary export tree.
{
  FILE *out = std::fopen(std::getenv("FLASHPROVE_WEIGHT_LAYOUT"), "wx");
  if (!out) refuse("weight-layout-destination");
  fprintf(out, "layout\t%d\t%llu\t%llu\n", wsLay.lk, (unsigned long long)wsLay.m0, (unsigned long long)D);
  for (const WsUnit &unit : wsLay.U) {
    fprintf(out, "unit\t%u\t%u\t%d\t%d\t%llu\t%llu\n", unit.X, unit.l, unit.nlw,
            unit.ncb, (unsigned long long)unit.off, (unsigned long long)unit.rows);
    for (const WsGrp &group : unit.g)
      fprintf(out, "group\t%s\t%c\t%d\t%llu\t%llu\t%d\t%d\t%d\t%llu\n",
              group.name, group.cls, group.high, (unsigned long long)group.R,
              (unsigned long long)group.o, group.z, group.t, group.cb0, (unsigned long long)group.left);
  }
  if (fclose(out)) refuse("weight-layout-write");
}
