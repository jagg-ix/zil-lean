import Zil.Engine.Report
import Zil.Test.Environment.A

open Zil

private def target : RelExpr :=
  .mk' (.ground `claim.environmentPersistence) `zil.requiresClaim
    (.ground `requirement.persistence)

run_cmd do
  let env ← getEnv
  let report := Zil.Engine.reportCheck env target
  unless report.meta.knowledgeRevision > 0 do
    throwError "query report did not include a knowledge revision"
  unless report.meta.profileVersion == some "0.1" do
    throwError "query report did not expose the active profile version"
  unless report.meta.completeness == .complete do
    throwError "query report did not reach a complete fixpoint"

#guard Zil.Engine.knowledgeRevision (by exact (default : Lean.Environment)) == 0
