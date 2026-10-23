import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Pkg.A.Block1

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `python.second)
      `zil.kind
      (.ground `second) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Pkg.A.Block1

namespace Zil.Embedded.Src.Pkg.A.Block1

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_34615ef83f8849c8
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Pkg.A.Block1
