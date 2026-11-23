// Public shapes for the H821 output-head relation. Positions are runs of consecutive columns.
{
  FILE *out = fopen(std::getenv("FLASHPROVE_HEAD_LAYOUT"), "wx");
  if (!out) refuse("head-layout-destination");
  auto field = [&](const char *name, u64 n) { fprintf(out, "field\t%s\t%llu\n",name,(unsigned long long)n); };
  field("lt",lt); field("ls",ls); field("layer",h.L); field("channels",d);
  field("vocab",Vv); field("n_hf",h.NHf); field("mask_bits",h.lmbH); field("log_channels",lPd);
  field("mf",h.MF); field("kf",h.KF); field("eps",h.epsF); field("sh",h.digSh); field("family",h.famF);
  field("clip",h.clipC); field("theta",h.theta); field("cap",h.cap);
  field("jv",HLy.JV); field("jva",HLy.JVa); field("forest_slots",forestElems(HLy.fs));
  field("slots",PH2.nMsg); field("claims",PH2.nLin); field("u3",PH2.nU[2]);
  if (residualStreamLimbs != 5) refuse("head-profile-limbs");
  for (const auto &m : PH2.tl.mats) fprintf(out, "matrix\t%llu\t%llu\n",(unsigned long long)m.m,(unsigned long long)m.k);
  for (u32 i=0;i<y.xb.nl;i++) fprintf(out,"limb\t%llu\n",(unsigned long long)(tenCell(y.xb,i,0,0)/S2));
  for (size_t q=0; q<HLy.calls.size(); q++) {
    const auto &call = HLy.calls[q];
    for (const Seg &s : call.segs) {
      fprintf(out,"segment\t%s\t%zu\t%d\t%llu",s.name.c_str(),q,call.lJ,(unsigned long long)s.n);
      for (size_t i=0; i<s.pos.size();) {
        size_t n=1;
        while (i+n<s.pos.size() && s.pos[i+n]==s.pos[i]+n) ++n;
        fprintf(out,"\t%llu\t%zu",(unsigned long long)s.pos[i],n);
        i+=n;
      }
      fputc('\n',out);
    }
  }
  if (fclose(out)) refuse("head-layout-write");
}
