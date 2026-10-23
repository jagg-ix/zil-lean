import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.M.Block0

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Macro.identity)
      `zil.formalizes
      (.ground `claim.embedded_identity) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

private def sourceTuple1 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `claim.embedded_identity)
      `zil.formalizedBy
      (.ground `lean.Macro.identity) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 3 } }

private def sourceTuple2 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Macro.identity)
      `zil.ownedBy
      (.ground `project.Src) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 4 } }

private def sourceTuple3 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Macro.identity)
      `zil.requires
      (.ground `assumption.natural_number) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 5 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0,
  sourceTuple1,
  sourceTuple2,
  sourceTuple3
]

zil_register_tuple sourceTuple0
zil_register_tuple sourceTuple1
zil_register_tuple sourceTuple2
zil_register_tuple sourceTuple3

end Zil.Embedded.Src.M.Block0

namespace Zil.Embedded.Src.M.Block0

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_632cf81ac9bab1d2
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.M.Block0
