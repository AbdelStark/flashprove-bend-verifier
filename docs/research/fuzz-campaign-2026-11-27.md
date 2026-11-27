# Differential fuzz campaign, 2026-11-27

> Status: frozen

REQ-ASSURE-1 asks that Bend never accept an input the pinned C++ verifier refuses. This campaign checks that implication on 40,000 altered inputs: 10,000 for each published proof family, both full-size families included. [Assurance contract](../spec/assurance.md) · [Tallies](data/fuzz-campaign/summary.json)

## What ran

`scripts/fuzz-differential.py` alters one input file of a genuine proof set per case and runs `verify-bend` and `cp_verify` on the same bytes. The file is drawn with weights (proof 60, key 12, leaf 12, request 4, policy 4, KL.bin 3, layout 3, next token 2). The change is drawn from bit flips, byte changes, a zeroed or swapped 8-byte word, a truncation, an extension and an incremented word. Each case is reproducible from the seed `campaign-2026-11-27`, the fixture name and its index.

```sh
make standalone oracle
python3 -B scripts/fuzz-differential.py -n 10000 --seed campaign-2026-11-27 -j 90 --threads 1 \
  --out FIXTURE.json FIXTURE
```

The build was `fabcb2b` (Bend source digest `59bf98240586a317b15ce9e29b57623b8bf9c80c2d3e5d47428a651443c2ebb8`, `verify-bend` SHA-256 `f0db8d06…`, `cp_verify` SHA-256 `7f9efc1e…`). It ran on an Intel Xeon Platinum 8480CL under Linux 6.8 with Ubuntu clang 18.1.3, in one Slurm job with 96 CPUs, 90 cases at a time and one thread per verifier call.

## Results

| Family | Cases | Both refused | Bend accepted, C++ refused | C++ accepted, Bend refused | Time |
| --- | ---: | ---: | ---: | ---: | ---: |
| accepted-proof | 10,000 | 10,000 | 0 | 0 | 12.5 min |
| accepted-proof-clipped-gap | 10,000 | 10,000 | 0 | 0 | 12.5 min |
| full-size | 10,000 | 10,000 | 0 | 0 | 105 min |
| full-size-clipped-gap | 10,000 | 10,000 | 0 | 0 | 106 min |

No case disagreed in either direction, and no verifier crashed, timed out or exited unexpectedly. The unchanged set passed both verifiers before each family.

Every Bend refusal arose in the stage that reads the altered file. Proof faults were refused in the request stage, leaf faults in the leaf stage, and key faults in the key stage. Faults in the configuration files were refused while the public inputs were read. Some faults in the request and next-token files were refused there too; the rest were refused in the request stage, which binds those files into the transcript.

| Altered file (accepted-proof) | Cases | Bend's refusal stage |
| --- | ---: | --- |
| `example.proof` | 6,068 | request |
| `ivk/leaf/0.bin` | 1,195 | leaf |
| `ivk/key.bin` | 1,184 | key |
| `config/policy.txt`, `config/KL.bin`, `config/layout.txt` | 994 | public |
| `example.req` | 382 | public 219, request 163 |
| `example.y` | 177 | public 150, request 27 |

The other three families have the same pattern. The tallies by file and mutation kind, and both programs' refusal names, are in the summary.

## Refusal names

Bend named 72 to 77 distinct checks per family; C++ named 98 to 114. The most common Bend names were `opening` (a Merkle opening that does not lead to its root, 54% to 59% of cases), `chain-round`, `plan-length` and `trailing-data`. C++ reports a stage class first: `proof-refused` about 62%, `entry-refused` and `key-refused` about 12% each. The names differ in wording but agree on the stage.

## Limits

A sampled campaign tests the implication on the inputs it draws. It cannot show that no input exists on which Bend accepts and C++ refuses. Most changes to a proof stop at the first Merkle opening or transcript check. The later equations need the fixed-transcript tests of `make request-claims-test` and the mutation tests of REQ-ASSURE-2.
