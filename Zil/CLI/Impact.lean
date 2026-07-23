import Zil.Parser.DeclarationProgram
import Zil.Impact

namespace Zil.CLI

private def loadImpactProgram (inputPath : String) : IO Zil.Program := do
  let parsed ← Zil.Parser.DeclarationProgram.parseFile inputPath
  match parsed with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def writeImpactOutput
    (text : String)
    (outputPath : Option String) : IO Unit :=
  match outputPath with
  | none => IO.print text
  | some "-" => IO.print text
  | some path => IO.FS.writeFile path text

private def impactNameFromArgument (value : String) : IO Name :=
  match Zil.Parser.nameFromToken value with
  | .ok name => pure name
  | .error error => throw <| IO.userError error

/-- Emit the dependency graph extracted from checked closure provenance. -/
def dependencyGraphFile
    (inputPath : String)
    (outputPath : Option String := none) : IO Unit := do
  let program ← loadImpactProgram inputPath
  let graph ← match Zil.Impact.fromProgram program with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  writeImpactOutput (Zil.Impact.renderGraph graph) outputPath

/-- Emit reverse change impact. Returns whether the changed node is known. -/
def changeImpactFile
    (inputPath changedText : String)
    (outputPath : Option String := none) : IO Bool := do
  let program ← loadImpactProgram inputPath
  let changed ← impactNameFromArgument changedText
  let graph ← match Zil.Impact.fromProgram program with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let report := Zil.Impact.analyze graph changed
  writeImpactOutput (Zil.Impact.renderImpact report) outputPath
  pure report.known

end Zil.CLI
