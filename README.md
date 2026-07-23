# ZIL Lean

ZIL is a small language for describing **named things**, the **relationships**
between them, and rules that derive additional relationships.

A ZIL model can describe statements such as:

```text
this Lean declaration formalizes this claim
this claim is supported by this paper
this theorem requires this assumption
this result depends on another result
```

ZIL Lean implements this relational model inside Lean 4. Lean is a programming
and theorem-proving language: it checks definitions, executable code, theorem
statements, and proofs. ZIL adds a queryable knowledge graph alongside those
Lean declarations.

A project can therefore use Lean to check mathematics and programs, while ZIL
records how declarations, claims, evidence, requirements, and work items relate
to one another.

## A first example

A ZIL relation connects a subject to an object:

```lean
import Zil

zil_fact
  node(lean.Schwarzschild.metric)
    ⟶[formalizes]
  node(claim.schwarzschildMetric)
```

This relation says that the Lean declaration named
`lean.Schwarzschild.metric` formalizes the project claim named
`claim.schwarzschildMetric`.

A second fact can record a requirement:

```lean
zil_fact
  node(lean.Schwarzschild.metric)
    ⟶[requires]
  node(requirement.lorentzianMetric)
```

A rule can combine both facts:

```lean
zil_theorem_rule propagateRequirement
  {declaration claim requirement : Zil.Node}
  (hFormalizes : declaration ⟶[formalizes] claim)
  (hRequires : declaration ⟶[requires] requirement)
  : claim ⟶[requiresClaim] requirement
```

The rule means:

```text
when a declaration formalizes a claim
and that declaration requires something,
then the claim inherits that requirement.
```

The native Horn engine can derive:

```text
claim.schwarzschildMetric
  ── requiresClaim ──▶
requirement.lorentzianMetric
```

## Core model

ZIL uses four main structures:

- **nodes** name declarations, claims, evidence, requirements, files, or other
  project objects;
- **relations** connect two nodes;
- **rules** derive relations from other relations;
- **queries** retrieve matching nodes and variable bindings.

The basic shape is:

```text
subject ── relation ──▶ object
```

Examples:

```text
Lean declaration ── formalizes ────▶ claim
Lean declaration ── requires ───────▶ requirement
claim ───────────── supportedBy ─────▶ evidence
claim ───────────── dependsOn ───────▶ another claim
claim ───────────── requiresClaim ───▶ inherited requirement
```

Nodes use stable names:

```text
lean.Project.Module.theoremName
claim.stability
requirement.compactness
evidence.paper.section4
```

These names let the graph connect Lean declarations with concepts and artifacts
that are useful across a repository.

## How ZIL complements Lean 4

Lean theorem types express precise propositions. ZIL describes the surrounding
project knowledge.

For example, a theorem may prove a stability result while ZIL records:

```text
paper.section4 ── supports ───────▶ claim.stability
lean.Stability.main ── formalizes ▶ claim.stability
lean.Stability.main ── requires ──▶ assumption.compactness
claim.stability ── usedBy ────────▶ claim.convergence
```

This supports questions such as:

- Which declaration formalizes a claim?
- Which evidence supports a theorem family?
- Which claims inherit a changed requirement?
- Which declarations depend on an assumption?
- Which formalization targets remain incomplete?
- Which facts and rules produced a derived relationship?

ZIL keeps this information in Lean modules, so imports reconstruct the graph in
the same way they reconstruct Lean declarations.

## Quick start

The repository pins Lean to:

```text
leanprover/lean4:v4.31.0
```

Build the package and run the executable tests:

```bash
lake build
lake exe zilLeanTests
```

The progressive examples are in:

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

### Register a fact

```lean
zil_fact
  node(lean.Example.metric)
    ⟶[formalizes]
  node(claim.exampleMetric)
```

`zil_fact` stores a ground relation in a persistent Lean environment extension.
Compiled modules preserve those entries through normal imports.

### Declare a theorem-shaped rule

```lean
zil_theorem_rule claimRequirement
  {declaration claim requirement : Zil.Node}
  (hFormalizes : declaration ⟶[formalizes] claim)
  (hRequires : declaration ⟶[requires] requirement)
  : claim ⟶[requiresClaim] requirement
```

This syntax lowers to a canonical `Zil.Rule`. The theorem-like layout makes
variables, premises, and the conclusion easy to read in a Lean file.

The block form expresses the same rule:

```lean
zil_rule claimRequirement where
  variables declaration claim requirement
  premises
    declaration ⟶[formalizes] claim
    declaration ⟶[requires] requirement
  conclusion
    claim ⟶[requiresClaim] requirement
```

## Typed relation profiles

A relation profile assigns expected endpoint kinds:

```text
formalizes    : declaration → claim
requires      : declaration → requirement
requiresClaim : claim → requirement
supportedBy   : claim → evidence
```

A typed rule declares the kind of each variable:

```lean
zil_typed_rule typedClaimRequirement using Zil.Profile.research where
  variables
    declaration : declaration
    claim : claim
    requirement : requirement
  premises
    declaration ⟶[formalizes] claim
    declaration ⟶[requires] requirement
  conclusion
    claim ⟶[requiresClaim] requirement

#guard typedClaimRequirement.valid
```

Profiles make category mistakes visible while retaining the canonical rule for
diagnostics and tooling.

## Closure and queries

The Horn engine repeatedly applies rules until it reaches a bounded fixpoint.

```lean
import Zil

open Zil

private def declaration : Term := .ground `lean.Example.metric
private def claim : Term := .ground `claim.exampleMetric
private def requirement : Term := .ground `requirement.lorentzianMetric

private def facts : Array RelExpr := #[
  .mk' declaration `zil.formalizes claim,
  .mk' declaration `zil.requires requirement
]

private def target : RelExpr :=
  .mk' claim `zil.requiresClaim requirement

#guard Zil.Engine.entails facts #[claimRequirement] target
```

A query can select variable bindings:

```lean
private def requirementQuery : Zil.Query := {
  name := `requirementsOfClaim
  variables := #[`requirement]
  select := #[`requirement]
  premises := #[
    .mk'
      (.ground `claim.exampleMetric)
      `zil.requiresClaim
      (.variable `requirement)
  ]
}

private def answers :=
  Zil.Engine.solve
    (Zil.Engine.closure facts #[claimRequirement])
    requirementQuery
```

The query engine performs unification, conjunctive matching, semantic
deduplication, and bounded least-fixpoint evaluation.

## Persistent project knowledge

Facts, rules, profiles, contracts, checkpoints, declaration links, and certified
rules use Lean environment extensions.

A module can register knowledge:

```lean
-- KnowledgeBase.lean
import Zil

zil_fact
  node(lean.Example.metric)
    ⟶[formalizes]
  node(claim.exampleMetric)
```

Another module can import and query it:

```lean
-- Consumer.lean
import KnowledgeBase

#eval Zil.Environment.facts (← Lean.getEnv)
```

Diamond imports are semantically deduplicated.

## Formalization coverage and contracts

The coverage linter checks relationships across the graph closure. It reports
conditions such as:

```text
unsupportedClaim
unpropagatedRequirement
unlinkedDeclaration
linkedWithoutClaim
```

Run it from a Lean module:

```lean
#zil_lint
#zil_lint!
```

A formalization contract records expectations for a file or work item:

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

Contracts give maintainers and automated agents a shared description of what a
formalization is expected to contain.

## Agent recovery and guarded changes

ZIL records knowledge revisions, contract revisions, and rollback checkpoints.
A mutation token can be checked before an automated change:

```lean
zil_checkpoint beforeRefactor
#zil_check_mutation token
```

The check can detect stale graph state, changed contracts, theorem-intent drift,
and missing rollback checkpoints. This supports long-running or multi-session
formalization work.

## Trust and Lean proofs

ZIL records three trust classes:

```text
asserted
graphDerived
certified
```

- `asserted` marks directly registered project knowledge;
- `graphDerived` marks a relation produced by a graph rule;
- `certified` associates a graph rule with a Lean proposition and proof term.

Example:

```lean
private theorem certificate : True := True.intro

private def certifiedRule : Zil.Trust.CertifiedRule :=
  .mkChecked graphRule True certificate

zil_register_certified_rule certifiedRule
```

Lean checks the proposition and proof term. ZIL records the relation between that
checked object and the surrounding project graph.

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

Explanations are topologically ordered, with premise facts before the derived
result.

Run the example:

```bash
lake env lean --run examples/provenance/DerivationDAG.lean
```

## Native CLI

The `zil` executable reads canonical `ZILX/1` snapshots and uses the native Lean
graph engine:

```bash
lake exe zil -- summary examples/native-cli/schwarzschild.zilx
lake exe zil -- closure examples/native-cli/schwarzschild.zilx
lake exe zil -- export examples/native-cli/schwarzschild.zilx prolog
lake exe zil -- repl examples/native-cli/schwarzschild.zilx
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

See `examples/native-cli/README.md` for a complete session.

## Interchange and external tools

### Canonical codecs

```lean
Zil.Codec.encodeRelation
Zil.Codec.decodeRelation
Zil.Codec.encodeRule
Zil.Codec.decodeRule
```

The encoding preserves names, variables, premise order, conclusions, and trust.

### Snapshots and deltas

`ZILX/1` stores a revisioned snapshot:

```text
schema version
knowledge revision
profile name and version
facts
rules
```

`ZILD/1` stores an incremental update:

```text
base and target revisions
fact additions and removals
rule additions, replacements, and removals
profile changes
```

Lean and Clojure tools use the same line-oriented representation.

### Soufflé and Prolog

Export canonical graph state from Lean:

```lean
#zil_export_souffle
#zil_export_prolog
```

Or through the CLI:

```bash
lake exe zil -- export graph.zilx souffle
lake exe zil -- export graph.zilx prolog
```

These exports support external Datalog and Prolog workflows.

## Use cases

### Formalization maps

Connect papers, claims, definitions, theorems, assumptions, and implementation
files. Query which parts of an informal argument have corresponding Lean
artifacts.

### Requirement propagation

Record assumptions on declarations and derive the requirements inherited by
claims, downstream theorems, or applications.

### Evidence tracking

Link claims to papers, datasets, experiments, benchmarks, or review notes and
query which results have supporting artifacts.

### Change-impact analysis

Use dependency and requirement relations to identify graph nodes affected by a
changed assumption, declaration, or source.

### Multi-agent formalization

Store contracts, checkpoints, revisions, and mutation guards so agents can resume
work with a shared representation of scope and current graph state.

### Policy and architecture models

Represent services, resources, identities, permissions, dependencies, and
requirements using the same relation and rule engine.

## Legacy `.zc` tooling

The repository also contains the original `.zc` surface language and Clojure
runtime. It includes parsing, macros, DataScript-backed evaluation, import/export
tools, SQLite storage, and adapters for several external formats.

Examples:

```bash
clojure -M -m zil.cli examples/it-infra-minimal.zc
./bin/zil examples/it-infra-minimal.zc
```

Legacy `.zc` knowledge can be migrated to canonical `ZILX/1` snapshots for use
with the native Lean CLI.

## Repository guide

```text
Zil/                         Lean implementation
examples/lean/               progressive Lean examples
examples/provenance/         derivation DAG example
examples/native-cli/         CLI example
spec/                        language and runtime specifications
src/zil/                     Clojure runtime and adapters
lib/ and libsets/            legacy `.zc` libraries
```

## Validation

```bash
lake build
lake exe zilLeanTests
clojure -M:test
```

The Lean package remains pinned to `leanprover/lean4:v4.31.0`.
