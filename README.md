# ZIL Lean

ZIL is a small relational language for describing named objects, the relationships between them, and rules that derive new relationships.

ZIL Lean implements that language inside Lean 4. Lean checks definitions, executable programs, theorem statements, and proofs. ZIL adds a queryable project-knowledge layer around those checked declarations.

That layer can record information such as:

```text
this declaration implements this requirement
this theorem formalizes this claim
this test validates this component
this file depends on this assumption
this task is blocked by this missing result
this change affects these downstream modules
```

The purpose is to make project structure explicit enough for people, tools, and AI agents to inspect it rather than reconstruct it repeatedly from filenames, comments, and conversation history.

## A first project example

Consider a project that contains a parser, a normalization pass, and a theorem about normalized output.

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

Lean knows the types and proofs of these declarations. ZIL records their project-level roles and relationships.

A query can now ask which declarations are affected by a parser change, which requirements have an implementation, or which components still lack validation.

## Rules derive project knowledge

A ZIL rule can propagate impact through dependencies:

```lean
zil_theorem_rule propagateImpact
  {changed dependent : Zil.Node}
  (hDepends : dependent ⟶[dependsOn] changed)
  : changed ⟶[affects] dependent
```

Given the earlier dependency fact, the graph derives:

```text
lean.Parser.parse
  ── affects ──▶
lean.Normalize.normalize
```

A second rule can continue propagation through multiple levels:

```lean
zil_theorem_rule propagateTransitiveImpact
  {source middle target : Zil.Node}
  (hFirst : source ⟶[affects] middle)
  (hSecond : target ⟶[dependsOn] middle)
  : source ⟶[affects] target
```

This turns a collection of local annotations into a reusable change-impact model.

## What ZIL adds beside Lean

Lean answers questions about terms, types, definitions, theorem statements, and proof correctness. ZIL addresses questions about the structure and intent of a whole project.

Examples include:

- Which declaration implements a requirement?
- Which theorem validates a transformation?
- Which modules are affected by a changed dependency?
- Which claims have supporting evidence?
- Which work items remain blocked?
- Which file advertises a capability without linking an implementation?
- Which derived relationship came from which facts and rule?
- Which project assumptions changed since an AI agent last worked on the repository?

These questions often span several modules and involve concepts that are useful to the project but are not themselves theorem propositions.

## Core model

ZIL uses four main structures:

- **nodes** identify declarations, requirements, claims, tests, files, tasks, evidence, or other project objects;
- **relations** connect two nodes;
- **rules** derive relations from existing relations;
- **queries** return matching nodes and variable bindings.

The basic relation shape is:

```text
subject ── relation ──▶ object
```

Examples:

```text
declaration ── implements ──▶ requirement
theorem ────── validates ────▶ component
module ─────── dependsOn ────▶ module
claim ──────── supportedBy ──▶ evidence
task ───────── blockedBy ────▶ missing result
change ─────── affects ──────▶ declaration
```

Nodes use stable names:

```text
lean.Parser.parse
lean.Normalize.normalized_sound
requirement.parseInput
component.normalizer
issue.missingTerminationProof
document.design.section4
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

Progressive examples are under:

```text
examples/lean/
```

Run them in order:

```bash
lake env lean examples/lean/01_FactsAndRelations.lean
lake env lean examples/lean/02_TheoremShapedRule.lean
lake env lean examples/lean/03_TypedRule.lean
lake env lean examples/lean/04_MultiStepQuery.lean
lake env lean examples/lean/KnowledgeBase.lean
lake env lean examples/lean/05_ImportedKnowledge.lean
```

## Facts and rules

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

The block form expresses the same structure:

```lean
zil_rule implementationCoversRequirement where
  variables declaration requirement
  premises
    declaration ⟶[implements] requirement
  conclusion
    requirement ⟶[coveredBy] declaration
```

Both forms lower to the canonical `Zil.Rule` representation used by the engine and tooling.

## Typed relation profiles

A relation profile records expected endpoint kinds:

```text
implements : declaration → requirement
validates  : theorem → component
dependsOn  : declaration → declaration
blockedBy  : task → requirement
supportedBy : claim → evidence
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

Profiles expose category errors early while preserving the canonical rule for diagnostics and tooling.

## Closure and queries

The Horn engine repeatedly applies rules until it reaches a bounded fixpoint.

```lean
import Zil

open Zil

private def parser : Term := .ground `lean.Parser.parse
private def requirement : Term := .ground `requirement.parseInput

private def facts : Array RelExpr := #[
  .mk' parser `zil.implements requirement
]

private def target : RelExpr :=
  .mk' requirement `zil.coveredBy parser

#guard Zil.Engine.entails facts #[implementationCoversRequirement] target
```

A query can retrieve the declaration covering a requirement:

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

The query engine performs variable binding, conjunctive matching, semantic deduplication, and bounded least-fixpoint evaluation.

## How ZIL helps AI-assisted projects

AI agents often lose context between sessions, branches, or repositories. Natural-language summaries help, but they are difficult to validate and easy to make stale. ZIL gives selected project facts a stable machine-readable representation inside the repository.

### 1. Preserve intent

```text
file.Parser.lean ── responsibleFor ──▶ requirement.parseInput
lean.Parser.parse ── implements ─────▶ requirement.parseInput
```

An agent can inspect why a file exists and which requirement its declarations serve before editing it.

### 2. Expose missing work

```text
requirement.totalParser ── blockedBy ──▶ issue.missingTerminationProof
issue.missingTerminationProof ── assignedTo ──▶ task.proveTermination
```

Queries can identify requirements with blockers, tasks with no owner, or declared capabilities with no implementation link.

### 3. Calculate change impact

```text
lean.Normalize.normalize ── dependsOn ──▶ lean.Parser.parse
lean.Codegen.emit ───────── dependsOn ──▶ lean.Normalize.normalize
```

Impact rules can derive which downstream components should be reviewed when `lean.Parser.parse` changes.

### 4. Guard long-running work

ZIL records knowledge revisions, contract revisions, and rollback checkpoints:

```lean
zil_checkpoint beforeParserRefactor
#zil_check_mutation token
```

A mutation check can surface stale graph state, changed contracts, theorem-intent drift, and missing rollback checkpoints before an automated edit continues.

### 5. Audit derived context

The provenance engine records the rule, variable binding, trust class, and premise node identifiers behind each derived relation. An agent can inspect how a conclusion was obtained instead of receiving only the final graph edge.

### 6. Share context between agents

Canonical snapshots and deltas allow one tool to produce project knowledge and another tool to consume the same state. This supports workflows where separate agents inspect requirements, implement code, verify proofs, and review impact.

## Persistent project knowledge

Facts, rules, profiles, contracts, checkpoints, declaration links, and certified rules use Lean environment extensions.

A module can register knowledge:

```lean
-- ProjectKnowledge.lean
import Zil

zil_fact
  node(lean.Parser.parse)
    ⟶[implements]
  node(requirement.parseInput)
```

Another module can import it:

```lean
-- Review.lean
import ProjectKnowledge

#eval Zil.Environment.facts (← Lean.getEnv)
```

Compiled `.olean` imports reconstruct the registered entries. Diamond imports are semantically deduplicated.

## Coverage linting and contracts

The coverage linter evaluates relationships across graph closure and reports conditions such as:

```text
unsupportedClaim
unpropagatedRequirement
unlinkedDeclaration
linkedWithoutClaim
```

Run it inside Lean:

```lean
#zil_lint
#zil_lint!
```

A formalization contract can record:

```text
advertised scope
abstraction level
required declarations
required graph relations
forbidden substitutions
completion state
revision history
```

Register and check contracts with:

```lean
zil_register_contract contract
#zil_contract_check
#zil_contract_check!
```

Contracts give maintainers and agents an explicit description of the expected result of a task or file.

## Trust and Lean proofs

ZIL records three trust classes:

```text
asserted
graphDerived
certified
```

- `asserted` marks directly registered project knowledge;
- `graphDerived` marks a relationship produced by a graph rule;
- `certified` associates a graph rule with a Lean proposition and proof term.

```lean
private theorem certificate : True := True.intro

private def certifiedRule : Zil.Trust.CertifiedRule :=
  .mkChecked graphRule True certificate

zil_register_certified_rule certifiedRule
```

Lean checks the proposition and proof term. ZIL records how that checked object participates in the surrounding project graph.

## Derivation provenance

The provenance engine builds an acyclic derivation graph. Each node records:

```text
semantic fact
asserted or rule-derived origin
rule name
variable binding
trust class
premise node identifiers
```

```lean
let dag :=
  Zil.Engine.Provenance.build facts rules

let some root :=
  Zil.Engine.Provenance.rootFor? dag target
  | failure

let explanation :=
  Zil.Engine.Provenance.explain dag root
```

Explanations are topologically ordered, with premise facts before the derived result.

Run the example:

```bash
lake env lean --run examples/provenance/DerivationDAG.lean
```

## Native CLI

The `zil` executable reads canonical `ZILX/1` snapshots and uses the native Lean graph engine:

```bash
lake exe zil -- summary examples/native-cli/project.zilx
lake exe zil -- closure examples/native-cli/project.zilx
lake exe zil -- export examples/native-cli/project.zilx prolog
lake exe zil -- repl examples/native-cli/project.zilx
```

Available operations:

```text
summary
closure
check
query
export souffle
export prolog
apply-delta
repl
```

## Interchange

Canonical relations and rules have deterministic text encodings:

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

These interfaces allow external analysis tools and agents to consume the same relational state used by the Lean implementation.

## Use cases

ZIL Lean can support:

- formalization maps connecting informal claims to Lean declarations;
- requirement-to-implementation traceability;
- theorem and component dependency analysis;
- change-impact queries across modules;
- evidence and source tracking;
- repository coverage checks;
- explicit task contracts for people and agents;
- multi-session AI work with revision and checkpoint guards;
- provenance explanations for derived project knowledge;
- exchange of graph state with Datalog and Prolog tooling;
- policy, architecture, and authorization models represented as relations and rules.

The same relational model can be applied to mathematics, software verification, infrastructure, scientific formalization, documentation, and other projects where relationships between artifacts matter.

## Existing `.zc` runtime

The repository also contains the earlier standalone ZIL syntax and Clojure/DataScript runtime. It supports `.zc` files, macros, import/export tooling, embedded annotations, and adapters.

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
