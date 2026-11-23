// Configuration-only feed-forward geometry at the four supported H821 profiles.
{
  FILE *out = fopen(std::getenv("FLASHPROVE_FF_LAYOUT"),"wx");
  if (!out) refuse("ff-layout-destination");
  auto field = [&](const char *name,u64 value){fprintf(out,"field\t%s\t%llu\n",name,(unsigned long long)value);};
  for (u64 g=0;g<NGr;++g) {
    fprintf(out,"group\t%llu\n",(unsigned long long)g);
    const auto &hp=hidPlans2.at(g);
    field("lt",lt);field("ll",ll);field("ls",ls);field("la",la);field("lPd",lPd);field("lPf",lPf);field("lfe",lfe);
    field("ldh",ldh);field("Lam",Lam);field("LamM",LamM);field("NI",NI);field("lNI",lNI);field("S2",S2);
    field("d",d);field("Pd",Pd);field("Pf",Pf);field("dq",dq);field("f",f);field("fe",fe);field("NE",NE);
    field("H",h.H);field("G",h.Gk);field("dh",dh);field("ltBits",h.lmb);
    field("NCL",hp.NCL);field("lamS",hp.lamS);field("slots",hp.ns);field("claims",hp.nLin);field("u3",hp.nU[2]);
    field("forest_slots",forestElems(y.fo));field("forest_depth",y.fo.dT);field("forest_top",y.fo.rK);
    field("NS",ledNS());field("NPr",ledNP());field("NO",ledNO());field("limbs",residualStreamLimbs);
    field("fQK",fQK);field("fV",fV);field("fO",fO);field("fG",fG);field("fU",fU);field("fD",fD);field("fR",fR);
    field("router_clamp",RCL);field("gate_clamp",GCL);field("up_bound",LBU);field("L",h.L);field("NN",NN);
    field("tree_b",iB);field("eps1",h.eps[0]);field("eps2",h.eps[1]);
    auto tensor = [&](const char *nm,int m,const TenAt &x) {
      fprintf(out,"tensor\t%s\t%d\t%llu\t%llu\t%llu\t%llu\n",nm,m,(unsigned long long)x.off,(unsigned long long)x.nl,(unsigned long long)x.cnt,(unsigned long long)x.J);
    };
    for (const auto &v:y.ten) tensor(v.name.c_str(),v.mat,v.at());
    tensor("xb",4,y.xb);
    for (size_t q=0;q<y.calls.size();++q) {
      const auto &call=y.calls[q];
      for(const auto &v:call.segs) {
        fprintf(out,"segment\t%s\t%zu\t%d\t%llu\t%u",v.name.c_str(),q,call.lJ,(unsigned long long)v.n,(unsigned)v.moe);
        for(size_t j=0;j<v.pos.size();) {
          size_t n=1;
          while(j+n<v.pos.size() && v.pos[j+n]==v.pos[j]+n) ++n;
          fprintf(out,"\t%llu\t%zu",(unsigned long long)v.pos[j],n);
          j+=n;
        }
        fputc('\n',out);
      }
      fprintf(out,"call\t%zu\t%d\t%d\t%d\t%s\n",q,y.fo.first[q],y.fo.iota[q],call.lJ,call.kind.c_str());
    }
    const u64 La=1ull<<la;
    u64 off=0;
    auto tables=[&](const char *name,u64 mu,u64 parts,const vector<string> &points,u64 cells) {
      for(const auto &p:points) {
        fprintf(out,"table\t%s\t%s\t%llu\t%llu\t%llu",name,p.c_str(),(unsigned long long)mu,(unsigned long long)cells,(unsigned long long)off);
        for(u64 j=mu;j<mu+parts;++j) {
          const auto &m=hp.tl.mats.at(j);
          u64 count=m.k*(m.m/cells);
          fprintf(out,"\t%llu",(unsigned long long)count);
          off+=count;
        }
        fputc('\n',out);
      }
    };
    tables("af",iAF,y.parts[0],rdAF,La);tables("qa",iQA,1,rdQA,La);tables("xbI",iXI,1,rdXI,La);
    if(!g) tables("xbI",iXI,1,{"Z_E"},La);
    tables("xbO",iXO,1,rdXO,La);tables("ad",iAD,y.parts[1],rdAD,T);
    tables("ar",iAR,1,rdAR,T);tables("qa",iQA,1,rdQS,T);
    tables("b",iB,1,{"bit0","bit1","pin"},1ull<<h.lmb);
    if(off!=hp.nU[2]) refuse("ff-table-size");
  }
  if(fclose(out)) refuse("ff-layout-write");
}
