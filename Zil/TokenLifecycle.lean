import Zil.ActionToken

namespace Zil.TokenLifecycle

/-- Durable lifecycle states for one issued action token. -/
inductive Status where
  | issued
  | checkpointed
  | consumed
  deriving Repr, BEq, Inhabited

namespace Status

def token : Status → String
  | .issued => "issued"
  | .checkpointed => "checkpointed"
  | .consumed => "consumed"

end Status

/-- Checkpoint evidence bound to one token and revision. -/
structure Checkpoint where
  checkpointId : String
  agentId : String
  revision : String
  snapshotDigest : String
  createdAt : Nat
  deriving Repr, BEq, Inhabited

/-- One observed action output. -/
structure ObservedOutput where
  artifact : String
  hash : String
  deriving Repr, BEq, Inhabited

/-- Recorded single-use action execution. -/
structure Execution where
  actionId : String
  checkpointId : String
  revision : String
  executedAt : Nat
  outputs : Array ObservedOutput
  deriving Repr, BEq, Inhabited

/-- Native lifecycle state. -/
structure State where
  token : Zil.ActionToken.Token
  lease : Zil.ActionToken.Lease
  status : Status := .issued
  checkpoint : Option Checkpoint := none
  execution : Option Execution := none
  deriving Repr, BEq, Inhabited

/-- Request to bind the required checkpoint. -/
structure CheckpointRequest where
  checkpointId : String
  agentId : String
  currentRevision : String
  snapshotDigest : String
  now : Nat
  deriving Repr, BEq, Inhabited

/-- Request to consume the token exactly once. -/
structure ExecutionRequest where
  actionId : String
  checkpointId : String
  currentRevision : String
  now : Nat
  storeIntegrity : Bool
  lease : Zil.ActionToken.Lease
  outputs : Array ObservedOutput := #[]
  deriving Repr, BEq, Inhabited

inductive Failure where
  | tokenNotIssued
  | tokenNotCheckpointed
  | agentMismatch
  | contextStale
  | tokenExpired
  | invalidCheckpointId
  | invalidSnapshotDigest
  | checkpointMismatch
  | storeIntegrity
  | leaseMismatch
  | leaseInactive
  | leaseExpired
  | invalidActionId
  | invalidObservedOutput
  deriving Repr, BEq, Inhabited

namespace Failure

def token : Failure → String
  | .tokenNotIssued => "token-not-issued"
  | .tokenNotCheckpointed => "token-not-checkpointed"
  | .agentMismatch => "agent-mismatch"
  | .contextStale => "context-stale"
  | .tokenExpired => "token-expired"
  | .invalidCheckpointId => "invalid-checkpoint-id"
  | .invalidSnapshotDigest => "invalid-snapshot-digest"
  | .checkpointMismatch => "checkpoint-mismatch"
  | .storeIntegrity => "store-integrity"
  | .leaseMismatch => "lease-mismatch"
  | .leaseInactive => "lease-inactive"
  | .leaseExpired => "lease-expired"
  | .invalidActionId => "invalid-action-id"
  | .invalidObservedOutput => "invalid-observed-output"

end Failure

private def isHex (char : Char) : Bool :=
  ('0' ≤ char && char ≤ '9') ||
  ('a' ≤ char && char ≤ 'f') ||
  ('A' ≤ char && char ≤ 'F')

/-- SHA-256 identifiers used by checkpoints and observed artifacts. -/
def validSha256 (value : String) : Bool :=
  value.startsWith "sha256:" && value.length == 71 &&
  (value.drop 7).data.all isHex

/-- Initialize lifecycle state from one successful issuance decision. -/
def initialize
    (request : Zil.ActionToken.Request)
    (decision : Zil.ActionToken.Decision) : Except String State := do
  let token ← match decision.token with
    | some value => pure value
    | none => throw "cannot initialize lifecycle without an issued token"
  unless decision.allowed do throw "cannot initialize lifecycle from a denied request"
  pure { token, lease := request.lease }

/-- Bind one checkpoint while token, agent, revision, and expiry remain current. -/
def bindCheckpoint
    (state : State)
    (request : CheckpointRequest) : Except Failure State := do
  unless state.status == .issued do throw .tokenNotIssued
  unless request.agentId == state.token.agentId do throw .agentMismatch
  unless request.currentRevision == state.token.baseRevision do throw .contextStale
  unless request.now < state.token.expiresAt do throw .tokenExpired
  if request.checkpointId.isEmpty then throw .invalidCheckpointId
  unless validSha256 request.snapshotDigest do throw .invalidSnapshotDigest
  pure {
    state with
    status := .checkpointed
    checkpoint := some {
      checkpointId := request.checkpointId
      agentId := request.agentId
      revision := request.currentRevision
      snapshotDigest := request.snapshotDigest
      createdAt := request.now
    }
  }

private def leaseMatches
    (token : Zil.ActionToken.Token)
    (lease : Zil.ActionToken.Lease) : Bool :=
  lease.agentId == token.agentId &&
  lease.moduleName == token.moduleName &&
  lease.scope == token.scope &&
  lease.baseRevision == token.baseRevision

private def outputValid (output : ObservedOutput) : Bool :=
  !output.artifact.isEmpty && validSha256 output.hash

/-- Consume one checkpointed token exactly once. -/
def execute
    (state : State)
    (request : ExecutionRequest) : Except Failure State := do
  unless state.status == .checkpointed do throw .tokenNotCheckpointed
  let checkpoint ← match state.checkpoint with
    | some value => pure value
    | none => throw .checkpointMismatch
  unless request.checkpointId == checkpoint.checkpointId do throw .checkpointMismatch
  unless request.currentRevision == state.token.baseRevision &&
         checkpoint.revision == state.token.baseRevision do
    throw .contextStale
  unless request.now < state.token.expiresAt do throw .tokenExpired
  unless request.storeIntegrity do throw .storeIntegrity
  unless leaseMatches state.token request.lease do throw .leaseMismatch
  unless request.lease.active do throw .leaseInactive
  unless request.now < request.lease.expiresAt do throw .leaseExpired
  if request.actionId.isEmpty then throw .invalidActionId
  unless request.outputs.all outputValid do throw .invalidObservedOutput
  pure {
    state with
    lease := request.lease
    status := .consumed
    execution := some {
      actionId := request.actionId
      checkpointId := request.checkpointId
      revision := request.currentRevision
      executedAt := request.now
      outputs := request.outputs
    }
  }

private def attr? (fact : Zil.RelExpr) (key : Name) : Option Zil.AttrValue :=
  (Zil.Attribute.find? fact.attrs key).map (·.value)

private def textValue? : Zil.AttrValue → Option String
  | .text value => some value
  | .decimal value => some value
  | .integer value => some (toString value)
  | .boolean value => some (if value then "true" else "false")
  | .term (.node node) => some node.name.toString
  | .term (.var _) => none

private def requiredText (fact : Zil.RelExpr) (key : Name) : Except String String := do
  let value ← match attr? fact key with
    | some value => pure value
    | none => throw s!"lifecycle event is missing {key}"
  let text ← match textValue? value with
    | some text => pure text
    | none => throw s!"lifecycle event attribute {key} must be ground"
  if text.isEmpty then throw s!"lifecycle event attribute {key} must be nonempty"
  pure text

private def requiredBool (fact : Zil.RelExpr) (key : Name) : Except String Bool :=
  match attr? fact key with
  | some (.boolean value) => pure value
  | some _ => throw s!"lifecycle event attribute {key} must be boolean"
  | none => throw s!"lifecycle event is missing {key}"

private def requiredNat (fact : Zil.RelExpr) (key : Name) : Except String Nat := do
  match attr? fact key with
  | some (.integer value) =>
      if value < 0 then throw s!"lifecycle event attribute {key} must be nonnegative"
      else pure value.toNat
  | some value =>
      match (textValue? value).bind String.toNat? with
      | some number => pure number
      | none => throw s!"lifecycle event attribute {key} must be numeric"
  | none => throw s!"lifecycle event is missing {key}"

private def eventFact?
    (program : Zil.Program)
    (requestNode relation : Name) : Option Zil.RelExpr :=
  program.facts.find? fun fact =>
    fact.subject == .ground requestNode && fact.relation == relation

private def parseOutputs (text : String) : Except String (Array ObservedOutput) := do
  if text.isEmpty then return #[]
  let mut outputs : Array ObservedOutput := #[]
  for raw in text.splitOn "|" do
    match raw.splitOn "=" with
    | [artifact, hash] =>
        if artifact.isEmpty || hash.isEmpty then
          throw "observed output requires artifact and hash"
        outputs := outputs.push { artifact, hash }
    | _ => throw s!"invalid observed output {raw}"
  pure outputs

/-- Decode the optional checkpoint event for one request node. -/
def checkpointFromProgram
    (program : Zil.Program)
    (requestNode : Name) : Except String (Option CheckpointRequest) := do
  match eventFact? program requestNode `zil.checkpointEvent with
  | none => pure none
  | some fact =>
      pure <| some {
        checkpointId := ← requiredText fact `checkpoint_id
        agentId := ← requiredText fact `agent_id
        currentRevision := ← requiredText fact `current_revision
        snapshotDigest := ← requiredText fact `snapshot_digest
        now := ← requiredNat fact `now
      }

/-- Decode the optional execution event for one request node. -/
def executionFromProgram
    (program : Zil.Program)
    (requestNode : Name) : Except String (Option ExecutionRequest) := do
  match eventFact? program requestNode `zil.executionEvent with
  | none => pure none
  | some fact =>
      let outputs ← parseOutputs <| match attr? fact `observed_outputs with
        | some value => (textValue? value).getD ""
        | none => ""
      pure <| some {
        actionId := ← requiredText fact `action_id
        checkpointId := ← requiredText fact `checkpoint_id
        currentRevision := ← requiredText fact `current_revision
        now := ← requiredNat fact `now
        storeIntegrity := ← requiredBool fact `store_integrity
        lease := {
          agentId := ← requiredText fact `lease_agent_id
          moduleName := ← requiredText fact `lease_module
          scope := ← requiredText fact `lease_scope
          baseRevision := ← requiredText fact `lease_base_revision
          expiresAt := ← requiredNat fact `lease_expires_at
          active := ← requiredBool fact `lease_active
        }
        outputs
      }

/-- Result of replaying issuance, checkpoint, and execution events. -/
structure Audit where
  requestNode : Name
  issuance : Zil.ActionToken.Decision
  state : Option State
  checkpointFailure : Option Failure := none
  executionFailure : Option Failure := none
  ok : Bool
  deriving Repr, Inhabited

/-- Replay the complete lifecycle declared for one request node. -/
def auditProgram
    (program : Zil.Program)
    (requestNode : Name) : Except String Audit := do
  let request ← Zil.ActionToken.fromProgram program requestNode
  let issuance := Zil.ActionToken.issue request
  if !issuance.allowed then
    return { requestNode, issuance, state := none, ok := false }
  let initial ← initialize request issuance
  let checkpointEvent ← checkpointFromProgram program requestNode
  let executionEvent ← executionFromProgram program requestNode
  let afterCheckpoint ← match checkpointEvent with
    | none => pure (.ok initial)
    | some event => pure (bindCheckpoint initial event)
  match afterCheckpoint with
  | .error failure =>
      pure {
        requestNode
        issuance
        state := some initial
        checkpointFailure := some failure
        ok := false
      }
  | .ok checkpointed =>
      match executionEvent with
      | none =>
          pure {
            requestNode
            issuance
            state := some checkpointed
            ok := checkpointEvent.isSome
          }
      | some event =>
          match execute checkpointed event with
          | .error failure =>
              pure {
                requestNode
                issuance
                state := some checkpointed
                executionFailure := some failure
                ok := false
              }
          | .ok consumed =>
              pure { requestNode, issuance, state := some consumed, ok := true }

private def failureText : Option Failure → String
  | none => ""
  | some failure => failure.token

private def outputsText (outputs : Array ObservedOutput) : String :=
  String.intercalate "|" (outputs.toList.map fun output =>
    output.artifact ++ "=" ++ output.hash)

/-- Stable lifecycle replay report. -/
def render (audit : Audit) : String :=
  let stateRows := match audit.state with
    | none => []
    | some state =>
        let checkpointRows := match state.checkpoint with
          | none => []
          | some checkpoint => [
              "checkpoint-id\t" ++ checkpoint.checkpointId,
              "checkpoint-revision\t" ++ checkpoint.revision,
              "snapshot-digest\t" ++ checkpoint.snapshotDigest,
              "checkpoint-created-at\t" ++ toString checkpoint.createdAt
            ]
        let executionRows := match state.execution with
          | none => []
          | some execution => [
              "action-id\t" ++ execution.actionId,
              "execution-revision\t" ++ execution.revision,
              "executed-at\t" ++ toString execution.executedAt,
              "observed-outputs\t" ++ outputsText execution.outputs
            ]
        ["token-status\t" ++ state.status.token] ++ checkpointRows ++ executionRows
  String.intercalate "\n" <|
    ["ZIL-TOKEN-LIFECYCLE\t1",
     "status\t" ++ (if audit.ok then "pass" else "fail"),
     "request\t" ++ audit.requestNode.toString,
     "issuance\t" ++ (if audit.issuance.allowed then "issued" else "denied"),
     "checkpoint-failure\t" ++ failureText audit.checkpointFailure,
     "execution-failure\t" ++ failureText audit.executionFailure] ++ stateRows ++ [""]

end Zil.TokenLifecycle
