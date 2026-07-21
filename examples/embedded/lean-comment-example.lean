/-
@zil target=self
USE FORMAL_CLAIM(self, claim:embedded_identity).
self#requires@assumption:natural_number.
@endzil
-/
theorem EmbeddedExample.identity (n : Nat) : n = n := by
  rfl
