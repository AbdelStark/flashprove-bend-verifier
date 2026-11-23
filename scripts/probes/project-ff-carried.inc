// R11.2 carries one linear claim on committed weights into the second chain.
// Give the public row coefficient at index i the independent weight 3^i.
{
  u64 first=wsLay.m0, last=0;
  for (const auto &cl : wo.rec) {
    const auto &u=wsLay.U.at(cl.ui);
    first=std::min(first,u.off);
    last=std::max(last,u.off+u.rows);
  }
  vector<Ex> weights(last,eZ());
  for (const auto &cl : wo.rec) wsGammaAdd(weights,wsLay,cl,eO());
  Ex row=eZ(), point=eZ();
  for (u64 i=last; i-->first;) row=eS(row,3)+weights[i];
  row=row*ePow(eI(3),first);
  for (auto it=wo.rm.rbegin(); it!=wo.rm.rend(); ++it) point=eS(point,257)+*it;
  fprintf(stdout,"ff-carried %u",wo.sFv);
  for (Ex x : {F.projectedAttentionRows,row,point,wo.fvp}) fprintf(stdout," %016llx%016llx%016llx",
    (unsigned long long)x.c[0],(unsigned long long)x.c[1],(unsigned long long)x.c[2]);
  fputc('\n',stdout);
  F.projectAttention=false;
}
