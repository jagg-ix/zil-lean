import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Tool.Block2

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `python.fetch)
      `zil.kind
      (.ground `async) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Tool.Block2

namespace Zil.Embedded.Src.Tool.Block2

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_233fec1e6c4e4291
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Tool.Block2
