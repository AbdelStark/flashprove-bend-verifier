// Evaluate the 15 U3 table functionals and deferred matrix row independently.
{
  Ex functions=eZ();
  for (const auto &fn : fun) {
    Ex sum=eZ();
    for (auto i=fn.phi.rbegin(); i!=fn.phi.rend(); ++i) sum=eS(sum,3)+*i;
    Ex v=eS(eS(eS(eI(fn.M),257)+eI(fn.L),257)+eI(fn.at),257)+sum;
    functions=eS(functions,257)+v;
  }
  const auto &unit=wsLay.U.back();
  vector<Ex> gamma(unit.off+unit.rows,eZ());
  for (const auto &cl : wo.rec) wsGammaAdd(gamma,wsLay,cl,eO());
  Ex coeff=eZ(), point=eZ();
  for (size_t j=gamma.size(); j-->unit.off;) coeff=eS(coeff,3)+gamma[j];
  coeff=coeff*ePow(eI(3),unit.off);
  for (auto i=wo.rm.rbegin(); i!=wo.rm.rend(); ++i) point=eS(point,257)+*i;
  fprintf(stdout,"head-functions %u %u",headUsed,wo.sFv);
  for (Ex v : {functions,coeff,point,wo.fvp}) fprintf(stdout," %016llx%016llx%016llx",
    (unsigned long long)v.c[0],(unsigned long long)v.c[1],(unsigned long long)v.c[2]);
  fputc('\n',stdout);
}
