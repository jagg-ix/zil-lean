import Zil.Parser.Program
import Zil.Parser.Macro

namespace Zil.Parser.MacroProgram

/-- Parse a complete ZIL source unit after collecting and expanding source macros. -/
def parseText (text : String) (limit : Nat := 10000) : Except ParseError Zil.Program := do
  let preprocessed ← Zil.Parser.Macro.preprocess text limit
  let program ← Zil.Parser.Program.parseText (Zil.Parser.Macro.renderExpanded preprocessed)
  pure {
    program with
    macros := preprocessed.macros
    expansions := preprocessed.expansions
  }

/-- Read and parse one macro-enabled `.zc` source file. -/
def parseFile (path : String) (limit : Nat := 10000) : IO (Except ParseError Zil.Program) := do
  let text ← IO.FS.readFile path
  pure (parseText text limit)

/-- Return only the fully expanded source statements. -/
def expandText (text : String) (limit : Nat := 10000) : Except ParseError String := do
  pure <| Zil.Parser.Macro.renderExpanded (← Zil.Parser.Macro.preprocess text limit)

/-- Read one source file and return its fully expanded source statements. -/
def expandFile (path : String) (limit : Nat := 10000) : IO (Except ParseError String) := do
  let text ← IO.FS.readFile path
  pure (expandText text limit)

/-- The ordinary Lean renderer consumes the expanded semantic program. Macro
metadata remains available on the returned `Zil.Program` for tools and reports. -/
def renderLeanModule (program : Zil.Program) (namespaceName : Name) : Except String String :=
  Zil.Parser.Program.renderLeanModule program namespaceName

/-- Namespace derived from the parsed source module. -/
def defaultNamespace (program : Zil.Program) : Name :=
  Zil.Parser.Program.defaultNamespace program

end Zil.Parser.MacroProgram
