# ZIL to Apalache: targets and tests (living checklist)

Status: nothing below is started. This file is the work list; the contract for the lowering itself is written
first (target APL-00).

This is **not part of the ZIL language or its engine**. It is a toolkit that uses ZIL, plus one optional macro
extension that lets a model say what to check. See *Where the work lives*.

Rule for every target, as in `spec/model-substrate-targets-v0.md`: write the failing tests, see them fail for the stated
reason, implement, see them pass, then start the next target. The compatibility gate below is green at every step.

## Why

ZIL answers questions about one concrete set of facts: `bin/zil query-ci` closes the facts under the rules and solves
the queries. It cannot say whether a rule set misbehaves on a fact set nobody wrote down, or what a *sequence* of changes
to the facts can do. [Apalache](https://apalache-mc.org) is a symbolic model checker for TLA+ that works over a bounded
number of steps and a bounded size of the domain, using an SMT solver. Lowering a ZIL program to Apalache's input lets
the same program be checked over *all* fact sets of a given size, and over all sequences of administrative operations of
a given length, and returns a counterexample when one exists.

The goal is to find violations and to rule out violations inside stated bounds, with Lean staying the authority on what
a program means. It is not to replace the Lean proofs.

## Where the work lives

Three places, and the dependency runs one way: the toolkit uses ZIL, ZIL never uses the toolkit.

| Place | What goes there | Rule |
|---|---|---|
| ZIL core (`Zil/`, `bin/zil`, the language specs) | nothing new | No Apalache code, no `bin/zil apalache`, no `#zil_apalache_*` command, no change to the parser or the declaration kinds. The default profile never knows the tool exists. |
| A macro extension in `libsets/` | the vocabulary for saying what to check: domain bounds, invariants, public projections, operations | Opt-in like `libsets/model-substrate`. It adds no relation kind and no syntax: every macro expands to ordinary tuples, rules and queries. It is qualified by `tools/macro_extension_matrix.sh` against a reviewed golden, and means nothing to the engine; the toolkit gives it meaning. |
| A toolkit (its own Lake package, with its own executable and gate, depending on `zil-lean` at a pinned commit) | the IR types and printer, the lowering, the runner, the trace reader, replay, evidence, the commands, the experiments | Reads a model after `bin/zil expand` (or the `Zil` library's `Program`). Replays every counterexample with the `Zil` evaluator. Optional JVM tool found at run time. |

Whether the toolkit is a directory of this repository or a repository of its own is open (see *Open questions*). Either way
the rows above hold: nothing of it is built or tested by the core profile.

Existing libraries already cover part of the vocabulary and are reused, not copied: `MODEL_STATE`, `MODEL_INITIAL`,
`MODEL_TRANS` (transitions), `TIME_TICK`, `TIME_LT`, `TIME_AGE` (time), `VC_*` (vector clocks), `RBD_*` (subjects, roles,
grants, sessions, requests), and `LEAN_PROOF` (evidence that a Lean theorem backs a claim).

## What exists today (checked against this repository)

| Piece | Where | Use here |
|---|---|---|
| Program: tuples, rules, queries, declarations | `Zil/Core/Program.lean` | input of the lowering |
| Closure with stratified negation (`Zil.Engine.stratify`, `closure`), query solving (`solve`) | `Zil/Engine/Query.lean` | the oracle every lowering is compared with |
| Rule safety: negative and head variables bound by positive premises | `Zil.Rule.safe` in `Zil/Core/Rule.lean` | the lowering refuses unsafe rules |
| Usersets, attributes | `Zil/Core/Userset.lean`, `Zil/Core/Attribute.lean` | lowered to relations |
| Revisions, causal graph, vector clocks | `Zil/Core/Revision.lean`, `spec/revision-causal-v0.1.md` | APL-43 |
| Ordered, byte-stable JSON | `Zil/Json/Ordered.lean` | emits the IR; the same bytes are hashed |
| Running a program with a deadline | `Zil/Process/Run.lean` | runs the checker |
| Evidence from a program outside Lean, with its assurance label | `spec/evidence-envelope-v1.md`, `spec/assurance-levels-v1.md`, `Zil/Plugin/` | how a result is recorded |
| A model exported as TLA+ text | `Zil/Export/Lts.lean` (`export-tla`) | a precedent for generated TLA+ and its tests |
| Query governance: query packs and profiles | `Zil/QueryGovernance.lean`, `examples/query-governance/` | read-only; see the corrections |

Nothing in the repository mentions Apalache yet.

## Corrections to the first plan

The plan this list comes from was written without reading the code. Where it differs from the repository, the repository
wins, and the target says what to do about it.

1. `#zil_horn_grounding` (`Zil/Datalog/HornGrounding.lean`) does not certify that rules are range-restricted. It checks that
   a *file contract's* required objects and witnesses resolve in the Lean environment, using the Horn engine. The safety
   check for rules is `Zil.Rule.safe`. The lowering must call it and refuse unsafe rules (APL-13).
2. `examples/query-governance/operations.zc` is a read-only query pack (`QUERY_PACK`, `DSL_PROFILE`, two queries). It has
   no operations that change facts. A language for administrative operations does not exist and is APL-31; the temporal
   targets cannot start before it.
3. `Zil/Test/QueryGovernance.lean` is a file of `#guard` tests. "Every governance branch" has no meaning until APL-42
   defines coverage over rules.
4. Datalog closure and userset chains are recursive. Apalache does not execute recursive definitions; recursion has to be
   unrolled or folded to a fixed depth. The depth is part of every claim and has to be derived, not guessed (APL-13).
5. "All possible graphs" means all graphs whose nodes come from a fixed-size domain. An answer of *no violation* holds
   inside that size. It is evidence, not a proof, and the small-scope heuristic (most bugs show up on small instances) is an
   observation, not a theorem. Wording in code, specs, reports and commands says *checked within bound N and depth d*, never
   *proved* or *100%*, unless a theorem for the fragment is written down.
6. Apalache documents the JSON IR for its `parse` and `typecheck` commands. Whether `check` takes the JSON directly, where
   counterexamples are written, and in which format, depends on the version; APL-01 settles it by experiment.
7. Apalache runs on the JVM. It is an optional external tool, found at run time. Building and testing this repository must
   never need it, and the checks in this file that need it are skipped, with a clear message, when it is absent.
8. The first plan put the commands in the language (`#zil_apalache_universal`, `#zil_equiv`, `lake exe zil-gen-tests`). They belong
   to the toolkit's own executable and, if wanted later, to a command in the toolkit's own library, not to `Zil` or `bin/zil`.
   Executable names are camel case, as the other `lean_exe` targets are.

## Compatibility gate (every target)

- The core is untouched: no file under `Zil/`, no `bin/zil` command and no `lakefile.lean` target of the core mentions Apalache.
- `bin/zil test --profile lean` passes with no Apalache and no `java` on `PATH`. Prove it with failing `java` and
  `apalache-mc` shims that exit 99, as the Clojure removal was proved.
- `lake build zilLeanTests` passes, including the existing suites.
- `scripts/check-no-clojure.sh` passes.
- The toolkit has its own gate. Its pure tests (IR types, printing, ITF parsing, replay on recorded traces) run without the tool;
  tests that need it run only with `--with-tool` and say *skipped: apalache-mc not found* otherwise. The macro extension is in the
  core's macro matrix.
- Every generated file is byte-stable: the same program gives the same bytes. The IR's SHA-256 appears in each report.
- Public content policy (`PUBLIC-CONTENT-POLICY.md`): examples are invented; nothing from a private system.
- A new test is shown to fail by a real rebuild of a deliberately broken implementation, not by a build that failed.

## Targets

Strategic targets are S1 to S3. The others are the steps that lead to them, and optional extensions.

| ID | Target | Done when | Needs | Status |
|---|---|---|---|---|
| APL-00 | Lowering contract | `spec/apalache-lowering-v0.1.md` states: the sort scheme, the state variables, how facts, rules, negation, usersets and attributes are lowered, the closure depth bound, the invariant language, what is out of scope, and the assurance rule. The questions under *Open questions* are answered. | none | not started |
| APL-01 | Tool spike | With Apalache installed by hand, three hand-written IR modules (a fact, a join, a negation) type-check and check, and `spec/apalache-tool-notes.md` records the version, the exact commands, whether `check` accepts the JSON, where counterexamples and traces are written, the exit codes, and how the domain size of an uninterpreted sort is fixed. | none | not started |
| APL-05 | Check vocabulary (macro extension) | `libsets/<name>` with macros for domain bounds (`CHECK_BOUND`), invariants as queries that must return nothing (`CHECK_INVARIANT`), public projections for non-interference (`CHECK_PUBLIC`), and operations (`CHECK_OPERATION`: guard, adds, removes), all expanding to ordinary tuples, rules and queries; a matrix row with reviewed goldens; two invented examples expand and compile; the existing `MODEL_*`, `TIME_*`, `VC_*` and `RBD_*` macros are reused | APL-00 | not started |
| APL-10 | IR types and JSON | toolkit `Apalache/IR.lean`: inductive types for the module, declarations, expressions and operators of Apalache's JSON IR (ADR-005) and for its types (ADR-002); emission through `Zil.Json`; a reader; 12 hand-written modules round-trip and match golden bytes; when the tool is present each also type-checks | APL-00, APL-01 | not started |
| APL-11 | Printer | the toolkit's `show` command prints the IR as TLA+ text for review, with golden tests; the printed text of the APL-01 modules is accepted by the tool's own parser when present | APL-10 | not started |
| APL-12 | Facts to state | A program's facts become state variables and an `Init`; relation names, nodes, attribute values and revisions have the sorts the contract fixes; a fully ground program lowers and checks at length 0 | APL-10 | not started |
| APL-13 | Rules to a step operator | Safe rules (`Zil.Rule.safe`) become one-step operators over sets; stratified negation follows the strata of `Zil.Engine.stratify`; usersets and `tupleToUserset` rewrites are covered; closure is an unrolled iteration to a derived depth; an unsafe rule is refused with the rule's name. **Differential test:** on every program of the chosen corpus subset and on at least 200 generated programs (fixed seeds, domain size up to 4), the relations Apalache derives from a ground `Init` equal `Zil.Engine.Query.closure`. | APL-12 | not started |
| APL-14 | Queries | A `QUERY` becomes a set expression; for the same programs, Apalache's answer equals `solve` | APL-13 | not started |
| APL-20 | Runner | toolkit `Apalache/Run.lean` finds the tool (`APALACHE_HOME`, then `PATH`), records its version, runs it in a fresh output directory with a deadline, never touches the network, and returns *tool unavailable* as a result, not an error | APL-01 | not started |
| APL-21 | Trace reader (ITF) | toolkit `Apalache/Itf.lean` reads the Informal Trace Format (ADR-015): states, sets, tuples, records, maps, big integers, loops, uninterpreted values; real traces written by the tool are checked in as fixtures and round-trip | APL-01 | not started |
| APL-22 | Witness replay | A trace is mapped back to ZIL facts and re-run through the Lean evaluator (or, for APL-32, through the Lean operation semantics). A counterexample is reported only if Lean confirms the violation; a mismatch is reported as a defect of the lowering or the tool, with the trace attached | APL-13, APL-21 | not started |
| APL-23 | Commands | The toolkit's `check`, `typecheck` and `show` commands; exit codes: 0 no violation within bound, 1 violation confirmed, 2 bad input, 3 tool unavailable | APL-20, APL-22 | not started |
| APL-24 | Evidence | Each run writes a `ZIL-EVIDENCE/1` envelope: role `bounded-model-checker`, authority `external`, assurance `externally-attested`, the IR hash, the tool version, the command, the bounds (domain size N, depth d, steps k) and the verdict. A confirmed counterexample carries its replay and is `validated`. Nothing is `kernel-backed` | APL-20 | not started |
| **S1** APL-30 | Universal contract check | The toolkit's `universal` command: `Init` is symbolic over a domain of N nodes; the invariant is a query that must return nothing; the report lists N, depth, time and verdict for N = 2 to 6 on three example policies, one of which has a seeded flaw that is found at N ≤ 3 and replayed | APL-14, APL-22, APL-23 | not started |
| APL-31 | Operations | The `CHECK_OPERATION` macros of APL-05 (parameters, a guard written as a query, adds and removes of tuples), a Lean executor in the toolkit that applies an operation to a fact set, a spec, and two invented examples (delegation with a bounded depth; an administrator who can remove the last administrator) | APL-00 | not started |
| **S2** APL-32 | Temporal governance | `Next` is the disjunction of the operations; The toolkit's `trace` command with `--length=k` checks reachability (can a principal come to hold a permission), separation of duty, and lockout (a state where no operation is enabled, or no administrator remains). Every trace is replayed by the Lean executor | APL-31, APL-22 | not started |
| **S3** APL-33 | Non-interference | Two copies of the state start equal on a stated public projection and differ elsewhere; the invariant is that the public queries of both copies stay equal. The observation function (which relations a principal sees) is written in the spec. A leaking policy is found with a replayed pair of traces; a non-leaking one passes within bound | APL-32 | not started |
| APL-40 | Equivalence | `equiv A B`: one shared symbolic `Init`, invariant that the derived relations agree; a counterexample shows the smallest graph where they differ, replayed in Lean on both programs | APL-30 | not started |
| APL-41 | One-step induction | `inductive`: starts from any state satisfying a candidate invariant and takes one step (`--length=1`, with the candidate as `Init`); a counterexample to induction is replayed; the command explains that passing is not a proof | APL-32 | not started |
| APL-42 | Test generation | `zilGenTests`: for each rule and each operation, the goal "this fires" is negated, the trace is read back and written as a Lean test with concrete facts under `Zil/Test/Generated/`; coverage is defined over rules and operations, reported, and the generated files are reviewed before they are committed | APL-32 | not started |
| APL-43 | Stale views | Revision-tagged facts and per-replica views over `RevisionStore` and `CausalGraph`; the invariant that a removal followed by a later addition is never undone by a stale read, checked within bound; the model is written in the spec first | APL-32 | not started |
| APL-44 | Numeric limits | Integer attributes and counters lowered to integer arithmetic for quota and session-count invariants. Decimal attribute values are kept as text today, so the number domain is fixed in the contract first | APL-32 | not started |
| APL-45 | Composition | Assume-guarantee: a policy module with a stated interface (assumptions, guarantees) checked alone, and the composition rule written and tested on two modules | APL-30 | not started |
| APL-46 | Repair hints | From a replayed counterexample, name the rule instance that fired and print candidate patches (a missing negative premise, a guard). It only suggests; it never edits a file | APL-40 | not started |

Order that keeps something useful at every step: APL-00, APL-01, APL-05, APL-10, APL-11, APL-12, APL-13, APL-14 (the lowering
exists and agrees with the evaluator), then APL-20 to APL-24 (the tool is usable), then S1. APL-31 can start as soon as
APL-05 is accepted and runs in parallel with APL-10 to APL-14. S2 and S3 follow.

## Open questions for APL-00

Answer these in the contract before writing code.

0. **Location of the toolkit.** A directory of this repository with its own `lakefile`, or a repository of its own that pins
   `zil-lean`? A separate repository keeps the core clean by construction; a directory shares the macro matrix and the
   release. Decide before APL-10; the macro extension stays in `libsets/` either way.

1. **Sorts.** ZIL terms are untyped nodes. Use one uninterpreted sort for all nodes, or add optional signatures for
   relations (so a domain can be N users and M objects)? Signatures shrink the search a lot and also document policies;
   they are a language addition and need their own spec.
2. **Relations as state.** One set variable of pairs per relation, or one set of triples with the relation as a value?
   Attributes: extra tuple components, or separate relations?
3. **Closure depth.** For a linear recursion over a binary relation, depth N suffices. In general the bound is the size of
   the Herbrand base of the stratum. State the rule used, compute it in Lean (`closureDepthBound`), and test that
   iterating to that depth gives the fixpoint on the generated programs.
4. **Invariant language.** A query that must return nothing is the least new syntax. Decide whether a named
   `INVARIANT` declaration is worth adding, and how an invariant refers to the state after a step.
5. **Counters and time.** What `ingest_ts`, revisions and decimals mean in the model (ignored, integers, or refused).
6. **Failure modes.** What the command does when the domain size makes the problem too large (a deadline and a clear
   *inconclusive* result, not a silent pass).
7. **Where Lean wins.** When Apalache says *no violation* and Lean's evaluator on a generated instance says *violation*, the
   lowering is wrong. Write down that Lean is always the reference, and what is filed when they disagree.

## Test inventory (to be filled by each target)

Each target adds its tests here before it is started, with the name and what it asserts, as the model substrate list does.
Starting points:

| Target | Tests |
|---|---|
| APL-05 | `expand_check_bound`, `expand_check_invariant`, `expand_check_operation`, `expand_check_public`, `matrix_row_golden`, `reuses_model_trans`, `unknown_macro_fails`, `arity_fails` |
| APL-10 | `ir_roundtrip`, `ir_golden_bytes`, `ir_type_strings`, `ir_rejects_untyped_operator` |
| APL-13 | `lower_refuses_unsafe_rule`, `lower_negation_follows_strata`, `lower_userset_chain`, `closure_depth_reaches_fixpoint`, `differential_corpus_subset`, `differential_generated_200` |
| APL-21 | `itf_roundtrip_recorded`, `itf_bigint`, `itf_map_and_set`, `itf_loop_marker`, `itf_rejects_missing_var` |
| APL-22 | `replay_confirms_real_violation`, `replay_rejects_fabricated_trace`, `replay_mismatch_is_reported` |
| APL-30 | `seeded_flaw_found_n3`, `clean_policy_passes_n2_to_n6`, `inconclusive_on_deadline` |
| APL-32 | `delegation_escalation_found`, `last_admin_lockout_found`, `separation_of_duty_holds`, `trace_replayed_by_executor` |
| APL-33 | `leaking_policy_found`, `isolated_policy_passes`, `observation_function_respected` |

## Taking a target

- Pick the lowest unblocked ID. Say which one in the pull request title.
- One target per pull request. Update this table in the same change: status, the test names, and what was measured.
- Write what the evidence shows with the right word: *checked within bound* for a pass, *violation confirmed by replay* for a
  failure, *tool unavailable* when the tool is missing. Never *proved*.
- Record tool versions and exact commands in `spec/apalache-tool-notes.md`. A result without them cannot be reproduced.
- Do not vendor the tool or its jar. The repository finds it on the machine and says so when it is not there.
- Do not merge to the main branch without the maintainer's word.

## Non-goals

- Replacing Lean proofs, or promoting a model-checker result to `kernel-backed`.
- Unbounded verification claims.
- Putting any of this into the language, the parser, the declaration kinds or `bin/zil`.
- Making Apalache, Java or any JVM tool a requirement of the build, the tests or the install.
- Lowering the query planner, macro definitions or the revision codecs; only expanded programs, queries and operations.
