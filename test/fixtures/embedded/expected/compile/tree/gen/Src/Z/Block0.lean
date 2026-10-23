import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Z.Block0

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `z.last)
      `zil.kind
      (.ground `last) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Z.Block0

namespace Zil.Embedded.Src.Z.Block0

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_5dca010705de78d8
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Z.Block0
