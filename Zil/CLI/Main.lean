import Zil.Parser.DeclarationProgram
import Zil.Codec.Revision

namespace Zil.CLI

/-- Native command-line usage. -/
def usage : String :=
  "zil compile <input.zc> [output.lean|-] [namespace]\n" ++
  "zil expand <input.zc> [output.zc|-]\n" ++
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

/-- Parse one declaration-enabled `.zc` source file and emit a native ZIL Lean module. -/
def compileFile
    (inputPath : String)
    (outputPath : Option String := none)
    (namespaceText : Option String := none) : IO Unit := do
  let parsed ← Zil.Parser.DeclarationProgram.parseFile inputPath
  let program ← match parsed with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let namespaceName ← namespaceFromArgument program namespaceText
  let source ← match Zil.Parser.DeclarationProgram.renderLeanModule program namespaceName with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  match outputPath with
  | none => IO.print source
  | some "-" => IO.print source
  | some path => IO.FS.writeFile path source

/-- Expand source macros without compiling the resulting statements. -/
def expandFile
    (inputPath : String)
    (outputPath : Option String := none) : IO Unit := do
  let expanded ← Zil.Parser.MacroProgram.expandFile inputPath
  let source ← match expanded with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  match outputPath with
  | none => IO.print source
  | some "-" => IO.print source
  | some path => IO.FS.writeFile path source

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
  match outputPath with
  | none => IO.print text
  | some "-" => IO.print text
  | some output => IO.FS.writeFile output text

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
