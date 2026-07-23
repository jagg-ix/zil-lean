import Zil.Parser.DeclarationProgram
import Zil.TokenLifecycle

namespace Zil.CLI

private def loadTokenLifecycleProgram (inputPath : String) : IO Zil.Program := do
  let parsed ← Zil.Parser.DeclarationProgram.parseFile inputPath
  match parsed with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def writeTokenLifecycleOutput
    (text : String)
    (outputPath : Option String) : IO Unit :=
  match outputPath with
  | none => IO.print text
  | some "-" => IO.print text
  | some path => IO.FS.writeFile path text

private def lifecycleName (text : String) : IO Name :=
  match Zil.Parser.nameFromToken text with
  | .ok value => pure value
  | .error error => throw <| IO.userError error

/-- Replay one declared token lifecycle. -/
def tokenLifecycleFile
    (inputPath requestText : String)
    (outputPath : Option String := none) : IO Bool := do
  let program ← loadTokenLifecycleProgram inputPath
  let requestNode ← lifecycleName requestText
  let audit ← match Zil.TokenLifecycle.auditProgram program requestNode with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  writeTokenLifecycleOutput (Zil.TokenLifecycle.render audit) outputPath
  pure audit.ok

end Zil.CLI
