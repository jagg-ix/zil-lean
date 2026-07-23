# ZIL Lean

ZIL is a small relational language for describing named objects, the relationships between them, and rules that derive new relationships.

A relation has three parts:

```text
subject ── relation ──▶ object
```

For example:

```text
lean.Parser.parse ── implements ──▶ requirement.parseInput
```

ZIL Lean implements this model inside Lean 4. Lean checks definitions, executable programs, theorem statements, and proofs. ZIL adds a queryable project-knowledge layer around those checked declarations.

That layer can record information such as:

```text
this declaration implements this requirement
this theorem validates this component
this module depends on this declaration
this task is blocked by this missing result
this change affects these downstream modules
```

The result is repository context that people, tools, and AI agents can inspect directly instead of reconstructing it repeatedly from filenames, comments, issue descriptions, and conversation history.

## Relation tuples: from Zanzibar to ZIL

ZIL's tuple notation and relational model are influenced by Zanzibar-style authorization data and its Datalog-like treatment of relations.

The Zanzibar paper represents an authorization tuple as:

```text
object#relation@user
```

Table 1 gives examples such as:

```text
doc:readme#owner@10
group:eng#member@11
doc:readme#viewer@group:eng#member
doc:readme#parent@folder:A#...
```

Their meanings are:

```text
user 10 is an owner of doc:readme
user 11 is a member of group:eng
members of group:eng are viewers of doc:readme
doc:readme is in folder:A
```

The third example is especially important. Its subject is a **userset** rather than one user:

```text
group:eng#member
```

It denotes the set of users related to `group:eng` by `member`. This lets one relation refer to another relation and supports nested groups, inherited permissions, and rule-based authorization.

ZIL retains the same compact relational shape:

```text
object#relation@subject
```

A Zanzibar-style policy fact can therefore be written in standalone ZIL syntax as:

```zc
doc:readme#owner@user:10.
group:eng#member@user:11.
doc:readme#viewer@group:eng#member.
doc:readme#parent@folder:A.
```

Inside Lean, the same kind of relation is represented with native ZIL syntax:

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
```

The notation is adapted to Lean, while the model remains a relation between named terms.

### From authorization tuples to general project knowledge

Zanzibar applies relation tuples to users, groups, objects, and permissions. ZIL applies the same relational pattern to a broader project graph:

```text
document ── viewer ─────▶ group
module ───── dependsOn ──▶ module
declaration ─ implements ▶ requirement
theorem ───── validates ──▶ component
task ──────── blockedBy ──▶ issue
```

This is a generalization of the data model, not a claim that ZIL reproduces Zanzibar's distributed authorization service. Zanzibar contributes the tuple-oriented authorization pattern; ZIL Lean uses relations and Horn rules to organize and query repository knowledge alongside Lean code.

### Datalog-style derivation

A relation database becomes more useful when rules derive new relations from existing ones. For authorization, a rule might express:

```text
if a user is a member of a group
and that group can view a document,
then the user can view the document
```

In ZIL Lean, a corresponding Horn-style rule can be written as:

```lean
zil_theorem_rule groupViewer
  {document group user : Zil.Node}
  (hViewer : document ⟶[viewer] group)
  (hMember : group ⟶[member] user)
  : document ⟶[viewer] user
```

Given:

```text
doc.readme ── viewer ──▶ group.engineering
group.engineering ── member ──▶ user.u11
```

closure derives:

```text
doc.readme ── viewer ──▶ user.u11
```

The same rule structure can represent project reasoning rather than access control.

## A project example

Consider a project containing a parser, a normalization pass, and a theorem about normalized output.

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

These facts form a small knowledge graph:

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

Lean knows the types, definitions, and proofs of these declarations. ZIL records their project roles and relationships.

A query can now ask:

- which declaration implements `requirement.parseInput`;
- which components depend on the parser;
- which transformations have a validation theorem;
- which downstream declarations should be reviewed after a change.

## Rules derive project knowledge

A rule can propagate direct change impact:

```lean
zil_theorem_rule propagateImpact
  {changed dependent : Zil.Node}
  (hDepends : dependent ⟶[dependsOn] changed)
  : changed ⟶[affects] dependent
```

From the parser dependency, the engine derives:

```text
lean.Parser.parse
  ── affects ──▶
lean.Normalize.normalize
```

A second rule can propagate impact through several levels:

```lean
zil_theorem_rule propagateTransitiveImpact
  {source middle target : Zil.Node}
  (hFirst : source ⟶[affects] middle)
  (hSecond : target ⟶[dependsOn] middle)
  : source ⟶[affects] target
```

Local dependency annotations can therefore support a repository-wide impact query.

## What ZIL adds beside Lean

Lean answers questions about terms, types, definitions, theorem statements, computation, and proof correctness. ZIL represents relationships concerning the purpose and organization of the whole project.

Examples include:

- Which declaration implements a requirement?
- Which theorem validates a transformation?
- Which modules are affected by a changed dependency?
- Which claims have supporting evidence?
- Which work items remain blocked?
- Which file advertises a capability without an implementation link?
- Which facts and rules produced a derived relationship?
- Which project assumptions changed since an AI agent last worked on the repository?

These relationships may span many modules and may connect Lean declarations to requirements, documents, issues, tests, agents, or external evidence.

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
agent.formalization
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

Register a ground fact:

```lean
zil_fact
  node(lean.Parser.parse)
    ⟶[implements]
  node(requirement.parseInput)
```

Declare a theorem-shaped graph rule:

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

Both forms lower to the canonical `Zil.Rule` representation used by the engine and tooling.

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

The engine performs variable binding, conjunctive matching, semantic deduplication, and bounded least-fixpoint evaluation.

## Typed relation profiles

A relation profile records expected endpoint kinds:

```text
implements  : declaration → requirement
validates   : theorem → component
dependsOn   : declaration → declaration
blockedBy   : task → requirement
supportedBy : claim → evidence
member      : group → user
viewer      : document → user-or-group
```

A typed rule declares the kind of each variable:

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

Profiles make category errors visible while preserving the canonical rule for diagnostics and tooling.

## How ZIL helps AI-assisted projects

AI agents can lose project context between sessions, branches, or repositories. ZIL gives selected project facts a persistent machine-readable form that can be queried and checked.

### Preserve intent

```text
file.Parser.lean ── responsibleFor ──▶ requirement.parseInput
lean.Parser.parse ── implements ─────▶ requirement.parseInput
```

An agent can inspect why a file exists and which requirement its declarations serve before editing it.

### Expose missing work

```text
requirement.totalParser ── blockedBy ──▶ issue.missingTerminationProof
issue.missingTerminationProof ── assignedTo ──▶ task.proveTermination
```

Queries can find requirements with blockers, tasks without owners, or advertised capabilities without implementation links.

### Calculate change impact

```text
lean.Normalize.normalize ── dependsOn ──▶ lean.Parser.parse
lean.Codegen.emit ───────── dependsOn ──▶ lean.Normalize.normalize
```

Impact rules derive the downstream components requiring review when `lean.Parser.parse` changes.

### Guard long-running work

```lean
zil_checkpoint beforeParserRefactor
#zil_check_mutation token
```

Mutation checks can surface changed contracts, stale graph revisions, theorem-intent drift, and missing rollback checkpoints before an automated edit continues.

### Audit derived context

The provenance engine records the rule, variable binding, trust class, and premise node identifiers behind each derived relation. An agent can inspect how a conclusion was obtained rather than receiving only the final edge.

### Share context between agents

Canonical snapshots and deltas allow separate agents to exchange the same project graph. One agent may inspect requirements, another implement code, another verify proofs, and another review impact while sharing stable relation names and revisions.

Authorization-style relations can also control an agent workflow:

```text
repo.zilLean ── editor ──▶ group.implementers
group.implementers ── member ──▶ agent.codegen
repo.zilLean ── reviewer ──▶ agent.verifier
```

The same tuple model can describe both project context and role-based access to project operations.

## Persistence, linting, and contracts

Facts, rules, profiles, contracts, checkpoints, declaration links, and certified rules use Lean environment extensions. Compiled `.olean` imports reconstruct registered entries and semantically deduplicate diamond imports.

The coverage linter evaluates relations across graph closure:

```lean
#zil_lint
#zil_lint!
```

A formalization contract can record required declarations, required graph relations, advertised scope, completion state, and revision history:

```lean
zil_register_contract contract
#zil_contract_check
#zil_contract_check!
```

Contracts give maintainers and agents a shared machine-readable description of the expected result of a task or file.

## Trust and provenance

ZIL records three trust classes:

```text
asserted
graphDerived
certified
```

- `asserted` marks directly registered project knowledge;
- `graphDerived` marks a relation produced by a graph rule;
- `certified` associates a graph rule with a Lean proposition and proof term.

```lean
private theorem certificate : True := True.intro

private def certifiedRule : Zil.Trust.CertifiedRule :=
  .mkChecked graphRule True certificate

zil_register_certified_rule certifiedRule
```

Lean checks the proposition and proof term. ZIL records how the checked object participates in the surrounding graph.

The provenance engine builds an acyclic derivation graph whose nodes record the semantic fact, origin, rule name, variable binding, trust class, and premise identifiers:

```lean
let dag :=
  Zil.Engine.Provenance.build facts rules

let some root :=
  Zil.Engine.Provenance.rootFor? dag target
  | failure

let explanation :=
  Zil.Engine.Provenance.explain dag root
```

## Native CLI and interchange

The native `zil` executable reads canonical `ZILX/1` snapshots:

```bash
lake exe zil -- summary examples/native-cli/project.zilx
lake exe zil -- closure examples/native-cli/project.zilx
lake exe zil -- export examples/native-cli/project.zilx prolog
lake exe zil -- repl examples/native-cli/project.zilx
```

Supported operations include `summary`, `closure`, `check`, `query`, `export souffle`, `export prolog`, `apply-delta`, and `repl`.

Canonical relations and rules have deterministic codecs:

```lean
Zil.Codec.encodeRelation
Zil.Codec.decodeRelation
Zil.Codec.encodeRule
Zil.Codec.decodeRule
```

`ZILX/1` stores revisioned snapshots. `ZILD/1` stores incremental updates with base and target revisions, fact changes, rule changes, and profile changes.

Canonical facts and rules can be exported to Soufflé Datalog or Prolog:

```lean
#zil_export_souffle
#zil_export_prolog
```

These interfaces let external analysis tools and agents consume the same relational state used by the Lean implementation.

## Use cases

ZIL Lean can support:

- Zanzibar-style authorization and group-membership models;
- formalization maps connecting informal claims to Lean declarations;
- requirement-to-implementation traceability;
- theorem and component dependency analysis;
- change-impact queries across modules;
- evidence and source tracking;
- repository coverage checks;
- explicit task contracts for people and agents;
- multi-session AI work with revision and checkpoint guards;
- provenance explanations for derived project knowledge;
- exchange of graph state with Datalog and Prolog tooling.

## Existing `.zc` runtime

The repository also contains the standalone ZIL syntax and Clojure/DataScript runtime. It supports `.zc` files, macros, import/export tooling, embedded annotations, and adapters.

```bash
clojure -M -m zil.cli examples/it-infra-minimal.zc
```

The canonical exchange layer connects that runtime with the native Lean representation.

## Repository layout

```text
Zil/                 native Lean library
Zil/Engine/          Horn evaluation and provenance
Zil/Trust/           certified graph rules
Zil/Exchange/        snapshots and deltas
examples/lean/       progressive native examples
examples/provenance/ derivation DAG example
examples/native-cli/ CLI snapshot example
src/zil/             Clojure runtime and tooling
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
