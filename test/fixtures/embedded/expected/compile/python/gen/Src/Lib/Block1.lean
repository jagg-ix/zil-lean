import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Lib.Block1

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `rust.Config)
      `zil.kind
      (.ground `struct) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Lib.Block1

namespace Zil.Embedded.Src.Lib.Block1

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_2e2367ef39b3288a
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Lib.Block1
