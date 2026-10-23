import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Main.Block4

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Foo.Bar)
      `zil.kind
      (.ground `dotted) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0
]

zil_register_tuple sourceTuple0

end Zil.Embedded.Src.Main.Block4

namespace Zil.Embedded.Src.Main.Block4

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_66b08c4a302f0aad
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Main.Block4
