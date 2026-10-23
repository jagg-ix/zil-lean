import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Main.Block2

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Outer.Point)
      `zil.kind
      (.ground `structure) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Main.Block2

namespace Zil.Embedded.Src.Main.Block2

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_488139b59bbde42c
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Main.Block2
