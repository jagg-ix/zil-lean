# Native workflow evidence

`Zil.Workflow` is the Lean model consumed by frozen workflow modules exported from the SQLite operational store.

## Evidence model

Each `ActionEvidence` records:

```text
action and agent identity
module and revision references
context freshness and completeness
conflict status
authorization and lease status
checkpoint and precondition status
recovery availability
```

The executable decision procedure is:

```lean
ActionEvidence.mayExecute : ActionEvidence → Bool
```

Generated modules use the proof-facing predicate:

```lean
MayExecute : ActionEvidence → Prop
```

A ready action can therefore carry a checked example:

```lean
example : MayExecute snapshot.actions[0]! := by
  native_decide
```

## Snapshot validity

`Snapshot.valid` checks structural evidence:

- the store snapshot is complete;
- the revision is populated;
- action identifiers are unique;
- every action was evaluated against the snapshot revision;
- every action has complete identity and revision fields.

Structural validity is separate from execution permission. A valid snapshot may contain a blocked action. `Snapshot.allMayExecute` reports whether every action is currently permitted.

## Verified export

The verified command is:

```bash
bin/zil-workflow \
  store.sqlite \
  Demo \
  generated/workflow/Demo.lean \
  Zil.Generated.WorkflowDemo \
  150
```

Equivalent Clojure invocation:

```bash
clojure -M:workflow-native \
  store.sqlite Demo generated/workflow/Demo.lean \
  Zil.Generated.WorkflowDemo 150
```

The command:

1. reads the current immutable module snapshot;
2. evaluates workflow evidence at the supplied epoch;
3. writes the Lean module atomically;
4. runs `lake env lean <output>`;
5. returns nonzero if store integrity or Lean elaboration fails.

The five-argument `export-workflow!` API remains translation-only for existing callers. Pass `{:verify-generated true}` to use the verified API directly.

## Versioned verification report

Add one optional final path to emit JSON suitable for release attestations:

```bash
bin/zil-workflow \
  store.sqlite \
  Demo \
  generated/workflow/Demo.lean \
  Zil.Generated.WorkflowDemo \
  150 \
  generated/workflow/Demo.workflow.json
```

The JSON format is:

```text
zil.workflow-verification.v0.1
```

It contains the normal export result plus:

- canonical string keys and status values;
- generated module SHA-256 in `output_sha256`;
- verification status and command metadata.

The release attestor requires `verification.status=verified` and binds `output_sha256` to a hashed release artifact.

## Validation

```bash
lake build
lake exe zilLeanTests
clojure -M:test
```
