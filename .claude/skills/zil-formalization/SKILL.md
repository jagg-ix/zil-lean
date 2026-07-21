---
name: zil-formalization
description: Model, audit, and CI-gate a mathematics or physics formalization arc as a ZIL theorem-dependency graph — theorem/lemma/assumption DAGs with proof-evidence bookkeeping, PROVED/CONDITIONAL/WEAK/BROKEN status computation, break-impact analysis, and TLA+/Lean export. Use when planning which declarations to prove next, recording proof witnesses from Lean/ACL2, or answering "what breaks if this assumption fails?".
---

# ZIL for formalization work

ZIL is a declarative fact/rule/query language. For formalization it plays one
role: **orchestration bookkeeping outside the proof assistant**. You model the
arc (assumptions, lemmas, theorems, dependencies, proof witnesses); ZIL computes
statuses and impact. The proof assistant's kernel remains the sole proof
authority — a `proof:...` token *names* a checked declaration, it never asserts
one. Never present ZIL status output as proof of a mathematical claim.

## Running

`./bin/zil` needs Java + `dist/zil-standalone.jar` (build once with
`./bin/build-jar`) or falls back to the `clojure` CLI. If the script lacks the
executable bit, run `bash bin/zil ...`. `./bin/zil --help` lists all
subcommands. Note: `tools/*.sh` have CRLF line endings; prefer the `bin/zil`
subcommands over those wrappers.

## Core workflow: theorem-dependency arc

Author a `.zc` model **inside this repo** (the DSL libset resolves relative to
the model path — a model outside the tree fails with "Unknown macro
invocation"). Runnable template: `examples/formalization-arc-demo.zc`.

Vocabulary (macros from `lib/theorem-dsl-macros.zc`):

```zc
MODULE my.arc.

USE THM_COMPONENT(lean4_mathlib, tier0).            // toolchain/context deps
USE THM_COMPONENT_HEALTHY(lean4_mathlib, check).    // or THM_COMPONENT_BROKEN(id, src, reason)

USE ASSUMPTION(a_hyp, hypothesis).                  // physical/mathematical hypotheses
USE ASSUME_HOLDS(a_hyp, review).                    // or ASSUME_BROKEN(a_hyp, src, reason)

USE LEMMA(l_step, high).
USE LEMMA_REQUIRES_ASSUMPTION(l_step, a_hyp).
USE LEMMA_REQUIRES_LEMMA(l_step, l_other).
USE EVIDENCE_FOR_LEMMA(l_step, lean4, proof:Namespace.decl_name).

USE THEOREM(t_main, high).
USE THEOREM_REQUIRES_ASSUMPTION(t_main, a_hyp).
USE THEOREM_REQUIRES_LEMMA(t_main, l_step).
USE THEOREM_ENSURES(t_main, guarantee_token).
USE EVIDENCE_FOR_THEOREM(t_main, lean4, proof:Namespace.main_decl).

USE DSL_SUMMARY_QUERIES().                          // standard status/impact queries
```

Convention: the third argument of `EVIDENCE_FOR_*` is the fully qualified
declaration name in the proof-assistant repo (engine token: `lean4`, `acl2`,
`tlaps`, ...). Keep these exact so an agent can round-trip model ↔ Lean source.

Run the one-shot pipeline:

```bash
./bin/zil theorem-dsl-ci examples/formalization-arc-demo.zc /tmp/arc
```

It preprocesses against `libsets/theorem-dsl-ci/`, executes, generates an
LTS/POLICY theorem bridge, bundle-checks it, exports TLA+ and Lean skeletons,
and writes `<model>.dsl.summary.json` with:

- `status_counts` / `statuses` — per-theorem `PROVED | CONDITIONAL | WEAK | BROKEN`
  (PROVED: witness present, dependencies satisfied; CONDITIONAL: witness present
  but rests on an unverified assumption; WEAK: no witness yet — these are the
  open targets to prove next; BROKEN: a dependency is broken)
- `missing_dependencies` — referenced-but-undeclared nodes (modeling bugs)
- `break_roots` / `impact_set` — which broken assumption/component is the root
  cause and exactly which theorems it invalidates

## Impact analysis ("what if this assumption fails?")

Flip one line — `ASSUME_HOLDS(a_hyp, review)` →
`ASSUME_BROKEN(a_hyp, review, counterexample_found)` — and rerun. Downstream
theorems flip to BROKEN, `break_roots` names the root, `impact_set` lists every
affected theorem. Use this before refactoring a hypothesis, or to audit which
results a disputed physical assumption actually supports.

## Machine-readable extraction

```bash
./bin/zil export-data /tmp/arc/<model>.dsl.pre.zc json out.json queries
```

emits `{query_name: [rows]}` (e.g. `dsl_theorem_statuses`,
`thm_dependency_dag`, `thm_proof_registry`) — parse this instead of scraping
EDN console output. `query-ci <model.zc> [out.edn] [lib_dir]` snapshots query
results for regression gating in CI.

## Lower-level and adjacent layers

- Canonical `THM_*` macros (`lib/theorem-impact-macros.zc`) are what the DSL
  lowers to; queries `thm_dependency_dag`, `thm_lemma_states`,
  `thm_predicted_break_theorems` work there too. Preprocess manually when using
  them outside the one-shot: `./bin/zil preprocess m.zc /tmp/m.pre.zc
  libsets/theorem-dsl-ci` then `./bin/zil /tmp/m.pre.zc`.
- Category-theory specs: `lib/category-theory-macros.zc` (`CT_CATEGORY`,
  `CT_FUNCTOR`, `CT_NAT_ISO`, `CT_LEAN4_THEOREM`, `CT_QUERY_MISSING()` for
  unproved CT obligations).
- Proof-obligation evidence from other tools:
  `./bin/zil proof-obligation-check <model> acl2` (artifact mode; see
  `docs/acl2-integration.md`).
- `export-lean` / `export-tla` target `LTS_ATOM` state machines only — theorem
  triples export via the bridge inside `theorem-dsl-ci`, not directly.

## Docs

`docs/theorem-dsl-ci-workflow.md`, `docs/theorem-impact-macro-layer.md`,
`docs/tooling-workflows.md`, `spec/zil-formal-core-v0.1.md`,
`docs/language-design.md`.
