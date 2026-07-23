namespace Zil.Workflow

/-- Frozen evidence for one proposed repository mutation. Every boolean is an
explicit result from the operational store rather than an inferred permission. -/
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
  deriving Repr, BEq, Inhabited

namespace ActionEvidence

/-- Required identifiers and revision references are populated. -/
def identityComplete (action : ActionEvidence) : Bool :=
  !action.actionId.isEmpty &&
  !action.agentId.isEmpty &&
  !action.moduleName.isEmpty &&
  !action.baseRevision.isEmpty &&
  !action.currentRevision.isEmpty

/-- The action was checked against a complete, current, conflict-free context. -/
def contextReady (action : ActionEvidence) : Bool :=
  action.contextFresh && action.contextComplete && action.noConflict

/-- The actor owns a valid authorization and lease for the mutation. -/
def authorizationReady (action : ActionEvidence) : Bool :=
  action.authorized && action.validLease

/-- The mutation has a checkpoint, passing preconditions, and a recovery path. -/
def recoveryReady (action : ActionEvidence) : Bool :=
  action.checkpointExists && action.preconditionsPass && action.recoveryAvailable

/-- Executable decision procedure for the workflow permission predicate. -/
def mayExecute (action : ActionEvidence) : Bool :=
  action.identityComplete &&
  action.contextReady &&
  action.authorizationReady &&
  action.recoveryReady

end ActionEvidence

/-- Proof-facing permission predicate used by generated workflow modules. -/
def MayExecute (action : ActionEvidence) : Prop :=
  action.mayExecute = true

instance (action : ActionEvidence) : Decidable (MayExecute action) := inferInstance

/-- One immutable workflow snapshot exported from the SQLite store. -/
structure Snapshot where
  revision : String
  complete : Bool
  actions : List ActionEvidence := []
  deriving Repr, BEq, Inhabited

namespace Snapshot

private def uniqueStrings : List String → Bool
  | [] => true
  | value :: rest => !rest.contains value && uniqueStrings rest

/-- Action identifiers are unique inside a frozen snapshot. -/
def actionIdsUnique (snapshot : Snapshot) : Bool :=
  uniqueStrings (snapshot.actions.map (·.actionId))

/-- Every action was evaluated against the snapshot revision. -/
def actionsMatchRevision (snapshot : Snapshot) : Bool :=
  snapshot.actions.all fun action => action.currentRevision == snapshot.revision

/-- Structural validity of the frozen evidence container. This does not assert
that every action is permitted. -/
def valid (snapshot : Snapshot) : Bool :=
  snapshot.complete &&
  !snapshot.revision.isEmpty &&
  snapshot.actionIdsUnique &&
  snapshot.actionsMatchRevision &&
  snapshot.actions.all ActionEvidence.identityComplete

/-- True exactly when every action in the snapshot has complete execution evidence. -/
def allMayExecute (snapshot : Snapshot) : Bool :=
  snapshot.actions.all ActionEvidence.mayExecute

end Snapshot

end Zil.Workflow
