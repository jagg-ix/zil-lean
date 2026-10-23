module

public import Zil.Core.Relation

@[expose] public section

namespace Zil

/-- Raw identifier used by the `.zc` macro surface. It deliberately remains a
string: tuple names use Lean `Name` normalization, while macro identifiers are
case-sensitive source tokens and must not collapse `foo-bar` into `foo_bar`. -/
structure MacroIdent where
  raw : String
  deriving Repr, Inhabited, DecidableEq

namespace MacroIdent

def asciiLetter (char : Char) : Bool :=
  ('A' <= char && char <= 'Z') || ('a' <= char && char <= 'z')

def asciiDigit (char : Char) : Bool :=
  '0' <= char && char <= '9'

def validName (value : String) : Bool :=
  !value.isEmpty && value.toList.all fun char =>
    asciiLetter char || asciiDigit char || char == '_' || char == '.' || char == ':' || char == '-'

def validParameter (value : String) : Bool :=
  match value.toList with
  | [] => false
  | first :: rest =>
      (asciiLetter first || first == '_') &&
      rest.all fun char =>
        asciiLetter char || asciiDigit char || char == '_' || char == ':' || char == '-' || char == '.'

end MacroIdent

/-- One source-level ZIL macro definition. Macro bodies contain source statements
that are parsed only after parameter substitution. -/
structure MacroDef where
  name : Name
  parameters : Array Name := #[]
  emit : Array String := #[]
  source : Source := {}
  /-- Exact source spelling. Empty means the definition was constructed by an
  older Lean caller and should use `name` for its legacy identity. -/
  rawName : MacroIdent := ⟨""⟩
  /-- Exact parameter spellings, parallel to `parameters` for parsed source. -/
  rawParameters : Array MacroIdent := #[]
  deriving Repr, Inhabited

namespace MacroDef

def uniqueStrings (values : Array String) : Bool :=
  (values.foldl (init := (((#[] : Array String), true) : Array String × Bool)) fun state value =>
    if state.1.contains value then (state.1, false)
    else (state.1.push value, state.2)).2

def uniqueNames (names : Array Name) : Bool :=
  (names.foldl (init := (((#[] : Array Name), true) : Array Name × Bool)) fun state name =>
    if state.1.contains name then (state.1, false)
    else (state.1.push name, state.2)).2

def sourceName (definition : MacroDef) : String :=
  if definition.rawName.raw.isEmpty then toString definition.name else definition.rawName.raw

def sourceParameters (definition : MacroDef) : Array String :=
  if definition.rawName.raw.isEmpty then definition.parameters.map toString
  else definition.rawParameters.map (·.raw)

/-- Structural validity for a source macro. -/
def valid (definition : MacroDef) : Bool :=
  let sourceNamesValid :=
    if definition.rawName.raw.isEmpty then uniqueNames definition.parameters
    else MacroIdent.validName definition.rawName.raw &&
      definition.rawParameters.size == definition.parameters.size &&
      definition.rawParameters.all (fun parameter => MacroIdent.validParameter parameter.raw) &&
      uniqueStrings (definition.rawParameters.map (·.raw))
  !definition.emit.isEmpty && sourceNamesValid

end MacroDef

/-- One recorded macro use after positional substitution. -/
structure MacroExpansion where
  macroName : Name
  arguments : Array String := #[]
  emitted : Array String := #[]
  stack : Array Name := #[]
  source : Source := {}
  /-- Exact source spelling retained alongside the legacy normalized `Name`. -/
  rawName : String := ""
  deriving Repr, Inhabited

end Zil
