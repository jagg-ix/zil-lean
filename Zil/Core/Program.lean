import Zil.Core.Userset
import Zil.Core.Query
import Zil.Core.Macro

namespace Zil

/-- Native representation of one parsed ZIL source unit. -/
structure Program where
  moduleName : Option Name := none
  tuples : Array TupleExpr := #[]
  rules : Array Rule := #[]
  queries : Array Query := #[]
  macros : Array MacroDef := #[]
  expansions : Array MacroExpansion := #[]
  deriving Repr, Inhabited

namespace Program

/-- View the tuple portion through the existing lossless tuple API. -/
def tupleProgram (program : Program) : TupleProgram :=
  { moduleName := program.moduleName, tuples := program.tuples }

/-- Base facts emitted by source tuples. -/
def facts (program : Program) : Array RelExpr :=
  program.tupleProgram.lower.facts

/-- Source rules plus userset traversal rules emitted by tuple lowering. -/
def allRules (program : Program) : Array Rule :=
  program.tupleProgram.lower.rules ++ program.rules

/-- Structural safety for macros, rules, and queries before stratification. -/
def valid (program : Program) : Bool :=
  program.macros.all MacroDef.valid &&
  program.allRules.all (fun rule => rule.allVariablesBound && rule.safe) &&
  program.queries.all (fun query => query.selectedVariablesBound && query.safe)

end Program

end Zil
