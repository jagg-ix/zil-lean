import Zil.Parser.Program
import Zil.Parser.Macro

namespace Zil.Parser.MacroProgram

/-- One ordered macro-library source. File discovery and sorting may happen in a
caller, while composition and parsing remain native. -/
structure LibrarySource where
  label : String
  text : String
  deriving Repr, Inhabited

private def renderBlock (label text : String) : String :=
  "// ---- begin " ++ label ++ " ----\n" ++
  text ++ (if text.endsWith "\n" then "" else "\n") ++
  "// ---- end " ++ label ++ " ----\n"

/-- Compose ordered extension libraries before one model source. This mirrors
`zil.preprocess/preprocess-model`: callers provide deterministically sorted,
non-recursive `lib/*.zc` sources and the model is appended last. -/
def composeLibraries
    (libraries : Array LibrarySource)
    (modelLabel modelText : String) : String :=
  let libraryText := String.intercalate "\n" <|
    libraries.toList.map fun source => renderBlock source.label source.text
  let modelBlock := renderBlock modelLabel modelText
  if libraryText.isEmpty then modelBlock else libraryText ++ "\n" ++ modelBlock

/-- Parse a complete ZIL source unit after collecting and expanding source macros. -/
def parseText (text : String) (limit : Nat := 10000) : Except ParseError Zil.Program := do
  let preprocessed ← Zil.Parser.Macro.preprocess text limit
  let program ← Zil.Parser.Program.parseText (Zil.Parser.Macro.renderExpanded preprocessed)
  pure {
    program with
    macros := preprocessed.macros
    expansions := preprocessed.expansions
  }

/-- Parse a model with ordered macro-library sources prepended. -/
def parseTextWithLibraries
    (libraries : Array LibrarySource)
    (modelLabel modelText : String)
    (limit : Nat := 10000) : Except ParseError Zil.Program :=
  parseText (composeLibraries libraries modelLabel modelText) limit

/-- Read and parse one macro-enabled `.zc` source file. -/
def parseFile (path : String) (limit : Nat := 10000) : IO (Except ParseError Zil.Program) := do
  let text ← IO.FS.readFile path
  pure (parseText text limit)

/-- Return only the fully expanded source statements. -/
def expandText (text : String) (limit : Nat := 10000) : Except ParseError String := do
  pure <| Zil.Parser.Macro.renderExpanded (← Zil.Parser.Macro.preprocess text limit)

/-- Expand a model with ordered macro-library sources prepended. -/
def expandTextWithLibraries
    (libraries : Array LibrarySource)
    (modelLabel modelText : String)
    (limit : Nat := 10000) : Except ParseError String :=
  expandText (composeLibraries libraries modelLabel modelText) limit

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
