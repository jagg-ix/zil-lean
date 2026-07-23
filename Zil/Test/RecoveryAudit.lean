import Zil.Parser.DeclarationProgram
import Zil.RecoveryAudit

open Zil.RecoveryAudit

private def bundleId : String :=
  "sha256:" ++ String.mk (List.replicate 64 'a')

private def digest (char : Char) : String :=
  "sha256:" ++ String.mk (List.replicate 64 char)

private def lifecycleSource (includeExecution : Bool := true) : String :=
  "MODULE recovery.audit.\n" ++
  "request:issue#action_token_request@entity:request [" ++
  "token_id=\"acttok:1\", task_id=\"task:demo\", agent_id=\"agent:a\", " ++
  "module=\"Demo\", base_revision=\"rev:1\", current_revision=\"rev:1\", " ++
  "scope=\"src/demo\", lease_id=\"lease:1\", context_bundle_id=\"" ++ bundleId ++ "\", " ++
  "now=100, ttl_seconds=100, lease_agent_id=\"agent:a\", lease_module=\"Demo\", " ++
  "lease_scope=\"src/demo\", lease_base_revision=\"rev:1\", lease_expires_at=180, " ++
  "lease_active=true, action_type=\"modify_file\", action_target=\"file:Demo.lean\", " ++
  "expected_effects=\"compile|record_artifact\", " ++
  "required_postconditions=\"file_compiles|artifact_recorded\", " ++
  "rollback_kind=\"rollback\", rollback_reference=\"git:abc\", " ++
  "context_fresh=true, context_complete=true, no_critical_conflict=true, authorized=true, " ++
  "valid_lease=true, preconditions_pass=true, recovery_available=true, store_integrity=true].\n" ++
  "request:issue#checkpoint_event@checkpoint:1 [checkpoint_id=\"checkpoint:1\", " ++
  "agent_id=\"agent:a\", current_revision=\"rev:1\", snapshot_digest=\"" ++ digest 'b' ++ "\", now=120].\n" ++
  (if includeExecution then
    "request:issue#execution_event@action:1 [action_id=\"action:1\", " ++
    "checkpoint_id=\"checkpoint:1\", current_revision=\"rev:1\", now=130, " ++
    "store_integrity=true, lease_agent_id=\"agent:a\", lease_module=\"Demo\", " ++
    "lease_scope=\"src/demo\", lease_base_revision=\"rev:1\", lease_expires_at=180, " ++
    "lease_active=true, observed_outputs=\"file:Demo.lean=" ++ digest 'c' ++ "\"].\n"
   else "")

private def postcondition
    (name : String)
    (passed : Bool)
    (evidence : String) : String :=
  "request:issue#postcondition_event@post:" ++ name ++
  " [passed=" ++ (if passed then "true" else "false") ++
  ", evidence=\"" ++ evidence ++ "\"].\n"

private def recovery
    (kind reference : String)
    (completed : Bool)
    (evidence : String) : String :=
  "request:issue#recovery_event@recovery:1 [kind=\"" ++ kind ++
  "\", reference=\"" ++ reference ++
  "\", completed=" ++ (if completed then "true" else "false") ++
  ", evidence=\"" ++ evidence ++ "\"].\n"

private def parseAudit (source : String) : Except String Audit := do
  let program ← match Zil.Parser.DeclarationProgram.parseText source with
    | .ok value => pure value
    | .error error => throw error.render
  Zil.RecoveryAudit.auditProgram program `request.issue

private def passingPostconditions : String :=
  postcondition "file_compiles" true (digest 'd') ++
  postcondition "artifact_recorded" true (digest 'e')

private def verifiedSource : String :=
  lifecycleSource ++ passingPostconditions

#guard match parseAudit verifiedSource with
  | .ok audit =>
      audit.outcome == .verified && audit.safe && audit.actionVerified &&
      audit.missing.isEmpty && audit.failed.isEmpty && audit.duplicates.isEmpty
  | .error _ => false

private def missingSource : String :=
  lifecycleSource ++ postcondition "file_compiles" true (digest 'd')

#guard match parseAudit missingSource with
  | .ok audit =>
      audit.outcome == .recoveryRequired && !audit.safe &&
      audit.missing.contains "artifact_recorded"
  | .error _ => false

private def recoveredSource : String :=
  lifecycleSource ++
  postcondition "file_compiles" true (digest 'd') ++
  postcondition "artifact_recorded" false (digest 'e') ++
  recovery "rollback" "git:abc" true (digest 'f')

#guard match parseAudit recoveredSource with
  | .ok audit =>
      audit.outcome == .recovered && audit.safe && !audit.actionVerified &&
      audit.failed.contains "artifact_recorded"
  | .error _ => false

private def failedRecoverySource : String :=
  lifecycleSource ++
  postcondition "file_compiles" true (digest 'd') ++
  postcondition "artifact_recorded" false (digest 'e') ++
  recovery "compensation" "git:wrong" true (digest 'f')

#guard match parseAudit failedRecoverySource with
  | .ok audit =>
      audit.outcome == .recoveryFailed && !audit.safe &&
      audit.recoveryIssues.contains "recovery-kind-mismatch" &&
      audit.recoveryIssues.contains "recovery-reference-mismatch"
  | .error _ => false

private def duplicateSource : String :=
  lifecycleSource ++
  postcondition "file_compiles" true (digest 'd') ++
  postcondition "file_compiles" true (digest 'e') ++
  postcondition "artifact_recorded" true (digest 'f')

#guard match parseAudit duplicateSource with
  | .ok audit =>
      audit.outcome == .recoveryRequired &&
      audit.duplicates.contains "file_compiles"
  | .error _ => false

private def evidenceMissingSource : String :=
  lifecycleSource ++
  postcondition "file_compiles" true "" ++
  postcondition "artifact_recorded" true (digest 'f')

#guard match parseAudit evidenceMissingSource with
  | .ok audit =>
      audit.outcome == .recoveryRequired &&
      audit.evidenceMissing.contains "file_compiles"
  | .error _ => false

private def invalidLifecycleSource : String :=
  lifecycleSource false ++ passingPostconditions

#guard match parseAudit invalidLifecycleSource with
  | .ok audit => audit.outcome == .lifecycleInvalid && !audit.safe
  | .error _ => false

run_cmd do
  match parseAudit recoveredSource with
  | .error error => throwError error
  | .ok audit =>
      unless audit.safe do throwError "successful rollback was not classified as safe"
      let report := render audit
      unless report.startsWith "ZIL-RECOVERY-AUDIT\t1\n" do
        throwError "recovery audit report header is missing"
      unless (report.splitOn "outcome\trecovered").length > 1 do
        throwError "recovery audit report lost recovered outcome"
      unless (report.splitOn "failed\tartifact_recorded").length > 1 do
        throwError "recovery audit report lost failed postcondition evidence"
