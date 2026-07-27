module

@[expose] public section

namespace Zil.Workflow

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
  deriving Repr, DecidableEq, Inhabited

def MayExecute (action : ActionEvidence) : Prop :=
  action.contextFresh = true ∧
  action.contextComplete = true ∧
  action.noConflict = true ∧
  action.authorized = true ∧
  action.validLease = true ∧
  action.checkpointExists = true ∧
  action.preconditionsPass = true ∧
  action.recoveryAvailable = true

instance (action : ActionEvidence) : Decidable (MayExecute action) := by
  unfold MayExecute
  infer_instance

theorem mayExecute_requires_current_context {action : ActionEvidence}
    (allowed : MayExecute action) : action.contextFresh = true := allowed.1

theorem mayExecute_requires_complete_context {action : ActionEvidence}
    (allowed : MayExecute action) : action.contextComplete = true := allowed.2.1

theorem mayExecute_requires_no_conflict {action : ActionEvidence}
    (allowed : MayExecute action) : action.noConflict = true := allowed.2.2.1

theorem mayExecute_requires_authorization {action : ActionEvidence}
    (allowed : MayExecute action) : action.authorized = true := allowed.2.2.2.1

theorem mayExecute_requires_valid_lease {action : ActionEvidence}
    (allowed : MayExecute action) : action.validLease = true := allowed.2.2.2.2.1

theorem mayExecute_requires_checkpoint {action : ActionEvidence}
    (allowed : MayExecute action) : action.checkpointExists = true := allowed.2.2.2.2.2.1

theorem mayExecute_requires_preconditions {action : ActionEvidence}
    (allowed : MayExecute action) : action.preconditionsPass = true := allowed.2.2.2.2.2.2.1

theorem mayExecute_requires_recovery {action : ActionEvidence}
    (allowed : MayExecute action) : action.recoveryAvailable = true := allowed.2.2.2.2.2.2.2

theorem mayExecute_revision_matches {action : ActionEvidence}
    (allowed : MayExecute action)
    (freshMeansEqual : action.contextFresh = true →
      action.baseRevision = action.currentRevision) :
    action.baseRevision = action.currentRevision :=
  freshMeansEqual (mayExecute_requires_current_context allowed)

structure Snapshot where
  revision : String
  complete : Bool
  actions : List ActionEvidence
  deriving Repr, DecidableEq, Inhabited

end Zil.Workflow
