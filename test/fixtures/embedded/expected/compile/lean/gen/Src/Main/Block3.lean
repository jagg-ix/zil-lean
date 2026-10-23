import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Main.Block3

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Standalone)
      `zil.kind
      (.ground `global) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Main.Block3

namespace Zil.Embedded.Src.Main.Block3

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_af08eb83ad60b9d1
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Main.Block3
