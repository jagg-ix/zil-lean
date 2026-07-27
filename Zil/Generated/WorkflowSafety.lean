-- Generated from a frozen SQLite workflow snapshot. Do not edit.
import Zil.Workflow

namespace Zil.Generated.WorkflowSafety

open Zil.Workflow

def snapshot : Snapshot := {
  revision := "sha256:8839f05305f724eb8987a329258e8c5df72a29151138870a90a43cad2f3094a8"
  complete := true
  actions := [{ actionId := "action:dependency-maintenance", agentId := "agent:workflow-demo", moduleName := "Zil.Generated.DependencyAvailability", baseRevision := "sha256:8839f05305f724eb8987a329258e8c5df72a29151138870a90a43cad2f3094a8", currentRevision := "sha256:8839f05305f724eb8987a329258e8c5df72a29151138870a90a43cad2f3094a8", contextFresh := true, contextComplete := true, noConflict := true, authorized := true, validLease := true, checkpointExists := true, preconditionsPass := true, recoveryAvailable := true }]
}

example : MayExecute snapshot.actions[0]! := by native_decide

end Zil.Generated.WorkflowSafety
