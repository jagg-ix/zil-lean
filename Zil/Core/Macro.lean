import Zil.Core.Relation

namespace Zil

/-- One source-level ZIL macro definition. Macro bodies contain source statements
that are parsed only after parameter substitution. -/
structure MacroDef where
  name : Name
  parameters : Array Name := #[]
  emit : Array String := #[]
  source : Source := {}
  deriving Repr, Inhabited

namespace MacroDef

private def uniqueNames (names : Array Name) : Bool :=
  names.foldl (init := (#[], true)) (fun state name =>
    if state.1.contains name then (state.1, false)
    else (state.1.push name, state.2)).2

/-- Structural validity for a source macro. -/
def valid (definition : MacroDef) : Bool :=
  !definition.emit.isEmpty && uniqueNames definition.parameters

end MacroDef

/-- One recorded macro use after positional substitution. -/
structure MacroExpansion where
  macroName : Name
  arguments : Array String := #[]
  emitted : Array String := #[]
  stack : Array Name := #[]
  source : Source := {}
  deriving Repr, Inhabited

end Zil
