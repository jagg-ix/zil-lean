# Formalization contracts

A `Zil.Contract.FileContract` records the scope a module advertises, its abstraction level, required Lean declarations, required graph relations, forbidden substitutes, revision, and completion status.

Contracts persist through `.olean` imports. Revisions for the same contract name are retained so validation can reject removal of previously required objects.

```lean
private def contract : Zil.Contract.FileContract :=
  { name := `contract.example
    revision := 1
    advertisedScope := "Example domain"
    abstractionLevel := "full theorem"
    requiredDeclarations := #[`Example.mainTheorem]
    status := .complete }

zil_register_contract contract
#zil_contract_check!
```

Blocking diagnostics cover missing declarations, missing required relations, forbidden substitute declarations, weakened scope, and `complete` status while blocking issues remain.

Lean remains pinned to `leanprover/lean4:v4.31.0`.
