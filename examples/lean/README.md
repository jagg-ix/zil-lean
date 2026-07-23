# Learn ZIL through Lean examples

These examples use ZIL directly inside Lean. They do not require legacy `.zc`
files or the Clojure runtime.

Run one example with:

```bash
lake env lean examples/lean/01_FactsAndRelations.lean
```

Run the progression in order:

## 1. Facts and relations

```bash
lake env lean examples/lean/01_FactsAndRelations.lean
```

Introduces:

- ground knowledge nodes;
- native `subject ⟶[relation] object` syntax;
- `zil_fact` registration;
- inspection through `Zil.Environment`.

## 2. Theorem-shaped graph rules

```bash
lake env lean examples/lean/02_TheoremShapedRule.lean
```

Introduces:

- theorem-like binders;
- named relation hypotheses;
- Horn-rule conclusions;
- the distinction between graph rules and Lean kernel theorems.

## 3. Typed rules

```bash
lake env lean examples/lean/03_TypedRule.lean
```

Introduces:

- relation profiles;
- declaration, claim, and requirement node kinds;
- successful endpoint validation;
- an intentional category error rejected by the profile.

## 4. Multi-step inference and queries

```bash
lake env lean examples/lean/04_MultiStepQuery.lean
```

Introduces:

- multiple graph rules;
- least-fixpoint closure;
- a derivation requiring two inference steps;
- variable projection through `Zil.Query`;
- programmatic result checks.

The scenario derives:

```text
claim.exampleMetric
  ⟶[reviewableAgainst]
requirement.lorentzianMetric
```

from three asserted facts and two rules.

## 5. Knowledge across imports

Compile the knowledge module first, then the consumer:

```bash
lake env lean examples/lean/KnowledgeBase.lean
lake env lean examples/lean/05_ImportedKnowledge.lean
```

Introduces:

- persistent ZIL environment entries;
- `.olean` reconstruction;
- imported rules and facts;
- inference over imported knowledge.

## Provenance extension

After completing the numbered examples, run:

```bash
lake env lean --run examples/provenance/DerivationDAG.lean
```

That example shows the full derivation DAG, including asserted leaves, rule
bindings, trust class, and premise edges.

## Validation

```bash
lake build
lake exe zilLeanTests
```

Lean remains pinned to `leanprover/lean4:v4.31.0`.
