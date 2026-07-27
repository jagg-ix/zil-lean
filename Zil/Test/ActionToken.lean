import Zil.ActionToken
import Zil.Parser.DeclarationProgram

open Zil.ActionToken

private def bundleId : String :=
  "sha256:" ++ String.mk (List.replicate 64 'a')

private def validRequest : Request := {
  tokenId := "acttok:1"
  taskId := "task:demo"
  agentId := "agent:a"
  moduleName := "Demo"
  baseRevision := "rev:1"
  currentRevision := "rev:1"
  scope := "src/demo"
  leaseId := "lease:1"
  contextBundleId := bundleId
  now := 120
  ttlSeconds := 60
  lease := {
    agentId := "agent:a"
    moduleName := "Demo"
    scope := "src/demo"
    baseRevision := "rev:1"
    expiresAt := 150
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

#guard validContextBundleId bundleId
#guard !validContextBundleId "sha256:abc"

#guard match issue validRequest with
  | { allowed := true, failures := #[], token := some token } =>
      token.expiresAt == 150 && token.requiredCheckpoint &&
      token.contextBundleId == bundleId
  | _ => false

#guard match issue { validRequest with currentRevision := "rev:2" } with
  | { allowed := false, failures, token := none } =>
      failures.contains .contextStale
  | _ => false

#guard match issue { validRequest with
    lease := { validRequest.lease with agentId := "agent:b" } } with
  | { allowed := false, failures, token := none } => failures.contains .leaseMismatch
  | _ => false

#guard match issue { validRequest with now := 150 } with
  | { allowed := false, failures, token := none } => failures.contains .leaseExpired
  | _ => false

#guard match issue { validRequest with ttlSeconds := 0 } with
  | { allowed := false, failures, token := none } => failures.contains .invalidTokenTtl
  | _ => false

#guard match issue { validRequest with
    rollback := { kind := "none", reference := "" } } with
  | { allowed := false, failures, token := none } => failures.contains .missingRollback
  | _ => false

#guard match issue { validRequest with evidence := {
    validRequest.evidence with
    contextComplete := false
    authorized := false
    recoveryAvailable := false
  }} with
  | { allowed := false, failures, token := none } =>
      failures == #[.contextComplete, .authorized, .recoveryAvailable]
  | _ => false

private def source : String :=
  "MODULE action.token.\n" ++
  "request:issue#action_token_request@entity:request [" ++
  "token_id=\"acttok:1\", task_id=\"task:demo\", agent_id=\"agent:a\", " ++
  "module=\"Demo\", base_revision=\"rev:1\", current_revision=\"rev:1\", " ++
  "scope=\"src/demo\", lease_id=\"lease:1\", context_bundle_id=\"" ++ bundleId ++ "\", " ++
  "now=120, ttl_seconds=60, lease_agent_id=\"agent:a\", lease_module=\"Demo\", " ++
  "lease_scope=\"src/demo\", lease_base_revision=\"rev:1\", lease_expires_at=150, " ++
  "lease_active=true, action_type=\"modify_file\", action_target=\"file:Demo.lean\", " ++
  "expected_effects=\"compile\", required_postconditions=\"file_compiles\", " ++
  "rollback_kind=\"rollback\", rollback_reference=\"git:abc\", " ++
  "context_fresh=true, context_complete=true, no_critical_conflict=true, " ++
  "authorized=true, valid_lease=true, preconditions_pass=true, " ++
  "recovery_available=true, store_integrity=true].\n"

#guard match Zil.Parser.DeclarationProgram.parseText source with
  | .ok program =>
      match fromProgram program `request.issue with
      | .ok request =>
          request.contextBundleId == bundleId &&
          match issue request with
          | { allowed := true, token := some token, .. } => token.expiresAt == 150
          | _ => false
      | .error _ => false
  | .error _ => false

run_cmd do
  match Zil.Parser.DeclarationProgram.parseText source with
  | .error error => throwError error.render
  | .ok program =>
      match fromProgram program `request.issue with
      | .error error => throwError error
      | .ok request =>
          let decision := issue request
          unless decision.allowed do throwError "valid action token request was denied"
          let report := render `request.issue decision
          unless report.startsWith "ZIL-ACTION-TOKEN\t1\n" do
            throwError "action token report header is missing"
          unless (report.splitOn "context-bundle-id\tsha256:").length > 1 do
            throwError "action token report lost context bundle binding"
