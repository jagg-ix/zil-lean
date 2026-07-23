/-
Generated from original ZIL tuple syntax.
Source: examples/tuple-lean/access.zc
-/

import Zil

namespace Zil.Generated.Access

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
