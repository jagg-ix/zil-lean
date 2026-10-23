import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Tool.Block0

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `python.run)
      `zil.kind
      (.ground `function) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

private def sourceTuple1 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `python.run)
      `zil.in
      (.ground `module) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 3 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0,
  sourceTuple1
]

zil_register_tuple sourceTuple0
zil_register_tuple sourceTuple1

end Zil.Embedded.Src.Tool.Block0

namespace Zil.Embedded.Src.Tool.Block0

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_b45050fe0a4d2882
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Tool.Block0
