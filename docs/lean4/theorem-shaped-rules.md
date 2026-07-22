# Theorem-shaped graph rules

The preferred Lean-facing graph syntax mirrors theorem declarations while still lowering to `Zil.Rule`:

```lean
zil_theorem_rule transferRequirement
  {claim requirement declaration : Zil.Node}
  (hFormalizes : declaration ⟶[formalizes] claim)
  (hRequires : declaration ⟶[requires] requirement)
  : claim ⟶[requiresClaim] requirement
```

Hypothesis names are documentation-level labels. The generated value remains a `.graphDerived` Horn rule and does not create a Lean theorem or proof term. Existing `zil_rule ... where` declarations remain supported.

Lean remains pinned to `leanprover/lean4:v4.31.0`.
