import Zil.Parser.DeclarationProgram
import Zil.TheoremAudit

namespace Zil.CLI

private def loadTheoremAuditProgram (inputPath : String) : IO Zil.Program := do
  let parsed ← Zil.Parser.DeclarationProgram.parseFile inputPath
  match parsed with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def writeTheoremAuditOutput
    (text : String)
    (outputPath : Option String) : IO Unit :=
  match outputPath with
  | none => IO.print text
  | some "-" => IO.print text
  | some path => IO.FS.writeFile path text

/-- Audit theorem contracts and external claims. Returns the pass decision. -/
def theoremAuditFile
    (inputPath : String)
    (outputPath : Option String := none) : IO Bool := do
  let program ← loadTheoremAuditProgram inputPath
  let report ← match Zil.TheoremAudit.audit program with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  writeTheoremAuditOutput (Zil.TheoremAudit.render report) outputPath
  pure report.ok

end Zil.CLI
