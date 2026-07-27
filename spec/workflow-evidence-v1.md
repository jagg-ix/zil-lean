# ZIL workflow evidence v1

## Action evidence

```lean
structure ActionEvidence where
  actionId : String
  agentId : String
  moduleName : String
  baseRevision : String
  currentRevision : String
  contextFresh : Bool
  contextComplete : Bool
  noConflict : Bool
  authorized : Bool
  validLease : Bool
  checkpointExists : Bool
  preconditionsPass : Bool
  recoveryAvailable : Bool
```

`ActionEvidence.mayExecute` is true exactly when:

- every identity and revision field is populated;
- the context is fresh, complete, and conflict-free;
- authorization and lease evidence pass;
- checkpoint, preconditions, and recovery evidence pass.

`MayExecute action` is the proposition `action.mayExecute = true`.

## Snapshot

```lean
structure Snapshot where
  revision : String
  complete : Bool
  actions : List ActionEvidence
```

`Snapshot.valid` requires:

```text
complete = true
revision is nonempty
action IDs are unique
every currentRevision equals snapshot.revision
every action identity is complete
```

`Snapshot.valid` does not imply `Snapshot.allMayExecute`.

## Export verification

A verified export report contains:

```clojure
{:ok true
 :module "Demo"
 :revision "rev:..."
 :complete true
 :action_count 1
 :as_of 150
 :output "generated/workflow/Demo.lean"
 :namespace "Zil.Generated.WorkflowDemo"
 :verification
 {:status :verified
  :command ["lake" "env" "lean" "..."]}}
```

Verification states are:

```text
:verified generated Lean elaborated successfully
:failed   Lean elaboration returned nonzero
:skipped  verification was explicitly disabled
```

The verified command fails when the store snapshot is incomplete or the generated Lean module does not elaborate.
