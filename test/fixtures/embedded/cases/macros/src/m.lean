/-
@zil target=self
USE FORMAL_CLAIM(self, claim:embedded_identity).
USE OWNED(self, project).
self#requires@assumption:natural_number.
@endzil
-/
theorem Macro.identity (n : Nat) : n = n := rfl
