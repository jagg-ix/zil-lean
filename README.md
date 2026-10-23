# ZIL Lean

ZIL is a small relational language for describing  objects, the relationships between them, and rules that derive additional relationships.

Developers, review tools, CI, documentation tools, and AI assistants can query the same stored relationships.

## Quick start


```bash
git clone https://github.com/jagg-ix/zil-lean
cd zil-lean
lake build        # the library and its tests
lake build zil    # the command-line tool used below
```

The first build compiles the whole library and took about a minute on a laptop. While it builds, Lean prints deprecation warnings for
the library's source code. They do not affect the result.


## Relation tuples: from Zanzibar to ZIL

ZIL's relation model is influenced by the tuple-oriented model described in Google's Zanzibar paper:

[Zanzibar: Google's Consistent, Global Authorization System (USENIX ATC '19)](https://storage.googleapis.com/gweb-research2023-media/pubtools/5068.pdf)

Section 2.1 represents an authorization tuple as:

```text
object#relation@user
```

Table 1 gives these examples:

```text
doc:readme#owner@10
group:eng#member@11
doc:readme#viewer@group:eng#member
doc:readme#parent@folder:A#...
```

They describe four useful relation patterns:

```text
user 10 is an owner of doc:readme
user 11 is a member of group:eng
members of group:eng are viewers of doc:readme
doc:readme is in folder:A
```

The third tuple uses the userset:

```text
group:eng#member
```

This userset names everyone related to `group:eng` through `member`. A tuple can therefore refer to another relation, supporting group membership and inherited access.

The `.zc` syntax expresses the same tuples:

```zc
doc:readme#owner@user:10.
group:eng#member@user:11.
doc:readme#viewer@group:eng#member.
doc:readme#parent@folder:A.
```

The native Lean syntax expresses the same relations as Lean declarations:

```lean
import Zil

zil_fact
  node(doc.readme)
    ⟶[owner]
  node(user.u10)

zil_fact
  node(group.engineering)
    ⟶[member]
  node(user.u11)

zil_fact
  node(doc.readme)
    ⟶[viewer]
  node(group.engineering)
```

Zanzibar uses relation tuples to describe authorization data. ZIL uses the same compact relational building blocks for authorization models and for wider project relationships:

```text
document ───── viewer ──────▶ group
declaration ── implements ──▶ requirement
theorem ────── validates ────▶ component
module ─────── dependsOn ────▶ module
task ───────── blockedBy ────▶ issue
claim ──────── supportedBy ──▶ document
```

## Lean and ZIL in one project

Lean verifies terms, types, definitions, computation, theorem statements, and proofs.

ZIL stores relationships concerning purpose, coverage, dependencies, evidence, tasks, and review work across the repository
it also implements its own macro system that allows you to extend it with your own DSL extensions to the language so you can leverage lean4 powers.

Together they support questions such as:

- Which declaration implements a requirement?
- Which theorem validates a transformation?
- Which modules depend on a changed declaration?
- Which claims have supporting documents?
- Which work items are waiting for a result?
- Which advertised capabilities have implementation links?
- Which facts and rules produced an inferred relationship?
- Which project assumptions changed since the previous work session?

These relationships can connect Lean declarations to requirements, documents, issues, tests, tools, and external sources across many modules.

## Core model

ZIL uses four primary structures:

- **nodes** identify declarations, requirements, claims, tests, files, tasks, users, groups, or other objects;
- **relations** connect two terms;
- **rules** derive relations from existing relations;
- **queries** return matching terms and variable bindings.

Nodes use stable names:

```text
lean.Parser.parse
lean.Normalize.normalized_sound
requirement.parseInput
component.normalizer
issue.missingTerminationProof
document.design.section4
assistant.formalization
```

## Facts, rules, and queries

Register a fact:

```lean
zil_fact
  node(lean.Parser.parse)
    ⟶[implements]
  node(requirement.parseInput)
```

Declare a theorem-shaped rule:

```lean
zil_theorem_rule implementationCoversRequirement
  {declaration requirement : Zil.Node}
  (hImplements : declaration ⟶[implements] requirement)
  : requirement ⟶[coveredBy] declaration
```

The block form expresses the same rule:

```lean
zil_rule implementationCoversRequirement where
  variables declaration requirement
  premises
    declaration ⟶[implements] requirement
  conclusion
    requirement ⟶[coveredBy] declaration
```

Both forms produce the standard `Zil.Rule` value used by the engine and tools.

A query can retrieve the implementation covering a requirement:

```lean
private def coverageQuery : Zil.Query := {
  name := `implementationForRequirement
  variables := #[`declaration]
  select := #[`declaration]
  premises := #[
    .mk'
      (.ground `requirement.parseInput)
      `zil.coveredBy
      (.variable `declaration)
  ]
}
```

The engine binds variables, joins the premises, removes duplicate results, and applies the rules until a fixed point is reached or the
configured bound is hit.

## Relation schemas

A relation schema records the expected source and target types:

```text
implements  : declaration → requirement
validates   : theorem → component
dependsOn   : declaration → declaration
blockedBy   : task → requirement
supportedBy : claim → evidence
member      : group → user
viewer      : document → user-or-group
```

In Lean, a `Profile` lists the relations and the kind of node at each end, and a `TypedRule` pairs a rule with the kind of each variable
and the profile that validates it. This excerpt is from `examples/lean/03_TypedRule.lean`, which defines the rule `requirementPropagation`
and also shows the failing case:

```lean
private def research : Profile := {
  name := `profile.research
  version := "1"
  relations := #[
    { relation := `zil.formalizes, subjectKind := .declaration, objectKind := .claim },
    { relation := `zil.requires, subjectKind := .declaration, objectKind := .requirement },
    { relation := `zil.requiresClaim, subjectKind := .claim, objectKind := .requirement }
  ]
}

private def researchKinds : Array VariableKind := #[
  { «variable» := `declaration, kind := .declaration },
  { «variable» := `claim, kind := .claim },
  { «variable» := `requirement, kind := .requirement }
]

private def typedRequirementPropagation : TypedRule := {
  profile := research
  variableKinds := researchKinds
  rule := requirementPropagation
}

#guard typedRequirementPropagation.valid
```

A rule that uses a relation with the wrong kinds of endpoints, such as `formalizes` pointing at a requirement, is reported as invalid by
`valid`. The rule value itself stays available for diagnostics and tools.

## Sharing the relationship graph between people and tools

ZIL stores selected project facts with the source code. Developers, reviewers, build tools, documentation tools, issue trackers, and AI
assistants can use the same graph.

### Continue work from a previous session

```text
file.Parser.lean ── responsibleFor ──▶ requirement.parseInput
lean.Parser.parse ── implements ─────▶ requirement.parseInput
```

A developer or assistant can inspect why a file exists and which requirement its declarations serve before editing it.

### Find blocked work

```text
requirement.totalParser ── blockedBy ──▶ issue.missingTerminationProof
issue.missingTerminationProof ── assignedTo ──▶ task.proveTermination
```

Queries can find blocked requirements, tasks awaiting an owner, and capabilities awaiting an implementation link.

### Compute change impact

```text
lean.Normalize.normalize ── dependsOn ──▶ lean.Parser.parse
lean.Codegen.emit ───────── dependsOn ──▶ lean.Normalize.normalize
```

Impact rules return the downstream components that require review when `lean.Parser.parse` changes. The command `bin/zil impact` does
the same analysis from the command line (see the Quick start).

### Check long-running changes

Automated work that runs for a while needs a safeguard against acting on stale information. Three commands provide it:

- `bin/zil action-token` validates the preflight evidence and the intent of an action token;
- `bin/zil token-lifecycle` replays the binding of the token to a checkpoint and its single use, and checks the revision, expiry, lease,
  store and the hash of the observed output;
- `bin/zil recovery-audit` verifies the required postconditions and checks that any recovery used the rollback or compensation that was
  committed when the token was issued.

The specifications are `spec/action-token-v1.md`, `spec/token-lifecycle-v1.md` and `spec/recovery-audit-v1.md`, and
`examples/action-token/` and `examples/recovery-audit/` contain models to run them on.

### Explain derived relations

Each derived relation records its provenance:

```text
the rule that produced it
the variable bindings
the identifiers of the input facts
```

`bin/zil explain-query` prints this derivation step by step, so developers and tools can see how the engine reached a result
(`spec/derivation-provenance-v1.md`).

### Share context between tools

A `ZILR/1` revision log records changes to the graph as numbered revisions with a causal order; `bin/zil revision-summary`, `snapshot` and
`causal-check` read it. The `ZIL-EXCHANGE/1` protocol (`bin/zil worker`, specified in `spec/exchange-protocol-v1.md`) exposes parsing,
compiling, expansion, querying, authorization and impact analysis as JSON Lines, so separate tools can use one Lean implementation.
`bin/zil agent-context` produces the context bundle for a task from the graph (`spec/agent-context-v1.md`).

Authorization-style relations can also describe roles in an automated workflow:

```text
repo.zilLean ── editor ─────▶ group.implementers
group.implementers ─ member ▶ assistant.codegen
repo.zilLean ── reviewer ───▶ assistant.verifier
```

The tuple model therefore supports project context and role-based access to project operations.

## Persistence, contracts, and linting

Facts, rules, schemas, profiles, declarations, theorem intents and file contracts are stored in Lean environment extensions. Compiled
`.olean` imports restore the registered entries and collapse repeated diamond imports into one relation (`examples/lean/05_ImportedKnowledge.lean`).

A file contract records what a Lean file promises: its scope, the objects it requires, the substitutes it forbids, its abstraction level, and
its completion status. This contract is from `Zil/Test/HornGrounding.lean`:

```lean
zil_file_contract zil.test.hornGrounding where
  promises "A grounded test contract exercising the Horn grounding command."
  at_level bridge_theorem
  contract_status scaffold
  requires_objects ["lean:Zil.Test.HornGrounding.groundingWitness"]
  forbids_substitutes ["none"]
  witnessed_by [groundingWitness]
```

The lint commands report on a contract:

```lean
#zil_file_contract zil.test.hornGrounding       -- show the contract
#zil_missing_requirements zil.test.hornGrounding -- required Lean objects that do not resolve
#zil_formalization_lint zil.test.hornGrounding   -- coverage percentage and problems
#zil_formalization_lint_all                      -- the same for every contract in the module
```

Contracts give maintainers and tools a shared description of the expected result of a task or file.

## Trust levels

Each rule has one of three trust classes (`Zil.TrustClass`):

```text
asserted
graphDerived
certified
```

- `graphDerived` marks a relation inferred by a graph rule. Every frontend assigns it today: `zil_rule`, `zil_theorem_rule` and the `.zc`
  syntax;
- `asserted` is intended for directly stated information;
- `certified` is intended for reasoning that the Lean kernel has checked.

No frontend assigns `asserted` or `certified` yet. They exist in the type and in the text codecs, so rules that carry them can be
exchanged. `spec/lean-native-acceptance-v0.1.md` (section D) states the requirement for `certified`: a graph-derived fact must never
acquire kernel-checked trust through an ordinary rule.

Lean checks definitions, theorem statements and proofs, and ZIL records how those checked declarations participate in the project graph.
Claims that need a proof are audited by `bin/zil theorem-audit`, which fails a high-criticality theorem that has no proof evidence
(`spec/theorem-audit-v1.md`), and `bin/zil proof-obligations` lists the proof obligations for each prover.


## Use cases

ZIL Lean can support:

- links from informal claims to Lean declarations;
- requirement-to-implementation tracking;
- theorem and component dependency analysis;
- change-impact queries across modules;
- evidence and source tracking;
- repository coverage checks;
- explicit task contracts for people and tools;
- AI assistants continuing work across sessions, guarded by revision and action-token checks;
- step-by-step explanations for inferred project relationships;
- interchange with Terraform/OpenTofu and TLA+ models.

## The `.zc` language

ZIL is implemented in Lean. The `.zc` syntax (facts, rules, queries, macros, declarations and embedded annotations) is parsed, expanded,
compiled and queried by the native Lean engine, through `bin/zil compile`, `expand`, `query-ci`, `conformance` and the audits listed under
*Native CLI and data exchange*. There is no other runtime, and nothing here depends on Clojure. An earlier Clojure/DataScript runtime was
removed. Its control plane, plugin loader, release attestation, placement evaluation, embedded blocks, datasource ingest, and its HCL,
TLA+ and LTS tools were rewritten in Lean (see *Operations and exchange tools*), and `spec/clojure-removal.md` records where each part
went. `scripts/check-no-clojure.sh` keeps Clojure out of the repository.

## Macro libraries

The macro engine and the nearest-`lib/` rule are part of this repository. The opt-in macro libraries (`libsets/`: model substrate,
process algebra, proof evidence, discovery API, AWS, Souffle compatibility and others) live in
[zil-lib](https://github.com/jagg-ix/zil-lib). That repository depends on this one at a pinned commit, tests each library against
reviewed golden files, and keeps a catalog. Load a library with `--lib`:

```bash
bin/zil expand model.zc - --lib <zil-lib>/libsets/process-algebra
```

The last commit of this repository that still holds `libsets/` is tagged `last-with-libsets`.

A keyword value written with a leading colon, such as `move=:N`, is read as the name without the colon, so the Petri-net layer in
`examples/petrinet-nd-macro-layer.zc` compiles natively.



## License

[Apache License 2.0](LICENSE). A contribution is accepted under the same terms (section 5 of the license). The macro libraries that used
to live here are in [zil-lib](https://github.com/jagg-ix/zil-lib), under the same license.
