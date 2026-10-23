import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Tool.Block1

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `python.Runner)
      `zil.kind
      (.ground `class) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Tool.Block1

namespace Zil.Embedded.Src.Tool.Block1

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_5d9b02e38c81747b
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Tool.Block1
