# ZIL ⇄ Lean4 integration examples

Graded, runnable examples showing every mechanism by which ZIL models are used
within Lean4. Each generated artifact in `generated/` compiles under the
`zil-lean` package (Lean v4.31.0) with `lake env lean <file>`; regeneration
commands are in each source header.

| Example | Layer | Lean4 mechanism | Generated artifact |
|---|---|---|---|
| `knowledge-core.zc` | core facts + rules | `export-snapshot` → native zil-lean module (`zil_fact`/`zil_rule`, kernel-elaborated) | `generated/KnowledgeCore.lean` |
| `measurement-protocol-lts.zc` | `LTS_ATOM` + `POLICY` | `export-lean` → dependency-free state-machine module | `generated/MeasurementProtocol.lean` |
| `access-control.zc` | RBAC/DAC macro layer (stratified negation) | preprocess with `libsets/rbac-dac` → `export-snapshot` | `generated/AccessControl.lean` |
| `category-theory-spec.zc` | category-theory layer over the theorem layer | `theorem-dsl-ci` → theorem bridge → Lean | `generated/CategoryTheoryBridge.lean` |
| `AnnotatedTheorem.lean` | embedded annotations | `embedded-scan` (Lean source → canonical ZIL facts) | `generated/annotated-scan.zc` |

The category-theory example encodes the free/forgetful adjunction between Set
and Grp; the layer expands each construct into proof obligations, and the
operator summary reports the left triangle identity PROVED (its full witness
chain names Mathlib declarations) and the right triangle WEAK (the open
target). Witness tokens are bookkeeping — the Lean kernel remains the sole
proof authority.

Known layer/exporter limits (as of snapshot format v0.2):

- Rules with multiple heads (the theorem layer's status rules) are not yet
  lowered by `export-snapshot`; the theorem bridge is the supported route.
- Snapshot export requires a stratifiable program; preprocess against a scoped
  libset, not all of `lib/` at once.
- A relation literally named `version` collides with zil-lean's grammar
  (see the bitemporal layer); prefer prefixed relation names.
- `export-lean` embeds the source path in a block comment; paths containing
  `/-` produce an unterminated nested comment. Generate from a path without
  that substring.
