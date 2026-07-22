# Agent recovery guards

Mutating formalization agents should capture a `Zil.Recovery.ContextToken` before editing. The token records the current knowledge revision, optional contract revision, rollback checkpoint, and theorem-intent mismatch state.

A mutation is rejected when:

- persistent knowledge changed after context acquisition;
- the selected formalization contract revision changed;
- a critical theorem-intent mismatch is unresolved;
- no registered rollback checkpoint exists.

```lean
zil_checkpoint beforeRefactor

run_cmd do
  let env ← getEnv
  let token := Zil.Recovery.capture env (some `contract.example)
    (some `beforeRefactor)
  unless Zil.Recovery.mutationAllowed env token do
    throwError "unsafe mutation context"
```

`#zil_check_mutation token` provides a strict command-level gate.

Checkpoints are persistent environment entries, so aggregation modules can verify that imported agent actions were prepared with rollback state.

Lean remains pinned to `leanprover/lean4:v4.31.0`.
