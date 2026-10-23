# ZIL Lean

ZIL is a small relational language for describing named objects, the relationships between them, and rules that derive additional relationships.

A relation has three parts:

```text
subject ── relation ──▶ object
```

For example:

```text
lean.Parser.parse ── implements ──▶ requirement.parseInput
```

ZIL Lean implements this model inside Lean 4. Lean checks definitions, executable programs, theorem statements, and proofs. ZIL records how those checked declarations relate to requirements, documents, tests, tasks, dependencies, and other parts of a project.

The same project map can answer questions such as:

```text
which declaration implements this requirement?
which theorem validates this component?
which modules depend on this declaration?
which task is waiting for this result?
which declarations should be reviewed after this change?
```

Developers, review tools, CI, documentation tools, and AI assistants can query the same stored relationships.

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

Standalone ZIL can express the same tuple-shaped facts:

```zc
doc:readme#owner@user:10.
group:eng#member@user:11.
doc:readme#viewer@group:eng#member.
doc:readme#parent@folder:A.
```

Native ZIL Lean syntax represents the relations with Lean names:

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

### Datalog-style rules

Table 1 presents relation data. Rules describe how additional relations follow from that data. ZIL uses Horn rules, the rule form commonly used by Datalog systems.

For example:

```text
when a group can view a document
and a user belongs to that group,
the user can view the document
```

In ZIL Lean:

```lean
zil_theorem_rule groupViewer
  {document group user : Zil.Node}
  (hViewer : document ⟶[viewer] group)
  (hMember : group ⟶[member] user)
  : document ⟶[viewer] user
```

Given:

```text
doc.readme ─────────── viewer ──▶ group.engineering
group.engineering ──── member ──▶ user.u11
```

repeated rule evaluation adds:

```text
doc.readme ── viewer ──▶ user.u11
```

The same rule structure can derive project relationships, such as requirement coverage and change impact.

### First-order Horn clauses and HORC compatibility

`Zil.Horn` is the opt-in logic-programming layer for programs that need more
than finite Datalog terms. It adds:

- nested constructor terms and function symbols;
- variables with first-order unification and an occurs check;
- ordered definite clauses and recursive predicates;
- leftmost, depth-first SLD resolution with clause-order backtracking;
- explicit depth bounds, cutoff reporting, and bounded iterative deepening;
- auditable traces, independently replayed proof trees, and a soundness theorem
  connecting certified answers to the proof-facing `Entails` relation;
- a completeness theorem showing every finite `Entails` proof has a valid,
  executably replayable proof-tree certificate;
- a parser for the pure Prolog notation used by HORC `.hn` models.

The existing `Zil.Datalog` layer remains the default for finite bottom-up
workloads. Import `Zil.Horn` when constructor trees or top-down proof search are
required:

```lean
import Zil.Horn

open Zil.Horn

def program : Program :=
  match Parser.parseText "natural(zero). natural(successor(N)) :- natural(N)." with
  | .ok value => value
  | .error _ => []

def query : List Atom :=
  match Parser.parseGoalsText "natural(successor(zero))" with
  | .ok value => value
  | .error _ => []

example : HasCertifiedSolution program query 4 := by
  horn_certify
```

Run a HORC model directly from the command line:

```bash
lake exe zilHorc "$HORC_ROOT/src/horn/list.hn" \
  'member(X, cons(nil,1))' 16

lake exe zilHorc "$HORC_ROOT/src/horn/map.hn" \
  'maps_to(cons(cons(nil,a,0),b,1), K, V)' 32
```

Set `HORC_ROOT` to a HORC checkout. The command returns all answers reachable
within the supplied clause-application bound and says whether any branch was
cut off. The accepted language is deliberately pure definite Horn logic; Prolog
built-ins, cut, negation, arithmetic operators, and bracket-list syntax are not
silently emulated.

The versioned operational and proof contract is in
[`spec/horn-resolution-v0.1.md`](spec/horn-resolution-v0.1.md).

### Certified grounding of a formalization contract

`#zil_formalization_lint` reports a coverage *percentage* over a contract's
executable requirements. `#zil_horn_grounding` uses the Horn engine to answer a
sharper, structural question: does the contract's `requires_objects` /
`witnessed_by` closure actually *bottom out* in the environment? It reads the
live `zil_file_contract`, emits a `provided(o)` fact only for each `lean:`
requirement that resolves and a `witnessed(w)` fact only for each witness that
exists, and asks the SLD engine to derive `grounded(contract)` — accepting the
answer only after independent proof-tree replay. A dangling requirement or a
mistyped witness leaves a body atom unprovable, so the check fails and names the
unmet obligation.

```lean
import Zil

#zil_horn_grounding my.contract   -- one contract
#zil_horn_grounding_all           -- every contract declared in this module
```

## A project example

Consider a project containing a parser, a normalization pass, and a theorem about normalized output:

```lean
import Zil

zil_fact
  node(lean.Parser.parse)
    ⟶[implements]
  node(requirement.parseInput)

zil_fact
  node(lean.Normalize.normalize)
    ⟶[dependsOn]
  node(lean.Parser.parse)

zil_fact
  node(lean.Normalize.normalized_sound)
    ⟶[validates]
  node(lean.Normalize.normalize)
```

These facts form a relationship map:

```text
requirement.parseInput
          ▲
          │ implements
lean.Parser.parse
          ▲
          │ dependsOn
lean.Normalize.normalize
          ▲
          │ validates
lean.Normalize.normalized_sound
```

Lean checks the parser, normalizer, theorem statement, and proof. ZIL stores their project roles and connections.

A query can ask:

- which declaration implements `requirement.parseInput`;
- which components depend on the parser;
- which transformations have a validation theorem;
- which downstream declarations should be reviewed after a change.

## Rules derive project relationships

A rule can derive direct change impact:

```lean
zil_theorem_rule propagateImpact
  {changed dependent : Zil.Node}
  (hDepends : dependent ⟶[dependsOn] changed)
  : changed ⟶[affects] dependent
```

From the parser dependency, the engine adds:

```text
lean.Parser.parse
  ── affects ──▶
lean.Normalize.normalize
```

A second rule continues the relationship through several levels:

```lean
zil_theorem_rule propagateTransitiveImpact
  {source middle target : Zil.Node}
  (hFirst : source ⟶[affects] middle)
  (hSecond : target ⟶[dependsOn] middle)
  : source ⟶[affects] target
```

Local dependency facts can therefore support a repository-wide review query.

## Lean and ZIL in one project

Lean verifies terms, types, definitions, computation, theorem statements, and proofs.

ZIL stores relationships concerning purpose, coverage, dependencies, evidence, tasks, and review work across the repository.

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

## Quick start

The repository pins Lean to:

```text
leanprover/lean4:v4.31.0
```

Build the package and run the Lean tests:

```bash
lake build
lake exe zilLeanTests
```

Progressive native examples are under `examples/lean/`:

```bash
lake env lean examples/lean/01_FactsAndRelations.lean
lake env lean examples/lean/02_TheoremShapedRule.lean
lake env lean examples/lean/03_TypedRule.lean
lake env lean examples/lean/04_MultiStepQuery.lean
lake build KnowledgeBase
lake env lean examples/lean/05_ImportedKnowledge.lean
lake env lean examples/lean/06_ProjectVerificationArc.lean
```

All documented example groups are also runnable through the Makefile:

```bash
make examples                 # lean, native, and integration groups
make examples GROUP=lean      # one group; report in .zil/examples-reports/
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

The engine binds variables, matches several premises, removes repeated results, and applies rules until the result set becomes stable within the configured bound.

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

A typed rule declares the type of each variable:

```lean
zil_typed_rule typedCoverage using Zil.Profile.research where
  variables
    declaration : declaration
    requirement : requirement
  premises
    declaration ⟶[implements] requirement
  conclusion
    requirement ⟶[coveredBy] declaration

#guard typedCoverage.valid
```

The schema reports category mistakes while keeping the underlying rule available for messages and tools.

## Shared project maps for people and tools

ZIL stores selected project facts with the source code. Developers, reviewers, build tools, documentation tools, issue trackers, and AI assistants can use the same map.

### Continue work from a previous session

```text
file.Parser.lean ── responsibleFor ──▶ requirement.parseInput
lean.Parser.parse ── implements ─────▶ requirement.parseInput
```

A developer or assistant can inspect why a file exists and which requirement its declarations serve before editing it.

### Find work that is waiting

```text
requirement.totalParser ── blockedBy ──▶ issue.missingTerminationProof
issue.missingTerminationProof ── assignedTo ──▶ task.proveTermination
```

Queries can find blocked requirements, tasks awaiting an owner, and capabilities awaiting an implementation link.

### Calculate change impact

```text
lean.Normalize.normalize ── dependsOn ──▶ lean.Parser.parse
lean.Codegen.emit ───────── dependsOn ──▶ lean.Normalize.normalize
```

Impact rules return the downstream components that require review when `lean.Parser.parse` changes.

### Check long-running changes

```lean
zil_checkpoint beforeParserRefactor
#zil_check_mutation token
```

Change checks compare graph revisions, contracts, stated goals, and rollback checkpoints before automated work continues.

### Explain inferred relationships

Each inferred relation can record:

```text
input project facts
rule name
variable bindings
trust level
input relation identifiers
```

This gives developers and tools a step-by-step explanation of how the engine reached a result.

### Share context between tools

`ZILX/1` snapshots and `ZILD/1` deltas allow separate tools to exchange the same project map. One tool may inspect requirements, another implement code, another verify proofs, and another review impact while sharing stable relation names and revision numbers.

Authorization-style relations can also describe roles in an automated workflow:

```text
repo.zilLean ── editor ─────▶ group.implementers
group.implementers ─ member ▶ assistant.codegen
repo.zilLean ── reviewer ───▶ assistant.verifier
```

The tuple model therefore supports project context and role-based access to project operations.

## Persistence, linting, and contracts

Facts, rules, schemas, contracts, checkpoints, declaration links, and proof-backed rules use Lean environment extensions. Compiled `.olean` imports restore registered entries and collapse repeated diamond imports into one relation.

The coverage linter evaluates the stored and inferred relations:

```lean
#zil_lint
#zil_lint!
```

A formalization contract can record required declarations, required relations, advertised scope, completion state, and revision history:

```lean
zil_register_contract contract
#zil_contract_check
#zil_contract_check!
```

Contracts give maintainers and tools a shared description of the expected result of a task or file.

## Trust levels and relationship explanations

ZIL records three trust levels:

```text
asserted
graphDerived
certified
```

- `asserted` marks a directly registered project fact;
- `graphDerived` marks an inferred relation;
- `certified` associates a rule with a Lean proposition and proof term.

```lean
private theorem certificate : True := True.intro

private def certifiedRule : Zil.Trust.CertifiedRule :=
  .mkChecked graphRule True certificate

zil_register_certified_rule certifiedRule
```

Lean checks the proposition and proof term. ZIL records how the checked declaration participates in the project map.

For inferred relationships, the explanation data records the project fact, source, rule name, variable binding, trust level, and input relation identifiers. Developers and tools can use that data to show how a result was reached.

## Native CLI and data exchange

The native `zil` executable reads `.zc` models and `ZILR/1` revision logs:

```bash
bin/zil expand examples/native-cli/formalization-claims.zc -
bin/zil query-ci examples/native-cli/formalization-claims.zc
bin/zil revision-summary examples/revision/release.zilr
bin/zil snapshot examples/revision/release.zilr 2 -
```

Supported operations include `compile`, `expand`, `trace`, `query-ci`, `explain-query`, `explain-authorization`, `dependency-graph`, `impact`, `authorize`, `revision-summary`, `snapshot`, and `causal-check` (`bin/zil --help` lists them all). See `examples/native-cli/README.md` for the walkthrough.

Relations and rules have deterministic text codecs:

```lean
Zil.Codec.encodeRelation
Zil.Codec.decodeRelation
Zil.Codec.encodeRule
Zil.Codec.decodeRule
```

`ZILX/1` stores revisioned snapshots. `ZILD/1` stores incremental updates with base and target revisions, fact changes, rule changes, and schema changes.

Facts and rules can be exported to Soufflé Datalog or Prolog:

```lean
#zil_export_souffle
#zil_export_prolog
```

These interfaces let external analysis tools and assistants consume the same relational state used by the Lean implementation.

### Operations and exchange tools

Each is a Lean executable behind `bin/zil`; every one has a specification and a test gate that does not need Clojure.

| Command | What it does | Specification | Gate |
|---|---|---|---|
| `control` | formal control plane: exchange with the worker, hash-chained control events and receipts in SQLite | `spec/control-event-store-v1.md`, `spec/exchange-protocol-v1.md` | `scripts/test-control-plane.sh` |
| `plugin` | extension registry for `ZIL-EXTENSION/1` manifests, with quarantine and an external-command adapter | `spec/extension-manifest-v1.md` | `scripts/test-plugins.sh` |
| `evaluate-runtime` | scores where a component is best implemented, with exact arithmetic | `spec/runtime-evaluation-v1.md` | `scripts/test-evaluation.sh` |
| `release-attest` | binds a release request to its evidence | `spec/release-attestation-v1.md` | `scripts/test-release-attestation.sh` |
| `import-hcl`, `export-tla`, `export-lean` | Terraform/OpenTofu to ZIL; `LTS_ATOM` to TLA+ and to Lean | `spec/interop-v1.md` | `scripts/test-interop.sh` |
| `embedded-scan`, `embedded-snapshot`, `embedded-drift-check`, `embedded-native` | ZIL blocks written in comments of Lean, Python, Clojure, Rust and Markdown sources | `spec/embedded-blocks-v1.md` | `scripts/test-embedded.sh` |
| `ingest`, `import-data`, `convert-data` | `DATASOURCE` declarations to facts, causal edges and a revision log; data files to and from JSON, EDN, text, CSV, a YAML subset and key=value | `spec/datasource-ingest-v1.md` | `scripts/test-ingest.sh` |

Their expected outputs were written by the earlier implementation and are checked byte for byte or as data; the gates run
the Lean tools alone. The control store needs `sqlite3`, the gates need `python3`, and the REST adapter needs `curl`.

## Use cases

ZIL Lean can support:

- Zanzibar-style authorization and group-membership models;
- maps connecting informal claims to Lean declarations;
- requirement-to-implementation tracking;
- theorem and component dependency analysis;
- change-impact queries across modules;
- evidence and source tracking;
- repository coverage checks;
- explicit task contracts for people and tools;
- AI assistants continuing work across sessions with revision and checkpoint checks;
- step-by-step explanations for inferred project relationships;
- exchange of relation data with Datalog and Prolog tools.

## Shared model substrate (macro library)

`libsets/model-substrate` is an opt-in macro library that gives domain macros one shared vocabulary for structure (entities, associations, states, messages), intent (actors, use cases), scenarios (feature, case, given/when/then steps with explicit order) and the coverage links between them, plus coherence queries that list use cases without a scenario, scenarios without a use case, and `then` steps that realize nothing. It adds no relation kind or syntax; a model that does not load it is unchanged.

```bash
bin/zil expand examples/model-substrate/book-loan/model.zc - --lib libsets/model-substrate
bin/zil query-ci examples/model-substrate/book-loan/model.zc loan_profile - --lib libsets/model-substrate
scripts/test-model-substrate.sh
```

The contract is `spec/model-substrate-v0.1.md`; the targets and test inventory are `spec/model-substrate-targets-v0.md`. See `examples/model-substrate/README.md`.

## The `.zc` language

ZIL is Lean. The `.zc` syntax (facts, rules, queries, macros, declarations, embedded annotations) is parsed, expanded, compiled and queried by the native Lean engine: `bin/zil compile`, `expand`, `query-ci`, `conformance` and the audits listed under *Native CLI*. There is no other runtime and nothing here depends on Clojure. An earlier Clojure/DataScript runtime was removed; its control plane, plugin loader, release attestation, placement evaluation, embedded blocks, datasource ingest and HCL, TLA+ and LTS tools were rewritten in Lean (*Operations and exchange tools*), and `spec/clojure-removal.md` says where each part went. `scripts/check-no-clojure.sh` keeps Clojure out.

### Native macro extension qualification

`spec/macro-extension-matrix.tsv` records each macro library variant and a representative
model that exercises it. Run the full qualification from this directory:

```bash
./tools/macro_extension_matrix.sh
```

The check runs on the native engine alone. Each row's native expansion must equal its reviewed golden in
`spec/macro-extension-golden/`, the native frontend must compile the model, and the generated
Lean module must typecheck. A library column of `-` marks a model that defines its macros
inline. After an intended change to a library or the expander, run
`./tools/macro_extension_matrix.sh --update` and review the golden diff. Add a row when
introducing a macro library or extension; keep distinct legacy `lib/` variants represented even
when a similarly named `libsets/` copy exists.

The Souffle compatibility macros (`libsets/souffle-compat`) declare relations and facts in the form a Souffle program uses. They are qualified by the same matrix; the bridge that ran Souffle from ZIL belonged to the removed runtime. See `spec/souffle-macro-compat-v1.md`.

`bin/zil corpus` (`scripts/check-corpus.sh`) compiles every `.zc` file under `lib/`, `libsets/` and `examples/` alone and compares the outcome with `spec/corpus-status.tsv`, so a change in what compiles shows up in review. A macro file or a model that needs its library is rejected alone and recorded as such; the matrix covers those with their libraries.

## Extension libraries

Opt-in macro libraries, each selected with `--lib` and qualified by the macro matrix.

| Library | Adds | Example |
|---|---|---|
| `libsets/process-algebra` | temporal process prefixes with internal and external sides, pi-calculus hand-offs, vector clocks with required orders, and a discrete clock with windows | `examples/process-algebra-checks.zc` |
| `libsets/proof-evidence` | `LEAN_PROOF` and `LEAN_LEMMA_PROOF`, the kernel-evidence form `bin/zil theorem-audit` reads | `examples/proof-evidence/contracts.zc` |
| `libsets/discovery-api` | rules and queries over the facts of a Discovery-style API description (methods, schemas, fields, references) | `examples/discovery-api/sample-model.zc` |

The AWS, TLM, Petri-net, namespace, theorem, interop and other libraries are listed in
`spec/macro-extension-matrix.tsv`. `scripts/test-extension-libraries.sh` checks the row counts the
three libraries above must give on their examples, and that the theorem audit refuses a high
theorem without evidence.

Keyword values written with a leading colon, such as `move=:N`, read as the name without the
colon, so the Petri-net layer in `examples/petrinet-nd-macro-layer.zc` compiles natively.

## Repository layout

```text
Zil/                 native Lean library
Zil/Engine/          Horn-rule evaluation and relationship explanations
Zil/Horn/            first-order terms, unification, SLD resolution, and parsing
Zil/Trust/           proof-backed rules
Zil/Exchange/        snapshots and deltas
examples/lean/       progressive native examples
examples/native-cli/ CLI snapshot example
libsets/             opt-in macro libraries, selected with --lib (model-substrate, aws-model, ...)
bin/ scripts/ tools/ commands, test runners and gates (no Clojure)
spec/                language and runtime specifications
```

## Validation

Expected repository validation:

```bash
lake build
lake exe zilLeanTests
bin/zil test --profile lean
```

The Lean toolchain is pinned to `leanprover/lean4:v4.31.0`.
