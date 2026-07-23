import Zil.Parser.Program

namespace Zil.CLI

/-- Native command-line usage for source compilation. -/
def usage : String :=
  "zil compile <input.zc> [output.lean|-] [namespace]\n" ++
  "  parses MODULE, tuple facts, RULE blocks, and QUERY blocks\n" ++
  "  prints generated Lean when output is omitted or '-'"

private def namespaceFromArgument
    (program : Zil.Program) (value : Option String) : IO Name :=
  match value with
  | none => pure (Zil.Parser.Program.defaultNamespace program)
  | some text =>
      match Zil.Parser.nameFromToken text with
      | .ok name => pure name
      | .error error => throw <| IO.userError error

/-- Parse one `.zc` source file and emit a native ZIL Lean module. -/
def compileFile
    (inputPath : String)
    (outputPath : Option String := none)
    (namespaceText : Option String := none) : IO Unit := do
  let parsed ← Zil.Parser.Program.parseFile inputPath
  let program ← match parsed with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let namespaceName ← namespaceFromArgument program namespaceText
  let source ← match Zil.Parser.Program.renderLeanModule program namespaceName with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  match outputPath with
  | none => IO.print source
  | some "-" => IO.print source
  | some path => IO.FS.writeFile path source

end Zil.CLI

/-- Native ZIL command-line entry point. -/
def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["compile", input] =>
        Zil.CLI.compileFile input
        pure 0
    | ["compile", input, output] =>
        Zil.CLI.compileFile input (some output)
        pure 0
    | ["compile", input, output, namespaceName] =>
        Zil.CLI.compileFile input (some output) (some namespaceName)
        pure 0
    | _ =>
        IO.eprintln Zil.CLI.usage
        pure 2
  catch error =>
    IO.eprintln error.toString
    pure 1
