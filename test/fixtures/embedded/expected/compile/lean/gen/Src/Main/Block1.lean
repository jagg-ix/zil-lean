import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Main.Block1

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `custom.thing)
      `zil.kind
      (.ground `explicit) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Main.Block1

namespace Zil.Embedded.Src.Main.Block1

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_ec3e2b55c129c6ef
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Main.Block1
