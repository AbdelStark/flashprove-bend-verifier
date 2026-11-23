# The command surface of the repo. Every command an agent or CI needs is a target here;
# docs name commands only as `make <target>` (scripts/check-docs.py enforces it).
export BEND_NO_TELEMETRY := 1

.PHONY: help bootstrap upstream check test test-native docs-check spikes ci

help:  ## list the targets
	@grep -E '^[a-z0-9-]+:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | expand -t 14

bootstrap:  ## install the pinned Bend toolchain into .toolchain/ (see toolchain.lock)
	@sh scripts/bootstrap.sh

upstream:  ## fetch the pinned FlashProve revision into .upstream/ (see upstream.lock)
	@sh scripts/fetch-upstream.sh

check: bootstrap generated-check  ## type-check and proof-check every Bend source file under src/
	@python3 scripts/bend-check.py src

test: bootstrap  ## run the expectation tests on the JS lane (fast)
	@python3 scripts/bend-test.py tests

test-native: bootstrap  ## run the expectation tests as native binaries (the lane that is benchmarked)
	@python3 scripts/bend-test.py --native tests

docs-check:  ## mechanical anti-drift checks over the Markdown
	@python3 scripts/check-docs.py

spikes: bootstrap upstream  ## reproduce the feasibility measurements of docs/research (needs bootstrap + upstream)
	@sh research/spikes/run.sh

ci: docs-check check test test-native e2e plan-test public-input-test stages-test standalone-test standalone-rejections request-claims-test  ## what CI runs

.PHONY: benchmark verifier oracle e2e e2e-full e2e-extended generated-check

verifier: build/verify build/bend_verify.digest  ## build the whole verifier with native Bend kernels

WORKER_MODULES := $(addprefix src/,hashlib.bend goldilocks.bend extension.bend merkle.bend chain.bend sumcheck.bend)
WORKER_NATIVE := $(wildcard src/native/*.patch src/native/*.inc src/native/*.h) src/native/bridge.c src/native/entry.bend.in

build/verify: $(wildcard src/policy*.bend src/layout*.bend) src/verify.bend src/header.bend src/commitment.bend src/hash_bytes.bend src/record_seeds.bend src/hashlib.bend src/native/exec_verifier.c src/native/exec_verifier.js src/native/verify_main.c scripts/build-cli.sh toolchain.lock | bootstrap
	@sh scripts/build-cli.sh

build/bend_verify: $(WORKER_NATIVE) $(WORKER_MODULES) tests/native_sumcheck.cpp scripts/build-verifier.sh upstream.lock toolchain.lock | bootstrap upstream
	@sh scripts/build-verifier.sh

build/bend_verify.digest: | build/bend_verify
	@test -s $@ || sh scripts/build-verifier.sh

oracle: build/cp_verify  ## build the unmodified pinned C++ verifier

build/cp_verify: scripts/oracle-build.sh upstream.lock | upstream
	@sh scripts/oracle-build.sh

e2e: verifier oracle  ## compare the two small proof sets and their rejection suites
	@python3 scripts/e2e.py
	@python3 scripts/verify-test.py

e2e-full: verifier oracle  ## compare all four proof sets and the rejection suites
	@python3 scripts/e2e.py --full-size
	@python3 scripts/verify-test.py --full-size

e2e-extended: verifier oracle  ## run 102 additional item and record rejection cases per worker
	@python3 scripts/e2e.py --extended

generated-check:  ## compare the checked-in hash kernel to the generator
	@python3 research/spikes/blake2b/gen.py kernel | cmp - src/hashlib.bend

benchmark: verifier oracle  ## time three alternating exact-match runs at each model size
	@python3 scripts/e2e.py --benchmark 3 --full-size

.PHONY: lean-baseline benchmark-lean

lean-baseline: build/verify-on-bytes  ## build the optional pinned native Lean OnBytes comparator

build/verify-on-bytes: scripts/onbytes-build.sh upstream.lock | upstream
	@bash scripts/onbytes-build.sh

benchmark-lean: lean-baseline  ## time three Lean OnBytes calls per exact-match fixture
	@python3 scripts/onbytes-test.py --samples 3

.PHONY: plans plans-reproduce plan-test

plans:  ## extract the four configuration-bound public plan bundles offline
	@python3 scripts/plan-profiles.py install

plans-reproduce: upstream  ## compare all bundled public plans with a fresh export from the pin
	@python3 scripts/plan-profiles.py check

build/inspect-plans: src/plan_cli.bend src/plan.bend src/plan_types.bend src/plan_catalog.bend src/wire_reader.bend src/header.bend src/commitment.bend src/hash_bytes.bend src/record_seeds.bend src/hashlib.bend toolchain.lock | bootstrap
	@mkdir -p build
	@.toolchain/bend/bin/bend src/plan_cli.bend -o $@

plan-test: build/inspect-plans plans upstream  ## authenticate the schedules in Bend and check changed input rejection
	@python3 scripts/test-plans.py

.PHONY: public-input-test

public-input-test: bootstrap plans upstream  ## reconstruct the public statement and layout on all four profiles
	@python3 scripts/public-input-test.py

.PHONY: stages-test stages-full

STAGE_MODULES := $(wildcard src/*.bend)

build/key-stage: $(STAGE_MODULES) scripts/probes/key-stage.bend toolchain.lock | bootstrap
	@mkdir -p build
	@.toolchain/bend/bin/bend scripts/probes/key-stage.bend -o $@

build/leaf-checked: $(STAGE_MODULES) scripts/probes/leaf-stage.bend toolchain.lock | bootstrap
	@mkdir -p build
	@.toolchain/bend/bin/bend scripts/probes/leaf-stage.bend -o $@

stages-test: build/key-stage build/leaf-checked plans upstream  ## compare standalone stage evidence and test the final LINK equation
	@python3 scripts/test-key-stage.py
	@python3 scripts/test-leaf-stage.py
	@python3 scripts/test-request-stage.py

stages-full: build/key-stage build/leaf-checked plans upstream  ## run the independent stage checks at both model sizes
	@python3 scripts/test-key-stage.py --full
	@python3 scripts/test-leaf-stage.py --full-size
	@python3 scripts/test-request-stage.py --full-size

.PHONY: standalone standalone-test standalone-full public-tables

public-tables:  ## materialize the public tables that Bend authenticates
	@python3 scripts/generate-tables.py --output build/tables

build/verify-bend: $(STAGE_MODULES) src/native/verify_main.c scripts/build-standalone.py scripts/compile_bend.py toolchain.lock | bootstrap
	@python3 scripts/build-standalone.py

build/verify-bend.digest: | build/verify-bend
	@test -s $@ || python3 scripts/build-standalone.py

standalone: build/verify-bend build/verify-bend.digest plans public-tables  ## build the native Bend verifier and its public data

standalone-test: standalone upstream  ## exercise the native command without external verifier executables
	@python3 scripts/standalone-test.py

standalone-full: standalone upstream  ## exercise the native command on all four published proofs
	@python3 scripts/standalone-test.py --full-size

.PHONY: standalone-rejections standalone-extended
standalone-rejections: standalone oracle  ## compare standalone and reference refusals on both small examples
	@python3 -B scripts/standalone-rejections.py

standalone-extended: standalone oracle  ## compare 122 altered sets and a cross-commitment leaf
	@python3 -B scripts/standalone-rejections.py --extended

.PHONY: request-claims-test
request-claims-test: bootstrap upstream plans public-tables  ## check local, carried and deferred equations at a fixed genuine transcript
	@python3 -B scripts/test-request-claims.py

.PHONY: fuzz
fuzz: standalone oracle  ## alter random bytes of both small proof sets; Bend must never accept where C++ refuses (FUZZ_ARGS="-n N --seed S")
	@python3 -B scripts/fuzz-differential.py $(FUZZ_ARGS)

.PHONY: benchmark-standalone
benchmark-standalone: standalone oracle  ## measure validated standalone and C++ whole calls on both exact fixtures
	@python3 -B scripts/benchmark-standalone.py

.PHONY: fresh-proof

fresh-proof: standalone upstream  ## generate a fresh small next-token proof on an H100 and verify it with C++ and Bend
	@python3 scripts/fresh-proof.py
