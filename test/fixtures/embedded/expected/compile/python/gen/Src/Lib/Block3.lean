import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Lib.Block3

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `rust.Mode)
      `zil.kind
      (.ground `enum) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Lib.Block3

namespace Zil.Embedded.Src.Lib.Block3

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_8157e078bda5f73b
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Lib.Block3
