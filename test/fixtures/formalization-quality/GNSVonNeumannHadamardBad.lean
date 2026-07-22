/-
Intentionally invalid acceptance fixture.

The file name advertises GNS, von Neumann algebra, and Hadamard-state
formalization, while the fixture contains no corresponding structures. Future
formalization lint must reject it despite successful Lean compilation.
-/

namespace Zil.Acceptance.Bad

theorem nonnegativeSquare (n : Nat) : 0 ≤ n * n := by
  exact Nat.zero_le _

end Zil.Acceptance.Bad
