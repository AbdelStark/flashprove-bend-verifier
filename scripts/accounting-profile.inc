    // Each bound is the largest uncharged error of a stage at a given work factor.
    // Keep the dyadic numerator and exponent so Bend can make the exact comparison.
    FILE *accounting = create(to + "accounting.tsv");
    auto bounds = [&](const char *name, const blk::FilePlan &file) {
      auto plan = blk::merged(c.sized().d.set, {file});
      const auto audit = blk::account(plan);
      if (!audit.formed || !audit.holds || !audit.refused.empty() || audit.circle)
        throw std::runtime_error("inadmissible public plan");
      blk::Real maximum[33];
      for (const auto &r : plan->rounds_) {
        if (r.word_fault() || r.work_bits > 32) throw std::runtime_error("inadmissible round");
        const auto error = plan->whole_error(r, plan->capped());
        if (maximum[r.work_bits] < error) maximum[r.work_bits] = error;
      }
      fprintf(accounting, "%s %u %llu %llu %llu %llu\n", name, audit.target,
        (unsigned long long)audit.rounds, (unsigned long long)audit.by_work,
        (unsigned long long)audit.closeness[0], (unsigned long long)audit.closeness[1]);
      for (unsigned w = 0; w <= 32; ++w) if (!maximum[w].zero()) {
        if (maximum[w].e >= 0) throw std::runtime_error("public plan error exceeds one");
        fprintf(accounting, "bound %u %ld", w, -maximum[w].e);
        for (auto limb : maximum[w].m.w) fprintf(accounting, " %u", limb);
        fprintf(accounting, "\n");
      }
    };
    bounds("key", c.key());
    bounds("leaf", c.entry());
    bounds("request", c.proof());
    if (fclose(accounting)) throw std::runtime_error("could not write accounting");
