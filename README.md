# ZIL Lean

ZIL Lean is a relational knowledge and rule layer implemented in Lean 4.
It provides a compact way to describe how declarations, claims, requirements,
evidence, dependencies, and other named objects relate to one another.

Lean remains the language used for definitions, executable programs, theorem
statements, and proofs. ZIL adds a queryable graph beside those declarations so
a project can record and inspect relationships that are broader than an
individual theorem type.

A typical ZIL relation looks like this:

```lean
node(lean.Schwarzschild.metric)
  ⟶[formalizes]
node(claim.schwarzschildMetric)
```

A rule can connect several relations:

```lean
zil_theorem_rule propagateRequirement
  {declaration claim requirement : Zil.Node}
  (hFormalizes : declaration ⟶[formalizes] claim)
  (hRequires : declaration ⟶[requires] requirement)
  : claim ⟶[requiresClaim] requirement
```

Given facts stating that a Lean declaration formalizes a claim and requires a
particular assumption, the native Horn engine derives that the claim inherits
that requirement.

This gives a Lean project two complementary structures:

- Lean declarations and proof terms express formally checked mathematics and
  programs.
- ZIL relations and graph rules express project-level knowledge about those
  declarations, their intent, dependencies, evidence, coverage, and workflow.

## What ZIL represents

The core model consists of terms, binary relations, Horn rules, and queries.

```text
subject ── relation ──▶ object
```

Examples include:

```text
Lean declaration ── formalizes ──▶ claim
Lean declaration ── requires ─────▶ requirement
claim ───────────── supportedBy ───▶ evidence
claim ───────────── dependsOn ─────▶ another claim
claim ───────────── requiresClaim ─▶ inherited requirement
```

The relation vocabulary is extensible. Versioned relation profiles can assign
expected endpoint kinds and validate how each relation is used.

ZIL nodes use stable names such as:

```text
lean.Project.Module.theoremName
claim.schwarzschildMetric
requirement.lorentzianMetric
evidence.paper.section3
```

These names allow the graph to connect formal declarations to concepts and
artifacts that may live outside a Lean theorem type.

## Quick start

The repository pins Lean at:

```text
leanprover/lean4:v4.31.0
```

Build the package and run the executable tests:

```bash
lake build
lake exe zilLeanTests
```

### Register facts

```lean
import Zil

zil_fact
  node(lean.Example.metric)
    ⟶[formalizes]
  node(claim.exampleMetric)

zil_fact
  node(lean.Example.metric)
    ⟶[requires]
  node(requirement.lorentzianMetric)
```

`zil_fact` stores ground relations in a persistent Lean environment extension.
Imported `.olean` modules reconstruct those entries, so knowledge can be
organized across a normal Lean module hierarchy.

### Declare a graph rule

The theorem-shaped frontend places variables and premises in a form familiar to
Lean users:

```lean
zil_theorem_rule claimRequirement
  {declaration claim requirement : Zil.Node}
  (hFormalizes : declaration ⟶[formalizes] claim)
  (hRequires : declaration ⟶[requires] requirement)
  : claim ⟶[requiresClaim] requirement
```

The declaration above creates a canonical `Zil.Rule`. Its trust class is
`.graphDerived`, which identifies the conclusion as a result of graph
inference.

The block-oriented frontend is also available:

```lean
zil_rule claimRequirement where
  variables declaration claim requirement
  premises
    declaration ⟶[formalizes] claim
    declaration ⟶[requires] requirement
  conclusion
    claim ⟶[requiresClaim] requirement
```

### Use typed relation profiles

Typed rules validate relation endpoints against a versioned profile:

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

A profile records relation signatures such as:

```text
formalizes    : declaration → claim
requires      : declaration → requirement
requiresClaim : claim → requirement
supportedBy   : claim → evidence
```

This catches category mistakes while preserving the underlying canonical rule
for diagnostics and tooling.

### Compute closure and run a query

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

A conjunctive query selects variable bindings from the closure:

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

The query engine supports variable binding, unification, conjunctive premises,
semantic deduplication, and bounded least-fixpoint Horn evaluation.

## How ZIL complements Lean 4

### Project intent beside theorem statements

A Lean theorem type records a precise proposition. A ZIL graph can additionally
record why the theorem exists, which informal claim it addresses, which source
supports that claim, and which assumptions or downstream results depend on it.

```text
paper.section4 ── supports ──▶ claim.stability
claim.stability ── formalizedBy ──▶ lean.Stability.main
lean.Stability.main ── requires ──▶ assumption.compactness
```

This makes the structure of a formalization visible without encoding every
project-management relation as a proposition.

### Querying across modules

Lean resolves declarations through imports and names. ZIL adds relational
queries over imported project metadata. A query can ask for:

- declarations that formalize a claim;
- claims with requirements that have not propagated;
- evidence linked to a family of theorems;
- downstream declarations affected by a changed assumption;
- formalization targets that remain incomplete;
- rules and facts contributing to a derived relationship.

### Validation of formalization coverage

The coverage linter evaluates the graph closure and reports conditions such as:

```text
unsupportedClaim
unpropagatedRequirement
unlinkedDeclaration
linkedWithoutClaim
```

Use warning or strict modes inside Lean modules:

```lean
#zil_lint
#zil_lint!
```

This supports repository-level checks where the desired property concerns the
relationship between many declarations rather than one proof goal.

### Formalization contracts

A formalization contract records the expected scope and structure of a file or
work item:

```text
advertised scope
abstraction level
required Lean declarations
required graph relations
forbidden substitutions
completion state
revision history
```

Contracts are registered and checked in Lean:

```lean
zil_register_contract contract

#zil_contract_check
#zil_contract_check!
```

They provide agents and maintainers with an explicit description of what a
formalization is expected to contain.

### Agent recovery and guarded mutation

ZIL records knowledge revisions, contract revisions, and rollback checkpoints.
A mutation token can be checked before an automated change is applied:

```lean
zil_checkpoint beforeRefactor
#zil_check_mutation token
```

The check identifies stale knowledge, changed contracts, theorem-intent
mismatches, and missing rollback checkpoints. This is useful when an agent
continues work across several sessions or stacked pull requests.

## Trust and proof integration

ZIL uses explicit trust classes:

```text
asserted
 graphDerived
 certified
```

- An asserted fact is registered directly as project knowledge.
- A graph-derived fact records the rule application that produced it.
- A certified rule is wrapped together with a Lean proposition and a
  kernel-checked proof term.

Example certified wrapper:

```lean
private theorem certificate : True := True.intro

private def certifiedRule : Zil.Trust.CertifiedRule :=
  .mkChecked graphRule True certificate

zil_register_certified_rule certifiedRule
```

This representation keeps the provenance of graph reasoning visible while
making the proof-bearing boundary explicit. Lean proof checking continues to be
performed by the Lean kernel; ZIL supplies structured knowledge about how the
project relates those checked declarations to claims and requirements.

## Provenance-rich derivation DAGs

The provenance engine builds an acyclic explanation graph for Horn closure.
Each node records:

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

The explanation is returned in topological order: asserted leaves appear before
the derived result that uses them. This supports CLI explanations, agent audits,
and graph visualization.

See:

```text
examples/provenance/DerivationDAG.lean
```

Run it with:

```bash
lake env lean --run examples/provenance/DerivationDAG.lean
```

## Native Lean CLI

The `zil` executable reads canonical `ZILX/1` snapshots and operates through the
Lean implementation of the graph engine.

```bash
lake exe zil -- summary examples/native-cli/schwarzschild.zilx
lake exe zil -- closure examples/native-cli/schwarzschild.zilx
lake exe zil -- export examples/native-cli/schwarzschild.zilx prolog
lake exe zil -- repl examples/native-cli/schwarzschild.zilx
```

Supported operations include:

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

See:

```text
examples/native-cli/README.md
```

## Persistence and interchange

### Lean environment persistence

Facts, rules, relation profiles, declaration links, contracts, checkpoints, and
certified rules use persistent Lean environment extensions. Importing a compiled
module reconstructs its ZIL entries and deduplicates repeated diamond imports.

### Canonical text codec

Relations and rules have deterministic text encodings:

```lean
Zil.Codec.encodeRelation
Zil.Codec.decodeRelation
Zil.Codec.encodeRule
Zil.Codec.decodeRule
```

These encodings preserve canonical names, variable order, premise order,
conclusions, and trust classes.

### Snapshot and delta protocols

`ZILX/1` represents a revisioned knowledge snapshot containing:

```text
schema version
knowledge revision
profile name and version
facts
rules
```

`ZILD/1` represents an incremental update containing:

```text
base and target revisions
fact additions and removals
rule additions, replacements, and removals
profile changes
```

The Lean and Clojure implementations use the same line-oriented exchange
format, enabling tools on either side to inspect or transport the same canonical
relational state.

### Logic-program export

Canonical facts and rules can be exported to Soufflé Datalog or Prolog:

```lean
#zil_export_souffle
#zil_export_prolog
```

or programmatically:

```lean
Zil.Export.exportProgram .souffle facts rules
Zil.Export.exportProgram .prolog facts rules
```

This provides a direct path from Lean-managed project knowledge to external
logic tooling.

## Use cases

### Formalization maps

Connect informal claims, paper sections, Lean declarations, assumptions, and
verification status.

```text
source equation → claim → Lean definition → theorem → dependent result
```

### Requirement propagation

Record assumptions on declarations and derive which claims inherit those
assumptions.

```text
declaration requires requirement
declaration formalizes claim
therefore claim requiresClaim requirement
```

### Change-impact analysis

Represent dependency edges and query which declarations or claims are affected
by a revised definition, source, contract, or assumption.

### Evidence tracking

Associate claims with papers, datasets, experiments, or review notes, then lint
for unsupported claims or missing formalization links.

### Multi-agent formalization

Give agents a persistent map of completed work, intended scope, active
requirements, checkpoints, and derivation provenance. Revision checks help an
agent recognize when its working context has become stale.

### Policy and authorization models

Use relation profiles and Horn rules to represent membership, inheritance,
resource relations, and derived access decisions. The graph layer is suitable
for modeling and querying such policies; Lean propositions can be added where a
kernel-checked policy theorem is required.

### Architecture and dependency knowledge

Describe services, modules, interfaces, providers, or generated artifacts as
nodes, then derive transitive dependencies and validate expected links.

## Legacy `.zc` and Clojure runtime

The repository also contains the earlier standalone ZIL surface language and
Clojure/DataScript runtime. Its tuple syntax is:

```zc
lean.Example.metric#formalizes@claim.exampleMetric.
```

Its rule syntax supports `IF`, `THEN`, conjunction, macros, queries, declaration
profiles, data import/export, and several domain libraries under `lib/` and
`libsets/`.

Run a `.zc` program with:

```bash
clojure -M -m zil.cli examples/it-infra-minimal.zc
```

Build and use the standalone Java archive with:

```bash
./bin/build-jar
./bin/zil examples/it-infra-minimal.zc
```

Legacy `.zc` knowledge can be converted into canonical snapshots for the Lean
CLI:

```bash
clojure -M:migrate input.zc output.zilx output.migration.edn
```

Strict migration produces a lossless conversion report. Audited lossy mode
records constructs whose current canonical snapshot representation is partial.
Recursive tree migration is available for repository-scale conversion.

## Repository layout

```text
Zil/                         Lean library
  Core/                      terms, relations, rules, queries
  Syntax/                    native Lean command syntax
  Profile/                   typed relation profiles
  Environment/               persistent environment extensions
  Engine/                    closure, queries, reports, provenance
  Lint/                      formalization coverage checks
  Contract/                  formalization contracts
  Recovery/                  checkpoints and mutation guards
  Codec/                     canonical text encoding
  Interop/                   snapshots and incremental deltas
  Export/                    Soufflé and Prolog output
  Trust/                     proof-carrying certified rules
  CLI/                       native Lean command-line interface

examples/native-cli/         snapshot and CLI walkthrough
examples/provenance/         derivation DAG walkthrough

src/zil/                     Clojure runtime and bridges
lib/ and libsets/            legacy `.zc` libraries
spec/                        language and runtime specifications
docs/                        design and workflow documentation
```

## Validation

Lean package:

```bash
lake build
lake exe zilLeanTests
```

Clojure runtime:

```bash
clojure -M:test
```

The Lean toolchain version remains pinned in `lean-toolchain`. The repository is
under active development; the executable tests and example modules provide the
current reference for supported behavior.
