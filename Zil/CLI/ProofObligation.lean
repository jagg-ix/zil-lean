import Zil.Parser.DeclarationProgram
import Zil.ProofObligation

namespace Zil.CLI

private def loadProofProgram (inputPath : String) : IO Zil.Program := do
  let parsed ← Zil.Parser.DeclarationProgram.parseFile inputPath
  match parsed with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def writeProofOutput
    (text : String)
    (outputPath : Option String) : IO Unit :=
  match outputPath with
  | none => IO.print text
  | some "-" => IO.print text
  | some path => IO.FS.writeFile path text

private def proofTool (text : String) : IO (Option Zil.ProofObligation.Tool) :=
  if text == "-" || text == "all" then pure none
  else
    match Zil.ProofObligation.Tool.ofToken? text with
    | some tool => pure (some tool)
    | none => throw <| IO.userError s!"unknown proof tool {text}"

/-- Audit native proof-obligation declarations. Returns the pass decision. -/
def proofObligationsFile
    (inputPath : String)
    (toolText : String := "-")
    (outputPath : Option String := none) : IO Bool := do
  let program ← loadProofProgram inputPath
  let tool ← proofTool toolText
  let report ← match Zil.ProofObligation.audit program tool with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  writeProofOutput (Zil.ProofObligation.render report) outputPath
  pure report.ok

end Zil.CLI
