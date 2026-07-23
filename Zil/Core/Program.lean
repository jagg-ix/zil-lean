import Zil.Core.Userset
import Zil.Core.Query

namespace Zil

/-- Native representation of one parsed ZIL source unit. -/
structure Program where
  moduleName : Option Name := none
  tuples : Array TupleExpr := #[]
  rules : Array Rule := #[]
  queries : Array Query := #[]
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

/-- Basic structural validation for parsed programs. -/
def valid (program : Program) : Bool :=
  program.rules.all Rule.allVariablesBound &&
  program.queries.all Query.selectedVariablesBound

end Program

end Zil
