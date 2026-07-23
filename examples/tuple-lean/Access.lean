/-
Generated from original ZIL tuple syntax.
Source: examples/tuple-lean/access.zc
-/

import Zil

namespace Zil.Generated.Access

/- Lossless original tuple values -/

private def sourceTuple0 : Zil.TupleExpr :=
  Zil.TupleExpr.direct
    (.ground `doc.readme)
    `zil.owner
    (.ground `user.u10)

private def sourceTuple1 : Zil.TupleExpr :=
  Zil.TupleExpr.direct
    (.ground `group.eng)
    `zil.member
    (.ground `user.u11)

private def sourceTuple2 : Zil.TupleExpr :=
  Zil.TupleExpr.withUserset
    (.ground `doc.readme)
    `zil.viewer
    ⟨`group.eng⟩
    `zil.member

private def sourceTuple3 : Zil.TupleExpr :=
  Zil.TupleExpr.direct
    (.ground `doc.readme)
    `zil.parent
    (.ground `folder.A)

def sourceTuples : Array Zil.TupleExpr := #[
  sourceTuple0,
  sourceTuple1,
  sourceTuple2,
  sourceTuple3
]

#guard sourceTuples.size == 4
#guard Zil.Codec.tupleRoundTrips sourceTuple2

/- Lowered facts for the current Horn engine -/

zil_fact
  node(doc.readme)
    ⟶[owner]
  node(user.u10)

zil_fact
  node(group.eng)
    ⟶[member]
  node(user.u11)

-- Source userset: group:eng#member (follow relation `member`)
zil_fact
  node(doc.readme)
    ⟶[viewer]
  node(group.eng)

zil_fact
  node(doc.readme)
    ⟶[parent]
  node(folder.A)

/- Userset expansion rules -/

zil_theorem_rule viewerViaMember
  {object userset subject : Zil.Node}
  (hOuter : object ⟶[viewer] userset)
  (hInner : userset ⟶[member] subject)
  : object ⟶[viewer] subject

end Zil.Generated.Access
