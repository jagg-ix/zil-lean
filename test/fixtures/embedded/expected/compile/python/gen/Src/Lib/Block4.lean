import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Lib.Block4

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `rust.Shape)
      `zil.kind
      (.ground `trait) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Lib.Block4

namespace Zil.Embedded.Src.Lib.Block4

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_28c616cae8ffe165
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Lib.Block4
