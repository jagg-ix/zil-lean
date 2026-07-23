import Zil.Parser.DeclarationProgram
import Zil.Codec.Revision
import Zil.Codec.Conformance
import Zil.Formalization

namespace Zil.CLI

/-- Native command-line usage. -/
def usage : String :=
  "zil compile <input.zc> [output.lean|-] [namespace]\n" ++
  "zil expand <input.zc> [output.zc|-]\n" ++
  "zil conformance <input.zc> [output.zilc|-]\n" ++
  "zil formalization-plan <input.zc> [output.txt|-]\n" ++
  "zil formalization-next <input.zc> [output.txt|-]\n" ++
  "zil revision-summary <input.zilr>\n" ++
  "zil snapshot <input.zilr> <revision> [output.txt|-]\n" ++
  "zil causal-check <input.zilr>\n"

private def namespaceFromArgument
    (program : Zil.Program) (value : Option String) : IO Name :=
  match value with
  | none => pure (Zil.Parser.DeclarationProgram.defaultNamespace program)
  | some text =>
      match Zil.Parser.nameFromToken text with
      | .ok name => pure name
      | .error error => throw <| IO.userError error

private def parseNatIO (value message : String) : IO Nat :=
  match value.toNat? with
  | some number => pure number
  | none => throw <| IO.userError message

private def loadProgram (inputPath : String) : IO Zil.Program := do
  let parsed ← Zil.Parser.DeclarationProgram.parseFile inputPath
  match parsed with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def writeOutput (text : String) (outputPath : Option String) : IO Unit :=
  match outputPath with
  | none => IO.print text
  | some "-" => IO.print text
  | some path => IO.FS.writeFile path text

/-- Parse one declaration-enabled `.zc` source file and emit a native ZIL Lean module. -/
def compileFile
    (inputPath : String)
    (outputPath : Option String := none)
    (namespaceText : Option String := none) : IO Unit := do
  let program ← loadProgram inputPath
  let namespaceName ← namespaceFromArgument program namespaceText
  let source ← match Zil.Parser.DeclarationProgram.renderLeanModule program namespaceName with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  writeOutput source outputPath

/-- Expand source macros without compiling the resulting statements. -/
def expandFile
    (inputPath : String)
    (outputPath : Option String := none) : IO Unit := do
  let expanded ← Zil.Parser.MacroProgram.expandFile inputPath
  let source ← match expanded with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  writeOutput source outputPath

/-- Emit the deterministic semantic report consumed by the differential harness. -/
def conformanceFile
    (inputPath : String)
    (outputPath : Option String := none) : IO Unit := do
  let text ← IO.FS.readFile inputPath
  let report ← match Zil.Codec.Conformance.renderSource text with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  writeOutput report outputPath

/-- Emit all formalization scheduling decisions. -/
def formalizationPlanFile
    (inputPath : String)
    (outputPath : Option String := none) : IO Unit := do
  let program ← loadProgram inputPath
  let targets ← match Zil.Formalization.fromProgram program with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let report ← match Zil.Formalization.renderPlan targets with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  writeOutput report outputPath

/-- Emit the highest-priority ready formalization target. -/
def formalizationNextFile
    (inputPath : String)
    (outputPath : Option String := none) : IO Unit := do
  let program ← loadProgram inputPath
  let targets ← match Zil.Formalization.fromProgram program with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let report ← match Zil.Formalization.renderNext targets with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  writeOutput report outputPath

private def loadRevisionStore (path : String) : IO Zil.RevisionStore := do
  let text ← IO.FS.readFile path
  match Zil.Codec.Revision.decodeStore text with
  | .ok store => pure store
  | .error error => throw <| IO.userError error

/-- Print deterministic revision and causal counts. -/
def revisionSummary (path : String) : IO Unit := do
  let store ← loadRevisionStore path
  IO.println s!"module: {store.moduleName}"
  IO.println s!"latest-revision: {store.latestRevision}"
  IO.println s!"records: {store.records.size}"
  IO.println s!"events: {store.causal.events.size}"
  IO.println s!"causal-edges: {store.causal.edges.size}"

/-- Materialize and emit one revision snapshot as canonical relation rows. -/
def snapshotFile
    (path : String)
    (frontier : Nat)
    (outputPath : Option String := none) : IO Unit := do
  let store ← loadRevisionStore path
  let facts ← match store.snapshotAt frontier with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  let text := String.intercalate "\n" (facts.toList.map Zil.Codec.encodeRelation) ++
    (if facts.isEmpty then "" else "\n")
  writeOutput text outputPath

/-- Validate the strict causal graph contained in a revision envelope. -/
def causalCheck (path : String) : IO Unit := do
  let store ← loadRevisionStore path
  if store.causal.valid then IO.println "valid" else throw <| IO.userError "invalid causal graph"

end Zil.CLI

/-- Native ZIL command-line entry point. -/
def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["compile", input] => Zil.CLI.compileFile input; pure 0
    | ["compile", input, output] => Zil.CLI.compileFile input (some output); pure 0
    | ["compile", input, output, namespaceName] =>
        Zil.CLI.compileFile input (some output) (some namespaceName); pure 0
    | ["expand", input] => Zil.CLI.expandFile input; pure 0
    | ["expand", input, output] => Zil.CLI.expandFile input (some output); pure 0
    | ["conformance", input] => Zil.CLI.conformanceFile input; pure 0
    | ["conformance", input, output] => Zil.CLI.conformanceFile input (some output); pure 0
    | ["formalization-plan", input] => Zil.CLI.formalizationPlanFile input; pure 0
    | ["formalization-plan", input, output] =>
        Zil.CLI.formalizationPlanFile input (some output); pure 0
    | ["formalization-next", input] => Zil.CLI.formalizationNextFile input; pure 0
    | ["formalization-next", input, output] =>
        Zil.CLI.formalizationNextFile input (some output); pure 0
    | ["revision-summary", input] => Zil.CLI.revisionSummary input; pure 0
    | ["snapshot", input, revision] =>
        let frontier ← Zil.CLI.parseNatIO revision "invalid snapshot revision"
        Zil.CLI.snapshotFile input frontier; pure 0
    | ["snapshot", input, revision, output] =>
        let frontier ← Zil.CLI.parseNatIO revision "invalid snapshot revision"
        Zil.CLI.snapshotFile input frontier (some output); pure 0
    | ["causal-check", input] => Zil.CLI.causalCheck input; pure 0
    | _ => IO.eprintln Zil.CLI.usage; pure 2
  catch error =>
    IO.eprintln error.toString
    pure 1
