import Zil.Parser.DeclarationProgram
import Zil.RecoveryAudit

namespace Zil.CLI

private def loadRecoveryAuditProgram (inputPath : String) : IO Zil.Program := do
  let parsed ← Zil.Parser.DeclarationProgram.parseFile inputPath
  match parsed with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def writeRecoveryAuditOutput
    (text : String)
    (outputPath : Option String) : IO Unit :=
  match outputPath with
  | none => IO.print text
  | some "-" => IO.print text
  | some path => IO.FS.writeFile path text

private def recoveryAuditName (text : String) : IO Name :=
  match Zil.Parser.nameFromToken text with
  | .ok value => pure value
  | .error error => throw <| IO.userError error

/-- Audit one consumed action, its required postconditions, and any recovery event. -/
def recoveryAuditFile
    (inputPath requestText : String)
    (outputPath : Option String := none) : IO Bool := do
  let program ← loadRecoveryAuditProgram inputPath
  let requestNode ← recoveryAuditName requestText
  let audit ← match Zil.RecoveryAudit.auditProgram program requestNode with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  writeRecoveryAuditOutput (Zil.RecoveryAudit.render audit) outputPath
  pure audit.safe

end Zil.CLI
