# ZIL Lean

ZIL is a small language for describing **named things**, the **relationships**
between them, and rules that derive additional relationships.

A ZIL model can describe statements such as:

```text
this Lean declaration formalizes associativity of addition
this theorem uses the definition of a monoid
this result depends on another lemma
this claim is supported by a textbook section
```

ZIL Lean implements this relational model inside Lean 4. Lean is a programming
and theorem-proving language: it checks definitions, executable code, theorem
statements, and proofs. ZIL adds a queryable knowledge graph alongside those
Lean declarations.

A project can therefore use Lean to check mathematics and programs, while ZIL
records how definitions, lemmas, theorems, claims, assumptions, sources, and
work items relate to one another.

## A first example

A ZIL relation connects a subject to an object:

```lean
import Zil

zil_fact
  node(lean.Arithmetic.add_assoc)
    ⟶[formalizes]
  node(claim.additionAssociative)
```

This relation says that the Lean declaration named
`lean.Arithmetic.add_assoc` formalizes the mathematical claim named
`claim.additionAssociative`.

A second fact can record a dependency:

```lean
zil_fact
  node(lean.Arithmetic.add_assoc)
    ⟶[requires]
  node(requirement.binaryAddition)
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
claim.additionAssociative
  ── requiresClaim ──▶
requirement.binaryAddition
```

## Core model

ZIL uses four main structures:

- **nodes** name declarations, definitions, lemmas, theorems, claims, sources,
  requirements, files, or other project objects;
- **relations** connect two nodes;
- **rules** derive relations from other relations;
- **queries** retrieve matching nodes and variable bindings.

The basic shape is:

```text
subject ── relation ──▶ object
```

Examples:

```text
Lean declaration ── formalizes ────▶ mathematical claim
Lean theorem ─────── usesDefinition ─▶ definition
Lean theorem ─────── dependsOn ──────▶ another theorem
claim ────────────── supportedBy ─────▶ source
claim ────────────── requiresClaim ───▶ inherited requirement
```

Nodes use stable names:

```text
lean.Algebra.Group.mul_assoc
claim.multiplicationAssociative
requirement.binaryOperation
evidence.textbook.chapter2
```

These names let the graph connect Lean declarations with concepts and artifacts
that are useful across a repository.

## How ZIL complements Lean 4

Lean theorem types express precise propositions. ZIL describes the surrounding
project knowledge.

For example, Lean may contain a theorem proving associativity, while ZIL records:

```text
textbook.chapter2 ── supports ───────▶ claim.additionAssociative
lean.Arithmetic.add_assoc ── formalizes ▶ claim.additionAssociative
lean.Arithmetic.add_assoc ── requires ──▶ definition.binaryAddition
claim.additionAssociative ── usedBy ────▶ claim.naturalNumbersFormMonoid
```

This supports questions such as:

- Which declaration formalizes a mathematical claim?
- Which definitions are used by a theorem?
- Which results depend on a changed lemma?
- Which claims require a particular axiom or assumption?
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
  node(lean.Algebra.Group.mul_assoc)
    ⟶[formalizes]
  node(claim.multiplicationAssociative)
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
formalizes     : theorem → claim
usesDefinition : theorem → definition
dependsOn      : theorem → theorem
requiresClaim  : claim → requirement
supportedBy    : claim → evidence
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

private def declaration : Term :=
  .ground `lean.Arithmetic.add_assoc

private def claim : Term :=
  .ground `claim.additionAssociative

private def requirement : Term :=
  .ground `requirement.binaryAddition

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
  name := `requirementsOfAssociativity
  variables := #[`requirement]
  select := #[`requirement]
  premises := #[
    .mk'
      (.ground `claim.additionAssociative)
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
-- ArithmeticKnowledge.lean
import Zil

zil_fact
  node(lean.Arithmetic.add_assoc)
    ⟶[formalizes]
  node(claim.additionAssociative)
```

Another module can import and query it:

```lean
-- Consumer.lean
import ArithmeticKnowledge

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
result. A mathematical example may show that a theorem uses a definition, that
the definition requires an operation, and that the resulting claim inherits the
same requirement.

Run the example:

```bash
lake env lean --run examples/provenance/DerivationDAG.lean
```

## Native CLI

The `zil` executable reads canonical `ZILX/1` snapshots and uses the native Lean
graph engine:

```bash
lake exe zil -- summary path/to/arithmetic.zilx
lake exe zil -- closure path/to/arithmetic.zilx
lake exe zil -- export path/to/arithmetic.zilx prolog
lake exe zil -- repl path/to/arithmetic.zilx
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

The interactive shell uses the same canonical terms, rules, queries, and closure
engine as the Lean library.

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

`ZILX/1` stores a revisioned snapshot containing a schema version, knowledge
revision, relation profile, facts, and rules.

`ZILD/1` stores an incremental update containing base and target revisions,
fact additions and removals, rule changes, and profile changes.

The Lean and Clojure implementations use the same line-oriented exchange format.

### Logic-program export

Canonical facts and rules can be exported to Soufflé Datalog or Prolog:

```lean
#zil_export_souffle
#zil_export_prolog
```

These exports support external inspection and analysis with established logic
programming tools.

## Use cases

### Mathematical-library maps

Record how definitions, lemmas, theorems, and claims connect across a library.
Queries can identify theorems using a definition or results affected by a changed
lemma.

### Informal-to-formal traceability

Connect textbook statements, paper sections, or design notes to the Lean
declarations that formalize them.

### Assumption and axiom tracking

Propagate requirements from declarations to claims and inspect which results rely
on a selected assumption.

### Formalization planning

Represent proposed claims, required declarations, completion states, and
contracts before or during implementation.

### Multi-agent formalization

Persist project knowledge, revisions, contracts, and checkpoints so separate
agents can continue work with a shared relational state.

### Other domains

The same graph model can describe software architecture, verification targets,
policies, infrastructure, and scientific formalizations by defining suitable
node kinds and relations.

## Legacy `.zc` runtime

The repository also contains the earlier standalone ZIL surface syntax and its
Clojure/DataScript runtime. It supports `.zc` files, macros, import and export
tools, compatibility profiles, and migration into canonical `ZILX/1` snapshots.

Example:

```bash
clojure -M -m zil.cli examples/it-infra-minimal.zc
```

The native Lean examples are the recommended starting point for learning how ZIL
integrates with Lean modules and declarations.

## Repository layout

```text
Zil/                 native Lean implementation
Zil/Engine/          closure, queries, and provenance
Zil/Environment/     persistent Lean environment extensions
examples/lean/       progressive native Lean examples
examples/provenance/ derivation DAG example
examples/native-cli/ CLI examples and snapshots
src/zil/             Clojure runtime and migration tooling
spec/                language and exchange specifications
```

## Validation

```bash
lake build
lake exe zilLeanTests
clojure -M:test
```

The repository is pinned to Lean `v4.31.0`.