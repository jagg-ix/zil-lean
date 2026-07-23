import Zil.Core.Program

namespace Zil.ActionToken

/-- Evidence that must already be resolved before a mutation token can be issued. -/
structure Evidence where
  contextFresh : Bool
  contextComplete : Bool
  noCriticalConflict : Bool
  authorized : Bool
  validLease : Bool
  preconditionsPass : Bool
  recoveryAvailable : Bool
  storeIntegrity : Bool
  deriving Repr, BEq, Inhabited

/-- Durable lease snapshot checked by the native issuance contract. -/
structure Lease where
  agentId : String
  moduleName : String
  scope : String
  baseRevision : String
  expiresAt : Nat
  active : Bool
  deriving Repr, BEq, Inhabited

/-- Intended mutation and its mandatory verification effects. -/
structure ActionSpec where
  actionType : String
  target : String
  expectedEffects : Array String := #[]
  requiredPostconditions : Array String := #[]
  deriving Repr, BEq, Inhabited

/-- Recovery operation bound before token issuance. -/
structure Rollback where
  kind : String
  reference : String
  deriving Repr, BEq, Inhabited

/-- Complete native action-token request. -/
structure Request where
  tokenId : String
  taskId : String
  agentId : String
  moduleName : String
  baseRevision : String
  currentRevision : String
  scope : String
  leaseId : String
  contextBundleId : String
  now : Nat
  ttlSeconds : Nat
  lease : Lease
  action : ActionSpec
  rollback : Rollback
  evidence : Evidence
  deriving Repr, BEq, Inhabited

/-- Fail-closed issuance reasons, in deterministic evaluation order. -/
inductive Failure where
  | contextFresh
  | contextComplete
  | noCriticalConflict
  | authorized
  | validLeaseEvidence
  | preconditionsPass
  | recoveryAvailable
  | storeIntegrity
  | contextStale
  | leaseMismatch
  | leaseInactive
  | leaseExpired
  | invalidTokenTtl
  | invalidContextBundleId
  | invalidIdentity
  | invalidAction
  | missingRollback
  deriving Repr, BEq, Inhabited

namespace Failure

def token : Failure → String
  | .contextFresh => "context-fresh"
  | .contextComplete => "context-complete"
  | .noCriticalConflict => "no-critical-conflict"
  | .authorized => "authorized"
  | .validLeaseEvidence => "valid-lease"
  | .preconditionsPass => "preconditions-pass"
  | .recoveryAvailable => "recovery-available"
  | .storeIntegrity => "store-integrity"
  | .contextStale => "context-stale"
  | .leaseMismatch => "lease-mismatch"
  | .leaseInactive => "lease-inactive"
  | .leaseExpired => "lease-expired"
  | .invalidTokenTtl => "invalid-token-ttl"
  | .invalidContextBundleId => "invalid-context-bundle-id"
  | .invalidIdentity => "invalid-identity"
  | .invalidAction => "invalid-action"
  | .missingRollback => "missing-rollback"

end Failure

/-- Issued token payload. The token is still required to obtain a checkpoint. -/
structure Token where
  tokenId : String
  taskId : String
  agentId : String
  moduleName : String
  baseRevision : String
  scope : String
  leaseId : String
  contextBundleId : String
  action : ActionSpec
  rollback : Rollback
  issuedAt : Nat
  expiresAt : Nat
  requiredCheckpoint : Bool := true
  deriving Repr, BEq, Inhabited

/-- Native issuance decision. -/
structure Decision where
  allowed : Bool
  failures : Array Failure := #[]
  token : Option Token := none
  deriving Repr, BEq, Inhabited

private def isHex (char : Char) : Bool :=
  ('0' ≤ char && char ≤ '9') ||
  ('a' ≤ char && char ≤ 'f') ||
  ('A' ≤ char && char ≤ 'F')

/-- Exact context bundle IDs are SHA-256 identifiers over canonical context bytes. -/
def validContextBundleId (value : String) : Bool :=
  value.startsWith "sha256:" &&
  value.length == 71 &&
  (value.drop 7).data.all isHex

private def identityValid (request : Request) : Bool :=
  !request.tokenId.isEmpty &&
  !request.taskId.isEmpty &&
  !request.agentId.isEmpty &&
  !request.moduleName.isEmpty &&
  !request.baseRevision.isEmpty &&
  !request.currentRevision.isEmpty &&
  !request.scope.isEmpty &&
  !request.leaseId.isEmpty

private def actionValid (action : ActionSpec) : Bool :=
  !action.actionType.isEmpty && !action.target.isEmpty

private def rollbackValid (rollback : Rollback) : Bool :=
  (rollback.kind == "rollback" || rollback.kind == "compensation") &&
  !rollback.reference.isEmpty

private def leaseMatches (request : Request) : Bool :=
  request.lease.agentId == request.agentId &&
  request.lease.moduleName == request.moduleName &&
  request.lease.scope == request.scope &&
  request.lease.baseRevision == request.baseRevision

/-- Evaluate token issuance without mutating durable state. -/
def issue (request : Request) : Decision := Id.run do
  let mut failures : Array Failure := #[]
  unless request.evidence.contextFresh do failures := failures.push .contextFresh
  unless request.evidence.contextComplete do failures := failures.push .contextComplete
  unless request.evidence.noCriticalConflict do failures := failures.push .noCriticalConflict
  unless request.evidence.authorized do failures := failures.push .authorized
  unless request.evidence.validLease do failures := failures.push .validLeaseEvidence
  unless request.evidence.preconditionsPass do failures := failures.push .preconditionsPass
  unless request.evidence.recoveryAvailable do failures := failures.push .recoveryAvailable
  unless request.evidence.storeIntegrity do failures := failures.push .storeIntegrity
  unless request.baseRevision == request.currentRevision do failures := failures.push .contextStale
  unless leaseMatches request do failures := failures.push .leaseMismatch
  unless request.lease.active do failures := failures.push .leaseInactive
  unless request.now < request.lease.expiresAt do failures := failures.push .leaseExpired
  unless request.ttlSeconds > 0 do failures := failures.push .invalidTokenTtl
  unless validContextBundleId request.contextBundleId do
    failures := failures.push .invalidContextBundleId
  unless identityValid request do failures := failures.push .invalidIdentity
  unless actionValid request.action do failures := failures.push .invalidAction
  unless rollbackValid request.rollback do failures := failures.push .missingRollback
  if failures.isEmpty then
    let expiresAt := Nat.min (request.now + request.ttlSeconds) request.lease.expiresAt
    return {
      allowed := true
      token := some {
        tokenId := request.tokenId
        taskId := request.taskId
        agentId := request.agentId
        moduleName := request.moduleName
        baseRevision := request.baseRevision
        scope := request.scope
        leaseId := request.leaseId
        contextBundleId := request.contextBundleId
        action := request.action
        rollback := request.rollback
        issuedAt := request.now
        expiresAt
      }
    }
  return { allowed := false, failures }

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
    | none => throw s!"action token request is missing {key}"
  let text ← match textValue? value with
    | some text => pure text
    | none => throw s!"action token request attribute {key} must be ground"
  if text.isEmpty then throw s!"action token request attribute {key} must be nonempty"
  pure text

private def optionalText (fact : Zil.RelExpr) (key : Name) (fallback : String := "") : String :=
  match attr? fact key with
  | some value => (textValue? value).getD fallback
  | none => fallback

private def requiredBool (fact : Zil.RelExpr) (key : Name) : Except String Bool :=
  match attr? fact key with
  | some (.boolean value) => pure value
  | some _ => throw s!"action token request attribute {key} must be boolean"
  | none => throw s!"action token request is missing {key}"

private def requiredNat (fact : Zil.RelExpr) (key : Name) : Except String Nat := do
  match attr? fact key with
  | some (.integer value) =>
      if value < 0 then throw s!"action token request attribute {key} must be nonnegative"
      else pure value.toNat
  | some value =>
      let text ← match textValue? value with
        | some text => pure text
        | none => throw s!"action token request attribute {key} must be numeric"
      match text.toNat? with
      | some number => pure number
      | none => throw s!"action token request attribute {key} must be numeric"
  | none => throw s!"action token request is missing {key}"

private def listText (fact : Zil.RelExpr) (key : Name) : Array String :=
  let text := optionalText fact key
  if text.isEmpty then #[]
  else (text.splitOn "|").toArray.filter fun value => !value.isEmpty

private def requestFact?
    (program : Zil.Program)
    (requestNode : Name) : Option Zil.RelExpr :=
  program.facts.find? fun fact =>
    fact.subject == .ground requestNode &&
    fact.relation == `zil.actionTokenRequest

/-- Decode one request from an attributed `action_token_request` relation. -/
def fromProgram (program : Zil.Program) (requestNode : Name) : Except String Request := do
  let fact ← match requestFact? program requestNode with
    | some fact => pure fact
    | none => throw s!"action token request {requestNode} was not found"
  pure {
    tokenId := ← requiredText fact `token_id
    taskId := ← requiredText fact `task_id
    agentId := ← requiredText fact `agent_id
    moduleName := ← requiredText fact `module
    baseRevision := ← requiredText fact `base_revision
    currentRevision := ← requiredText fact `current_revision
    scope := ← requiredText fact `scope
    leaseId := ← requiredText fact `lease_id
    contextBundleId := ← requiredText fact `context_bundle_id
    now := ← requiredNat fact `now
    ttlSeconds := ← requiredNat fact `ttl_seconds
    lease := {
      agentId := ← requiredText fact `lease_agent_id
      moduleName := ← requiredText fact `lease_module
      scope := ← requiredText fact `lease_scope
      baseRevision := ← requiredText fact `lease_base_revision
      expiresAt := ← requiredNat fact `lease_expires_at
      active := ← requiredBool fact `lease_active
    }
    action := {
      actionType := ← requiredText fact `action_type
      target := ← requiredText fact `action_target
      expectedEffects := listText fact `expected_effects
      requiredPostconditions := listText fact `required_postconditions
    }
    rollback := {
      kind := ← requiredText fact `rollback_kind
      reference := ← requiredText fact `rollback_reference
    }
    evidence := {
      contextFresh := ← requiredBool fact `context_fresh
      contextComplete := ← requiredBool fact `context_complete
      noCriticalConflict := ← requiredBool fact `no_critical_conflict
      authorized := ← requiredBool fact `authorized
      validLease := ← requiredBool fact `valid_lease
      preconditionsPass := ← requiredBool fact `preconditions_pass
      recoveryAvailable := ← requiredBool fact `recovery_available
      storeIntegrity := ← requiredBool fact `store_integrity
    }
  }

private def stringsText (values : Array String) : String :=
  String.intercalate "|" values.toList

private def failuresText (values : Array Failure) : String :=
  String.intercalate "," (values.toList.map Failure.token)

/-- Stable native issuance report. -/
def render (requestNode : Name) (decision : Decision) : String :=
  let tokenRows := match decision.token with
    | none => []
    | some token => [
        "token-id\t" ++ token.tokenId,
        "task-id\t" ++ token.taskId,
        "agent-id\t" ++ token.agentId,
        "module\t" ++ token.moduleName,
        "base-revision\t" ++ token.baseRevision,
        "scope\t" ++ token.scope,
        "lease-id\t" ++ token.leaseId,
        "context-bundle-id\t" ++ token.contextBundleId,
        "action-type\t" ++ token.action.actionType,
        "action-target\t" ++ token.action.target,
        "expected-effects\t" ++ stringsText token.action.expectedEffects,
        "required-postconditions\t" ++ stringsText token.action.requiredPostconditions,
        "rollback-kind\t" ++ token.rollback.kind,
        "rollback-reference\t" ++ token.rollback.reference,
        "issued-at\t" ++ toString token.issuedAt,
        "expires-at\t" ++ toString token.expiresAt,
        "required-checkpoint\ttrue"
      ]
  String.intercalate "\n" <|
    ["ZIL-ACTION-TOKEN\t1",
     "status\t" ++ (if decision.allowed then "issued" else "denied"),
     "request\t" ++ requestNode.toString,
     "failures\t" ++ failuresText decision.failures] ++ tokenRows ++ [""]

end Zil.ActionToken
