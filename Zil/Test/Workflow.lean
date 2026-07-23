import Zil.Workflow

open Zil.Workflow

private def readyAction : ActionEvidence := {
  actionId := "action:1"
  agentId := "agent:a"
  moduleName := "Demo"
  baseRevision := "rev:1"
  currentRevision := "rev:1"
  contextFresh := true
  contextComplete := true
  noConflict := true
  authorized := true
  validLease := true
  checkpointExists := true
  preconditionsPass := true
  recoveryAvailable := true
}

private def blockedAction : ActionEvidence :=
  { readyAction with actionId := "action:2", validLease := false }

private def validSnapshot : Snapshot := {
  revision := "rev:1"
  complete := true
  actions := [readyAction, blockedAction]
}

#guard readyAction.identityComplete
#guard readyAction.contextReady
#guard readyAction.authorizationReady
#guard readyAction.recoveryReady
#guard readyAction.mayExecute
#guard !blockedAction.mayExecute
#guard validSnapshot.valid
#guard !validSnapshot.allMayExecute

example : MayExecute readyAction := by
  native_decide

private def duplicateSnapshot : Snapshot :=
  { validSnapshot with actions := [readyAction, readyAction] }

private def staleSnapshot : Snapshot :=
  { validSnapshot with revision := "rev:2" }

#guard !duplicateSnapshot.valid
#guard !staleSnapshot.valid
#guard !({ validSnapshot with complete := false }).valid

run_cmd do
  unless validSnapshot.valid do
    throwError "workflow snapshot should be structurally valid"
  unless readyAction.mayExecute do
    throwError "ready workflow action should be executable"
  if blockedAction.mayExecute then
    throwError "blocked workflow action should not be executable"
