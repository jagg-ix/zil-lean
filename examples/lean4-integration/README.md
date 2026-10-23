# ZIL ⇄ Lean4 integration examples

Graded examples showing the mechanisms by which ZIL models are used within Lean4. Each artifact in `generated/` compiles under the `zil-lean` package (Lean v4.31.0) with `lake env lean <file>`.

The artifacts in `generated/` were produced by exporters that were removed with the Clojure runtime (`spec/clojure-removal.md`); they are kept as written. `bin/zil compile` produces a native module from any of the sources that need no library.

| Example | Layer | Lean4 mechanism | Artifact |
|---|---|---|---|
| `knowledge-core.zc` | core facts + rules | native zil-lean module (`zil_fact`/`zil_rule`, kernel-elaborated); `bin/zil compile` | `generated/KnowledgeCore.lean` |
| `measurement-protocol-lts.zc` | `LTS_ATOM` + `POLICY` | dependency-free state-machine module | `generated/MeasurementProtocol.lean` |
| `access-control.zc` | RBAC/DAC macro layer (stratified negation) | `bin/zil compile ... --lib libsets/rbac-dac` | `generated/AccessControl.lean` |
| `category-theory-spec.zc` | category-theory layer over the theorem layer | theorem bridge → Lean; the `category-theory` row of the macro matrix | `generated/CategoryTheoryBridge.lean` |
| `AnnotatedTheorem.lean` | embedded annotations | Lean source → canonical ZIL facts (scanner removed) | `generated/annotated-scan.zc` |

The category-theory example encodes the free/forgetful adjunction between Set
and Grp; the layer expands each construct into proof obligations, and the
operator summary reports the left triangle identity PROVED (its full witness
chain names Mathlib declarations) and the right triangle WEAK (the open
target). Witness tokens are bookkeeping — the Lean kernel remains the sole
proof authority.

Known limits:

- A relation literally named `version` collides with zil-lean's grammar
  (see the bitemporal layer); prefer prefixed relation names.
- A program with negation must be stratifiable; compose it with a scoped libset,
  not all of `lib/` at once.
