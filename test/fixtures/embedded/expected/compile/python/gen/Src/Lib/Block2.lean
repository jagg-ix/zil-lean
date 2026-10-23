import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Lib.Block2

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `rust.serve)
      `zil.kind
      (.ground `async) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Lib.Block2

namespace Zil.Embedded.Src.Lib.Block2

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_0d4b92c637acb021
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Lib.Block2
