import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Pkg.A.Block0

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `python.first)
      `zil.kind
      (.ground `first) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Pkg.A.Block0

namespace Zil.Embedded.Src.Pkg.A.Block0

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_83f5065c737514ca
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Pkg.A.Block0
