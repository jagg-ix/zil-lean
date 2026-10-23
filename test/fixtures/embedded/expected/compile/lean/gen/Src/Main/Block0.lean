import Zil.Core.Program
import Zil.Syntax.Environment

namespace Zil.Embedded.Src.Main.Block0

private def sourceTuple0 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Outer.Inner.identity)
      `zil.requires
      (.ground `assumption.natural_number) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 2 } }

private def sourceTuple1 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean_module.Src.Main)
      `zil.locatedIn
      (.ground `file) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 3 } }

private def sourceTuple2 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Outer.Inner.identity)
      `zil.in
      (.ground `namespace) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 4 } }

private def sourceTuple3 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `project.Src)
      `zil.owns
      (.ground `self) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 5 } }

private def sourceTuple4 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `sha256.n5923e3ba00d27dde181305b31e1c6d14fff731ba15837d1580fbf2452bd5a2d8)
      `zil.of
      (.ground `self) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 6 } }

private def sourceTuple5 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean4_kind.theorem)
      `zil.of
      (.ground `self) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 7 } }

private def sourceTuple6 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `source_span.Src.Main.lean.n4_18)
      `zil.of
      (.ground `self) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 8 } }

private def sourceTuple7 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Outer.Inner.identity)
      `zil.alias
      (.ground `my_self) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 9 } }

private def sourceTuple8 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Outer.Inner.identity)
      `zil.alias
      (.ground `self_two) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 10 } }

private def sourceTuple9 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Outer.Inner.identity)
      `zil.alias
      (.ground `a.self.b) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 11 } }

private def sourceTuple10 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Outer.Inner.identity)
      `zil.alias
      (.ground `a.self.b) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 12 } }

private def sourceTuple11 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Outer.Inner.identity)
      `zil.alias
      (.ground `a_self) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 13 } }

private def sourceTuple12 : Zil.TupleExpr :=
  { Zil.TupleExpr.direct
      (.ground `lean.Outer.Inner.identity)
      `zil.alias
      (.ground `file) with
    attrs := #[]
    source := { frontend := "zc", file := none, line := some 14 } }

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0,
  sourceTuple1,
  sourceTuple2,
  sourceTuple3,
  sourceTuple4,
  sourceTuple5,
  sourceTuple6,
  sourceTuple7,
  sourceTuple8,
  sourceTuple9,
  sourceTuple10,
  sourceTuple11,
  sourceTuple12
]

zil_register_tuple sourceTuple0
zil_register_tuple sourceTuple1
zil_register_tuple sourceTuple2
zil_register_tuple sourceTuple3
zil_register_tuple sourceTuple4
zil_register_tuple sourceTuple5
zil_register_tuple sourceTuple6
zil_register_tuple sourceTuple7
zil_register_tuple sourceTuple8
zil_register_tuple sourceTuple9
zil_register_tuple sourceTuple10
zil_register_tuple sourceTuple11
zil_register_tuple sourceTuple12

end Zil.Embedded.Src.Main.Block0

namespace Zil.Embedded.Src.Main.Block0

def sourceProgram : Zil.Program := {
  moduleName := some `embedded.block.embedded_2b0f3e9f619964b6
  tuples := sourceTuples
  rules := #[]
  queries := #[]
}

end Zil.Embedded.Src.Main.Block0
