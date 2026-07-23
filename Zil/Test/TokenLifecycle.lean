import Zil.TokenLifecycle
import Zil.Parser.DeclarationProgram

open Zil.ActionToken
open Zil.TokenLifecycle

private def bundleId : String :=
  "sha256:" ++ String.mk (List.replicate 64 'a')

private def digest (char : Char) : String :=
  "sha256:" ++ String.mk (List.replicate 64 char)

private def request : Zil.ActionToken.Request := {
  tokenId := "acttok:1"
  taskId := "task:demo"
  agentId := "agent:a"
  moduleName := "Demo"
  baseRevision := "rev:1"
  currentRevision := "rev:1"
  scope := "src/demo"
  leaseId := "lease:1"
  contextBundleId := bundleId
  now := 100
  ttlSeconds := 100
  lease := {
    agentId := "agent:a"
    moduleName := "Demo"
    scope := "src/demo"
    baseRevision := "rev:1"
    expiresAt := 180
    active := true
  }
  action := {
    actionType := "modify_file"
    target := "file:Demo.lean"
    expectedEffects := #["compile"]
    requiredPostconditions := #["file_compiles"]
  }
  rollback := { kind := "rollback", reference := "git:abc" }
  evidence := {
    contextFresh := true
    contextComplete := true
    noCriticalConflict := true
    authorized := true
    validLease := true
    preconditionsPass := true
    recoveryAvailable := true
    storeIntegrity := true
  }
}

private def issued : Except String State :=
  initialize request (Zil.ActionToken.issue request)

private def checkpointRequest : CheckpointRequest := {
  checkpointId := "checkpoint:1"
  agentId := "agent:a"
  currentRevision := "rev:1"
  snapshotDigest := digest 'b'
  now := 120
}

private def executionRequest : ExecutionRequest := {
  actionId := "action:1"
  checkpointId := "checkpoint:1"
  currentRevision := "rev:1"
  now := 130
  storeIntegrity := true
  lease := request.lease
  outputs := #[{ artifact := "file:Demo.lean", hash := digest 'c' }]
}

#guard match issued with
  | .ok state =>
      match bindCheckpoint state checkpointRequest with
      | .ok checkpointed =>
          checkpointed.status == .checkpointed &&
          match execute checkpointed executionRequest with
          | .ok consumed =>
              consumed.status == .consumed && consumed.execution.isSome
          | .error _ => false
      | .error _ => false
  | .error _ => false

#guard match issued with
  | .ok state =>
      match bindCheckpoint state { checkpointRequest with currentRevision := "rev:2" } with
      | .error .contextStale => true
      | _ => false
  | .error _ => false

#guard match issued with
  | .ok state =>
      match bindCheckpoint state { checkpointRequest with now := 180 } with
      | .error .tokenExpired => true
      | _ => false
  | .error _ => false

#guard match issued with
  | .ok state =>
      match bindCheckpoint state { checkpointRequest with snapshotDigest := "sha256:bad" } with
      | .error .invalidSnapshotDigest => true
      | _ => false
  | .error _ => false

#guard match issued with
  | .ok state =>
      match bindCheckpoint state checkpointRequest with
      | .ok checkpointed =>
          match execute checkpointed { executionRequest with checkpointId := "checkpoint:2" } with
          | .error .checkpointMismatch => true
          | _ => false
      | .error _ => false
  | .error _ => false

#guard match issued with
  | .ok state =>
      match bindCheckpoint state checkpointRequest with
      | .ok checkpointed =>
          let invalidOutput : ObservedOutput := {
            artifact := "file:Demo.lean"
            hash := "sha256:bad"
          }
          match execute checkpointed { executionRequest with outputs := #[invalidOutput] } with
          | .error .invalidObservedOutput => true
          | _ => false
      | .error _ => false
  | .error _ => false

#guard match issued with
  | .ok state =>
      match bindCheckpoint state checkpointRequest with
      | .ok checkpointed =>
          match execute checkpointed executionRequest with
          | .ok consumed =>
              match execute consumed executionRequest with
              | .error .tokenNotCheckpointed => true
              | _ => false
          | .error _ => false
      | .error _ => false
  | .error _ => false

private def source : String :=
  "MODULE token.lifecycle.\n" ++
  "request:issue#action_token_request@entity:request [" ++
  "token_id=\"acttok:1\", task_id=\"task:demo\", agent_id=\"agent:a\", " ++
  "module=\"Demo\", base_revision=\"rev:1\", current_revision=\"rev:1\", " ++
  "scope=\"src/demo\", lease_id=\"lease:1\", context_bundle_id=\"" ++ bundleId ++ "\", " ++
  "now=100, ttl_seconds=100, lease_agent_id=\"agent:a\", lease_module=\"Demo\", " ++
  "lease_scope=\"src/demo\", lease_base_revision=\"rev:1\", lease_expires_at=180, " ++
  "lease_active=true, action_type=\"modify_file\", action_target=\"file:Demo.lean\", " ++
  "expected_effects=\"compile\", required_postconditions=\"file_compiles\", " ++
  "rollback_kind=\"rollback\", rollback_reference=\"git:abc\", " ++
  "context_fresh=true, context_complete=true, no_critical_conflict=true, authorized=true, " ++
  "valid_lease=true, preconditions_pass=true, recovery_available=true, store_integrity=true].\n" ++
  "request:issue#checkpoint_event@checkpoint:1 [checkpoint_id=\"checkpoint:1\", " ++
  "agent_id=\"agent:a\", current_revision=\"rev:1\", snapshot_digest=\"" ++ digest 'b' ++ "\", now=120].\n" ++
  "request:issue#execution_event@action:1 [action_id=\"action:1\", " ++
  "checkpoint_id=\"checkpoint:1\", current_revision=\"rev:1\", now=130, " ++
  "store_integrity=true, lease_agent_id=\"agent:a\", lease_module=\"Demo\", " ++
  "lease_scope=\"src/demo\", lease_base_revision=\"rev:1\", lease_expires_at=180, " ++
  "lease_active=true, observed_outputs=\"file:Demo.lean=" ++ digest 'c' ++ "\"].\n"

#guard match Zil.Parser.DeclarationProgram.parseText source with
  | .ok program =>
      match auditProgram program `request.issue with
      | .ok audit =>
          audit.ok &&
          match audit.state with
          | some state => state.status == .consumed
          | none => false
      | .error _ => false
  | .error _ => false

run_cmd do
  match Zil.Parser.DeclarationProgram.parseText source with
  | .error error => throwError error.render
  | .ok program =>
      match auditProgram program `request.issue with
      | .error error => throwError error
      | .ok audit =>
          unless audit.ok do throwError "valid token lifecycle was rejected"
          let report := render audit
          unless report.startsWith "ZIL-TOKEN-LIFECYCLE\t1\n" do
            throwError "token lifecycle report header is missing"
          unless (report.splitOn "token-status\tconsumed").length > 1 do
            throwError "token lifecycle report lost consumed status"
