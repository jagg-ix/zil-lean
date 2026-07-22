# Lean-native ZIL rule syntax

The native frontend represents graph rules as Lean declarations that elaborate to the canonical `Zil.Rule` intermediate representation.

```lean
zil_rule schwarzschildClaimRequirement where
  variables claim requirement declaration
  premises
    declaration ⟶[formalizes] claim
    declaration ⟶[requires] requirement
  conclusion
    claim ⟶[requiresClaim] requirement
```

## Endpoint interpretation

A bare identifier denotes a rule variable:

```lean
declaration ⟶[formalizes] claim
```

A ground node is explicit:

```lean
declaration ⟶[formalizes] node(claim.schwarzschildMetric)
```

This avoids the legacy punctuation-heavy form:

```text
?declaration # formalizes @ ?claim
```

## Semantics

`zil_rule` creates a `Zil.Rule` value with:

- the declaration name as the stable rule name;
- explicit variable names;
- canonical `Zil.RelExpr` premises;
- one canonical conclusion;
- `TrustClass.graphDerived` by default.

It does not create a Lean theorem or proof term. Certified rules remain a separate later layer so graph inference cannot be mistaken for kernel proof.

## Validation

```bash
lake build
lake exe zilLeanTests
```

The validation suite checks variable order, premise count, relation names, ground-node lowering, graph trust, and binding coverage across both premises and conclusions.

The Lean toolchain remains pinned at the repository-established `v4.31.0`.
