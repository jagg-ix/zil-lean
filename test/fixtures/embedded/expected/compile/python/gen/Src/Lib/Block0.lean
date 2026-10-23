import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Lib.Block0

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `rust.run)
      `zil.kind
      (.ground `function) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Lib.Block0

namespace Zil.Embedded.Src.Lib.Block0

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_9271336f2f11905c
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Lib.Block0
