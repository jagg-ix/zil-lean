import Zil.Syntax.Recovery
import Zil.Test.Contracts

zil_checkpoint recoveryBaseline

run_cmd do
  let env ← getEnv
  let token := Zil.Recovery.capture env (some `contract.environmentPersistence)
    (some `recoveryBaseline)
  unless Zil.Recovery.mutationAllowed env token do
    throwError "fresh context with checkpoint was rejected"
  let stale := { token with knowledgeRevision := token.knowledgeRevision + 1 }
  unless (Zil.Recovery.validateMutation env stale).any
      (fun issue => issue.kind == .staleKnowledgeRevision) do
    throwError "stale knowledge revision was not rejected"
  let mismatch := { token with theoremIntentMismatchResolved := false }
  unless (Zil.Recovery.validateMutation env mismatch).any
      (fun issue => issue.kind == .unresolvedTheoremIntentMismatch) do
    throwError "unresolved theorem-intent mismatch was not rejected"
  let noCheckpoint := { token with checkpoint := none }
  unless (Zil.Recovery.validateMutation env noCheckpoint).any
      (fun issue => issue.kind == .missingRollbackCheckpoint) do
    throwError "missing rollback checkpoint was not rejected"
