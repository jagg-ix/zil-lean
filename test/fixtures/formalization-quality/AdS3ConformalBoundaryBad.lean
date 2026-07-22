/-
Intentionally invalid acceptance fixture.

The file name advertises an AdS3 conformal-boundary formalization, but this
fixture only proves a fact about an interval. Future formalization lint must
reject it as a misleading scope match even though Lean can compile it.
-/

namespace Zil.Acceptance.Bad

def unitInterval (x : Nat) : Prop := x ≤ 1

theorem unitInterval_zero : unitInterval 0 := by
  decide

end Zil.Acceptance.Bad
