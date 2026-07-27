/-
Intentionally invalid acceptance fixture.

The file name advertises the Ryu--Takayanagi relation but the only theorem is
an elementary reassociation identity. Future lint must classify the theorem as
algebraic and reject it as the advertised physical formalization.
-/

namespace Zil.Acceptance.Bad

theorem divideByFourReassociate (a g : Nat) :
    a / (4 * g) = a / (4 * g) := by
  rfl

end Zil.Acceptance.Bad
