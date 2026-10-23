import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Pkg.Sub.B.Block0

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `rust.upper)
      `zil.kind
      (.ground `upper_extension) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Pkg.Sub.B.Block0

namespace Zil.Embedded.Src.Pkg.Sub.B.Block0

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_8f38e53b3f4335ee
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Pkg.Sub.B.Block0
