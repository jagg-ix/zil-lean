# Persistent Lean knowledge environment

ZIL facts, graph rules, relation profiles, and declaration links can be stored in a Lean persistent environment extension. Entries registered in one module are exported in its `.olean` and reconstructed by importing modules.

The established toolchain remains `leanprover/lean4:v4.31.0`.

## Register knowledge

```lean
import Zil

zil_rule claimRequirements where
  variables declaration claim requirement
  premises
    declaration ⟶[formalizes] claim
    declaration ⟶[requires] requirement
  conclusion
    claim ⟶[requiresClaim] requirement

zil_register_rule claimRequirements
zil_register_profile Zil.Profile.research

zil_fact
  node(lean.Example.theoremName)
    ⟶[formalizes]
  node(claim.example)

zil_link Example.theoremName with
  node(lean.Example.theoremName)
    ⟶[formalizes]
  node(claim.example)
```

`zil_fact` and `zil_link` require ground `node(...)` endpoints. Variables belong in rules and queries, not persistent data.

## Read imported knowledge

```lean
run_cmd do
  let env ← getEnv
  let facts := Zil.Environment.facts env
  let rules := Zil.Environment.rules env
  let profiles := Zil.Environment.profiles env
```

Available predicates include:

```lean
Zil.Environment.containsFact
Zil.Environment.containsRule
Zil.Environment.containsProfile
Zil.Environment.linksForDeclaration
```

## Import semantics

The extension uses semantic deduplication:

- facts ignore source-location differences;
- rules are unique by canonical rule name;
- profiles are unique by name and version;
- declaration links are unique by declaration name and semantic relation.

This prevents a diamond import from multiplying the same entries.

## Validation fixtures

`Zil/Test/Environment/A.lean` registers knowledge. `B.lean` imports A and asserts that all entry kinds were reconstructed. `Left.lean` and `Right.lean` both import A; `Diamond.lean` imports both and asserts that entries remain unique.

Run:

```bash
lake build
lake exe zilLeanTests
```

No network or mutable external database is consulted during Lean elaboration.