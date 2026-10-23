import Zil.Crypto.Sha256
import Zil.Json.Ordered

/-!
# Release attestation

A deterministic attestation that a release's artifacts and its five classes of evidence (workflow verification, proof
token resolution, theorem locks, authorization, formalization plan) agree with the release request. Every class is
mandatory, every path is relative to the request directory and may not leave it, and the attestation carries the SHA-256
of the request and of itself, so any change to either changes its fingerprint.
-/

namespace Zil.Release

open Zil.Json Zil.Crypto

def requestFormat : String := "zil.release-request.v0.1"
def attestationFormat : String := "zil.release-attestation.v0.1"
def workflowFormat : String := "zil.workflow-verification.v0.1"
def proofFormat : String := "zil.proof-token-resolution.v0.1"
def lockFormat : String := "zil.theorem-lock-check.v0.1"
def acceptedTargetStatuses : List String := ["verified", "reviewed", "proved"]

/-- Raised for a request or an evidence file that is not valid, as opposed to evidence that fails. -/
private def invalid (message : String) : IO α := throw (IO.userError s!"validation: {message}")

private def v (document : J) (key : String) : J := (document.get? key).getD .null

private def nonempty (value : J) : Bool :=
  match value with
  | .str text => !text.all Char.isWhitespace
  | _ => false

private def sha256String (value : J) : Bool :=
  match value with
  | .str text => !text.all Char.isWhitespace && text.startsWith "sha256:"
  | _ => false

private def statusName (value : J) : Option String :=
  match value with
  | .str text => some text
  | _ => none

private def asNat (value : J) : Nat :=
  match value with
  | .int n => n.toNat
  | _ => 0

private def isInteger (value : J) : Bool := match value with | .int _ => true | _ => false

private def isArray (value : J) : Bool := match value with | .arr _ => true | _ => false

private def items (value : J) : Array J := match value with | .arr a => a | _ => #[]

/-- A failure record: its kind and any further fields. -/
private def failure (kind : String) (fields : Array (String × J) := #[]) : J :=
  .obj (#[("kind", .str kind)] ++ fields)

private def distinctCount (values : Array J) : Nat :=
  values.foldl (fun acc x => if acc.any (· == x) then acc else acc.push x) #[] |>.size

/-- The canonical bytes of a document: object fields sorted at every depth, `/` unescaped. -/
def canonicalText (document : J) : IO String := do
  match canonical document with
  | .ok value => return write value (escapeSlash := false)
  | .error message => invalid message

/-- SHA-256 of a document's canonical bytes. -/
def documentFingerprint (document : J) : IO String := do
  return Sha256.ofText (← canonicalText document)

/-- Resolve `raw` under `root` lexically; it must be relative and may not climb out of `root`. -/
private def containedFile (root : System.FilePath) (raw : J) : IO System.FilePath := do
  let some text := (match raw with | .str t => some t | _ => none) | invalid "Evidence path must be non-empty"
  if text.all Char.isWhitespace then invalid "Evidence path must be non-empty"
  if text.startsWith "/" then invalid s!"Release evidence paths must be relative ({text})"
  let mut stack : Array String := #[]
  for part in text.splitOn "/" do
    if part == "" || part == "." then pure ()
    else if part == ".." then
      if stack.isEmpty then invalid s!"Release evidence path escapes request directory ({text})"
      stack := stack.pop
    else stack := stack.push part
  let target := stack.foldl (fun path part => path / part) root
  -- an existing file must also resolve inside the root once symbolic links are followed
  if ← target.pathExists then
    let real ← IO.FS.realPath target
    let realRoot ← IO.FS.realPath root
    unless real.toString == realRoot.toString || real.toString.startsWith (realRoot.toString ++ "/") do
      invalid s!"Release evidence path escapes request directory ({text})"
  return target

private def isFile (path : System.FilePath) : IO Bool := do
  return (← path.pathExists) && !(← path.isDir)

private def fileSha256 (path : System.FilePath) : IO String := do
  return Sha256.prefixed (← IO.FS.readBinFile path)

def validateRequest (request : J) : IO Unit := do
  unless request.getStr? "format" == some requestFormat do invalid "Unsupported release request format"
  for key in ["release_id", "module"] do
    unless nonempty (v request key) do invalid s!"Release request field must be non-empty ({key})"
  let artifacts := v request "artifacts"
  let evidence := v request "evidence"
  unless isArray artifacts && !(items artifacts).isEmpty do invalid "Release request requires at least one artifact"
  let paths := (items artifacts).map (v · "path")
  unless distinctCount paths == paths.size do invalid "Release artifact paths must be unique"
  for artifact in items artifacts do
    unless nonempty (v artifact "path") do invalid "Release artifact path must be non-empty"
    unless sha256String (v artifact "sha256") do invalid "Release artifact requires a sha256 fingerprint"
  unless (match evidence with | .obj _ => true | _ => false) do invalid "Release request evidence must be an object"
  let keys := ["workflow", "proof_tokens", "theorem_locks", "authorization", "formalization"]
  for key in keys do
    unless (match v evidence key with | .obj _ => true | _ => false) do invalid s!"Release request is missing required evidence ({key})"
    unless nonempty (v (v evidence key) "path") do invalid s!"Release evidence path must be non-empty ({key})"
  let evidencePaths := (keys.map fun k => v (v evidence k) "path").toArray
  unless distinctCount evidencePaths == evidencePaths.size do invalid "Release evidence paths must be unique"
  let workflow := v evidence "workflow"
  let authorization := v evidence "authorization"
  let formalization := v evidence "formalization"
  let minimum := match v workflow "minimum_actions" with | .null => J.int 1 | other => other
  unless nonempty (v workflow "artifact") && paths.contains (v workflow "artifact") do
    invalid "Workflow evidence must name one release artifact"
  unless (match minimum with | .int n => decide (n > 0) | _ => false) do invalid "Workflow minimum_actions must be a positive integer"
  for key in ["object", "relation", "subject"] do
    unless nonempty (v authorization key) do invalid s!"Authorization evidence expectation must be non-empty ({key})"
  let targets := v formalization "required_targets"
  unless isArray targets && !(items targets).isEmpty && (items targets).all nonempty &&
      distinctCount (items targets) == (items targets).size do
    invalid "Formalization evidence requires unique target IDs"

private def readJson (path : System.FilePath) (expectedFormat : String) : IO J := do
  unless ← isFile path do invalid s!"Evidence file does not exist ({path})"
  match parse (← IO.FS.readFile path) with
  | .error message => invalid s!"Evidence file is not JSON ({path}): {message}"
  | .ok document =>
      unless document.getStr? "format" == some expectedFormat do
        invalid s!"Unsupported evidence format ({path}): expected {expectedFormat}"
      return document

private structure Validation where
  ok : Bool
  failures : Array J
  details : J

private def validation (failures : Array J) (details : J) : Validation :=
  { ok := failures.isEmpty, failures, details }

private def when_ (condition : Bool) (item : J) (out : Array J) : Array J := if condition then out.push item else out

private def validateWorkflow (document : J) (module : String) (minimumActions : Nat) : Validation :=
  let status := statusName (v (v document "verification") "status")
  let actions := if isInteger (v document "action_count") then asNat (v document "action_count") else 0
  let failures : Array J := #[]
    |> when_ (v document "ok" != .bool true) (failure "workflow_not_ok")
    |> when_ (document.getStr? "module" != some module)
        (failure "workflow_module_mismatch" #[("expected", .str module), ("actual", v document "module")])
    |> when_ (v document "complete" != .bool true) (failure "workflow_incomplete")
    |> when_ (status != some "verified")
        (failure "workflow_module_not_verified" #[("status", match status with | some s => .str s | none => .null)])
    |> when_ (actions < minimumActions)
        (failure "workflow_action_coverage" #[("required", .int minimumActions), ("actual", .int actions)])
    |> when_ (!sha256String (v document "output_sha256")) (failure "workflow_output_hash_missing")
  validation failures (.obj #[("revision", v document "revision"), ("actions", .int actions),
                              ("output_sha256", v document "output_sha256")])

private def validateProof (document : J) (module : String) : Validation :=
  let rowsRaw := v document "resolutions"
  let rows := items rowsRaw
  let intOr0 (key : String) := if isInteger (v document key) then asNat (v document key) else 0
  let tokenCount := intOr0 "token_count"
  let resolved := intOr0 "resolved"
  let unresolved := intOr0 "unresolved"
  let statuses := rows.map fun r => statusName (v r "status")
  let tokenIds := rows.map (v · "token_id")
  let failures : Array J := #[]
    |> when_ (v document "ok" != .bool true) (failure "proof_tokens_not_ok")
    |> when_ (document.getStr? "module" != some module)
        (failure "proof_module_mismatch" #[("expected", .str module), ("actual", v document "module")])
    |> when_ (!isArray rowsRaw) (failure "proof_resolution_rows_missing")
    |> when_ (!(tokenCount > 0)) (failure "proof_token_set_empty")
    |> when_ (tokenCount != rows.size)
        (failure "proof_resolution_row_count" #[("tokens", .int tokenCount), ("rows", .int rows.size)])
    |> when_ (tokenCount != resolved)
        (failure "proof_resolution_incomplete" #[("tokens", .int tokenCount), ("resolved", .int resolved)])
    |> when_ (unresolved != 0) (failure "proof_tokens_unresolved" #[("count", .int unresolved)])
    |> when_ (!(statuses.all (· == some "resolved")))
        (failure "proof_resolution_row_statuses"
          #[("statuses", .arr (statuses.map fun s => match s with | some t => .str t | none => .null))])
    |> when_ (distinctCount tokenIds != tokenIds.size) (failure "proof_token_ids_duplicate")
    |> when_ (!sha256String (v document "event_batch_fingerprint")) (failure "proof_event_fingerprint_missing")
    |> when_ (!sha256String (v document "token_batch_fingerprint")) (failure "proof_token_fingerprint_missing")
  validation failures (.obj #[("tokens", .int tokenCount),
    ("event_batch_fingerprint", v document "event_batch_fingerprint"),
    ("token_batch_fingerprint", v document "token_batch_fingerprint")])

private def validateLocks (document : J) (module : String) (proof : J) : Validation :=
  let rowsRaw := v document "results"
  let rows := items rowsRaw
  let intOr0 (key : String) := if isInteger (v document key) then asNat (v document key) else 0
  let changed := intOr0 "changed"
  let lockCount := intOr0 "lock_count"
  let unchanged := intOr0 "unchanged"
  let statuses := rows.map fun r => statusName (v r "status")
  let tokenIds := rows.map (v · "token_id")
  let sameEvents := v document "current_event_batch_fingerprint" == v proof "event_batch_fingerprint"
  let sameTokens := v document "current_token_batch_fingerprint" == v proof "token_batch_fingerprint"
  let failures : Array J := #[]
    |> when_ (v document "ok" != .bool true) (failure "theorem_locks_not_ok")
    |> when_ (document.getStr? "module" != some module)
        (failure "theorem_lock_module_mismatch" #[("expected", .str module), ("actual", v document "module")])
    |> when_ (!isArray rowsRaw) (failure "theorem_lock_rows_missing")
    |> when_ (!(lockCount > 0)) (failure "theorem_lock_set_empty")
    |> when_ (changed != 0) (failure "theorem_statement_drift" #[("changed", .int changed)])
    |> when_ (lockCount != unchanged)
        (failure "theorem_lock_coverage" #[("locks", .int lockCount), ("unchanged", .int unchanged)])
    |> when_ (unchanged != (statuses.filter (· == some "unchanged")).size)
        (failure "theorem_lock_row_count"
          #[("unchanged", .int unchanged),
            ("statuses", .arr (statuses.map fun s => match s with | some t => .str t | none => .null))])
    |> when_ (!(statuses.all fun s => s == some "unchanged" || s == some "additional_allowed"))
        (failure "theorem_lock_row_statuses"
          #[("statuses", .arr (statuses.map fun s => match s with | some t => .str t | none => .null))])
    |> when_ (distinctCount tokenIds != tokenIds.size) (failure "theorem_lock_token_ids_duplicate")
    |> when_ (!sameEvents) (failure "theorem_lock_event_snapshot_mismatch")
    |> when_ (!sameTokens) (failure "theorem_lock_token_snapshot_mismatch")
    |> when_ (!sha256String (v document "lock_document_fingerprint")) (failure "theorem_lock_fingerprint_missing")
  validation failures (.obj #[("locks", .int lockCount), ("unchanged", .int unchanged),
    ("lock_document_fingerprint", v document "lock_document_fingerprint")])

private def tabReport (path : System.FilePath) (expectedHeader : String) : IO (Array String) := do
  let lines := ((← IO.FS.readFile path).splitOn "\n").toArray.filter fun l => !l.all Char.isWhitespace
  unless lines[0]? == some expectedHeader do
    invalid s!"Unsupported tab-separated evidence report ({path}): expected {expectedHeader}"
  return lines

private def keyValueReport (lines : Array String) : IO (Array (String × String)) := do
  let mut out : Array (String × String) := #[]
  for line in lines.extract 1 lines.size do
    match line.splitOn "\t" with
    | [key, value] =>
        if out.any (·.1 == key) then invalid s!"Evidence report contains a duplicate key ({key})"
        out := out.push (key, value)
    | _ => invalid s!"Evidence report row must contain one key and value ({line})"
  return out

private def lookup (report : Array (String × String)) (key : String) : Option String :=
  report.find? (·.1 == key) |>.map (·.2)

private def optStr (value : Option String) : J := match value with | some s => .str s | none => .null

private def validateAuthorization (path : System.FilePath) (config : J) : IO Validation := do
  let report ← keyValueReport (← tabReport path "ZIL-AUTHORIZATION\t1")
  let failures : Array J := #[]
    |> when_ (lookup report "decision" != some "allow") (failure "authorization_denied")
    |> when_ (!(["direct", "derived"].any fun s => lookup report "source" == some s))
        (failure "authorization_source_invalid" #[("source", optStr (lookup report "source"))])
    |> when_ (config.getStr? "object" != lookup report "object") (failure "authorization_object_mismatch")
    |> when_ (config.getStr? "relation" != lookup report "relation") (failure "authorization_relation_mismatch")
    |> when_ (config.getStr? "subject" != lookup report "subject") (failure "authorization_subject_mismatch")
  return validation failures (.obj #[("object", optStr (lookup report "object")),
    ("relation", optStr (lookup report "relation")), ("subject", optStr (lookup report "subject")),
    ("source", optStr (lookup report "source"))])

private def validateFormalization (path : System.FilePath) (config : J) : IO Validation := do
  let lines ← tabReport path "ZIL-FORMALIZATION-PLAN\t1"
  let mut rows : Array (String × String) := #[]
  for line in lines.extract 1 lines.size do
    let parts := line.splitOn "\t"
    unless parts.length == 10 do invalid s!"Formalization plan row has the wrong number of fields ({line})"
    unless parts[0]! == "target" do invalid s!"Formalization plan row must begin with target ({line})"
    rows := rows.push (parts[1]!, parts[2]!)
  unless distinctCount (rows.map (fun r => J.str r.1)) == rows.size do
    invalid "Formalization plan target IDs must be unique"
  let required := items (v config "required_targets")
  let mut failures : Array J := #[]
  for target in required do
    let id := (target.asStr?).getD ""
    match rows.find? (·.1 == id) with
    | some (_, status) =>
        unless acceptedTargetStatuses.contains status do
          failures := failures.push (failure "formalization_target_not_accepted" #[("target", .str id), ("status", .str status)])
    | none => failures := failures.push (failure "formalization_target_missing" #[("target", .str id)])
  return validation failures (.obj #[("required_targets", .arr required), ("plan_targets", .int rows.size)])

private def evidenceRow (kind path sha : String) (ok : Bool) (details : J) : J :=
  .obj #[("kind", .str kind), ("path", .str path), ("sha256", .str sha),
         ("status", .str (if ok then "verified" else "failed")), ("details", details)]

/-- Attest a release: artifacts and evidence under `root` against `request`. -/
def attest (request : J) (root : System.FilePath) : IO J := do
  validateRequest request
  let module := (request.getStr? "module").getD ""
  let evidence := v request "evidence"
  -- artifacts
  let mut artifactRows : Array J := #[]
  let mut artifactFailures : Array J := #[]
  let mut actualByPath : Array (String × Option String) := #[]
  for artifact in items (v request "artifacts") do
    let path := (artifact.getStr? "path").getD ""
    let expected := (artifact.getStr? "sha256").getD ""
    let file ← containedFile root (v artifact "path")
    if ← isFile file then
      let actual ← fileSha256 file
      let status := if expected == actual then "verified" else "hash_mismatch"
      let row : J := .obj #[("path", .str path), ("expected_sha256", .str expected), ("actual_sha256", .str actual),
                            ("status", .str status)]
      artifactRows := artifactRows.push row
      actualByPath := actualByPath.push (path, some actual)
      if status != "verified" then
        artifactFailures := artifactFailures.push (match row with
          | .obj fields => .obj (fields.push ("kind", .str "artifact_failure")) | other => other)
    else
      let row : J := .obj #[("path", .str path), ("expected_sha256", .str expected), ("actual_sha256", .null),
                            ("status", .str "missing")]
      artifactRows := artifactRows.push row
      actualByPath := actualByPath.push (path, none)
      artifactFailures := artifactFailures.push (match row with
        | .obj fields => .obj (fields.push ("kind", .str "artifact_failure")) | other => other)
  -- evidence files
  let workflowConfig := v evidence "workflow"
  let proofConfig := v evidence "proof_tokens"
  let lockConfig := v evidence "theorem_locks"
  let authorizationConfig := v evidence "authorization"
  let formalizationConfig := v evidence "formalization"
  let workflowFile ← containedFile root (v workflowConfig "path")
  let proofFile ← containedFile root (v proofConfig "path")
  let lockFile ← containedFile root (v lockConfig "path")
  let authorizationFile ← containedFile root (v authorizationConfig "path")
  let formalizationFile ← containedFile root (v formalizationConfig "path")
  let workflowDocument ← readJson workflowFile workflowFormat
  let proofDocument ← readJson proofFile proofFormat
  let lockDocument ← readJson lockFile lockFormat
  let minimum := match v workflowConfig "minimum_actions" with | .int n => n.toNat | _ => 1
  let workflowResult := validateWorkflow workflowDocument module minimum
  let proofResult := validateProof proofDocument module
  let lockResult := validateLocks lockDocument module proofDocument
  let authorizationResult ← validateAuthorization authorizationFile authorizationConfig
  let formalizationResult ← validateFormalization formalizationFile formalizationConfig
  -- the workflow output must be one of the release artifacts, byte for byte
  let workflowArtifact := (workflowConfig.getStr? "artifact").getD ""
  let artifactActual := actualByPath.find? (·.1 == workflowArtifact)
  let bindingFailures : Array J := #[]
    |> when_ artifactActual.isNone
        (failure "workflow_artifact_missing_from_release" #[("artifact", .str workflowArtifact)])
    |> when_ (match artifactActual with
        | some (_, actual) => v workflowDocument "output_sha256" != (match actual with | some a => J.str a | none => .null)
        | none => false)
        (failure "workflow_artifact_hash_mismatch"
          #[("artifact", .str workflowArtifact), ("workflow_sha256", v workflowDocument "output_sha256"),
            ("artifact_sha256", match artifactActual with | some (_, some a) => .str a | _ => .null)])
  let rows : Array J := #[
    evidenceRow "workflow" ((workflowConfig.getStr? "path").getD "") (← fileSha256 workflowFile) workflowResult.ok workflowResult.details,
    evidenceRow "proof_tokens" ((proofConfig.getStr? "path").getD "") (← fileSha256 proofFile) proofResult.ok proofResult.details,
    evidenceRow "theorem_locks" ((lockConfig.getStr? "path").getD "") (← fileSha256 lockFile) lockResult.ok lockResult.details,
    evidenceRow "authorization" ((authorizationConfig.getStr? "path").getD "") (← fileSha256 authorizationFile)
      authorizationResult.ok authorizationResult.details,
    evidenceRow "formalization" ((formalizationConfig.getStr? "path").getD "") (← fileSha256 formalizationFile)
      formalizationResult.ok formalizationResult.details]
  let evidenceFailures := workflowResult.failures ++ proofResult.failures ++ lockResult.failures ++
    authorizationResult.failures ++ formalizationResult.failures ++ bindingFailures
  let failures := artifactFailures ++ evidenceFailures
  let body : J := .obj #[("format", .str attestationFormat), ("ok", .bool failures.isEmpty),
    ("release_id", v request "release_id"), ("module", .str module),
    ("request_fingerprint", .str (← documentFingerprint request)), ("artifacts", .arr artifactRows),
    ("evidence", .arr rows), ("failures", .arr failures)]
  let fingerprint ← documentFingerprint body
  match body with
  | .obj fields => return .obj (fields.push ("attestation_fingerprint", .str fingerprint))
  | other => return other

/-- Canonical text of a finished attestation, as written to a file. -/
def render (attestation : J) : IO String := canonicalText attestation

/-- Attest the release named by a request file and write the attestation. -/
def attestFile (requestPath : System.FilePath) (outputPath : System.FilePath) : IO J := do
  unless ← isFile requestPath do invalid s!"Release request file does not exist ({requestPath})"
  let root := requestPath.parent.getD "."
  let request ← match parse (← IO.FS.readFile requestPath) with
    | .ok r => pure r
    | .error message => invalid s!"Release request is not JSON: {message}"
  let attestation ← attest request root
  if let some parent := outputPath.parent then IO.FS.createDirAll parent
  IO.FS.writeFile outputPath ((← render attestation) ++ "\n")
  return attestation

end Zil.Release
