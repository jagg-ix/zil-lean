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
lake env lean examples/lean/KnowledgeBase.lean
lake env lean examples/lean/05_ImportedKnowledge.lean
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

The explanation API builds a directed graph whose entries record the project fact, source, rule name, variable binding, trust level, and input relation identifiers:

```lean
let dag :=
  Zil.Engine.Provenance.build facts rules

let some root :=
  Zil.Engine.Provenance.rootFor? dag target
  | failure

let explanation :=
  Zil.Engine.Provenance.explain dag root
```

The public identifier remains visible in the code sample so the example matches the current API. The surrounding documentation uses “explanation” to describe the feature.

## Native CLI and data exchange

The native `zil` executable reads standard `ZILX/1` snapshots:

```bash
lake exe zil -- summary examples/native-cli/project.zilx
lake exe zil -- closure examples/native-cli/project.zilx
lake exe zil -- export examples/native-cli/project.zilx prolog
lake exe zil -- repl examples/native-cli/project.zilx
```

Supported operations include `summary`, `closure`, `check`, `query`, `export souffle`, `export prolog`, `apply-delta`, and `repl`.

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

## Existing `.zc` runtime

The repository also contains the standalone ZIL syntax and Clojure/DataScript runtime. It supports `.zc` files, macros, import/export tools, embedded annotations, and adapters.

```bash
clojure -M -m zil.cli examples/it-infra-minimal.zc
```

The standard exchange layer connects that runtime with the native Lean representation.

## Repository layout

```text
Zil/                 native Lean library
Zil/Engine/          Horn-rule evaluation and relationship explanations
Zil/Trust/           proof-backed rules
Zil/Exchange/        snapshots and deltas
examples/lean/       progressive native examples
examples/native-cli/ CLI snapshot example
src/zil/             Clojure runtime and tools
spec/                language and runtime specifications
```

## Validation

Expected repository validation:

```bash
lake build
lake exe zilLeanTests
clojure -M:test
```

The Lean toolchain is pinned to `leanprover/lean4:v4.31.0`.
