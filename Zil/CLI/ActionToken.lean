import Zil.Parser.DeclarationProgram
import Zil.ActionToken

namespace Zil.CLI

private def loadActionTokenProgram (inputPath : String) : IO Zil.Program := do
  let parsed ← Zil.Parser.DeclarationProgram.parseFile inputPath
  match parsed with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def writeActionTokenOutput
    (text : String)
    (outputPath : Option String) : IO Unit :=
  match outputPath with
  | none => IO.print text
  | some "-" => IO.print text
  | some path => IO.FS.writeFile path text

private def actionTokenName (text : String) : IO Name :=
  match Zil.Parser.nameFromToken text with
  | .ok value => pure value
  | .error error => throw <| IO.userError error

/-- Evaluate one attributed action-token request. -/
def actionTokenFile
    (inputPath requestText : String)
    (outputPath : Option String := none) : IO Bool := do
  let program ← loadActionTokenProgram inputPath
  let requestNode ← actionTokenName requestText
  let request ← match Zil.ActionToken.fromProgram program requestNode with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let decision := Zil.ActionToken.issue request
  writeActionTokenOutput (Zil.ActionToken.render requestNode decision) outputPath
  pure decision.allowed

end Zil.CLI
