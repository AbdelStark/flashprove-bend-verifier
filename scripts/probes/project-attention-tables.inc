// Test-only projection of each dense public phi, including its extent and placement.
Ex functions = eZ();
for (const auto &fn : fun) {
  Ex p = eO(), sum = eZ();
  for (auto &x : fn.phi) {
    sum = sum + x * p;
    p = eS(p, 3);
  }
  Ex value = eS(eS(eS(eI(fn.M), 257) + eI(fn.L), 257) + eI(fn.at), 257) + sum;
  functions = eS(functions, 257) + value;
}
fprintf(stdout, "attention-project %u %016llx%016llx%016llx %016llx%016llx%016llx\n", attentionOwnSlots,
  (unsigned long long) F.projectedAttentionRows.c[0], (unsigned long long) F.projectedAttentionRows.c[1],
  (unsigned long long) F.projectedAttentionRows.c[2], (unsigned long long) functions.c[0],
  (unsigned long long) functions.c[1], (unsigned long long) functions.c[2]);
F.projectAttention = false;
