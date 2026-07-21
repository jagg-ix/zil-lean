/-
Reverse direction: ZIL annotations embedded in ordinary Lean4 source.
The scanner reads the comment block without touching the code:

  ./bin/zil embedded-scan examples/lean4-integration /tmp/annotated.zc lean4.integration.annotated

Output is canonical `.zc` with the claim link attached to the first
declaration after the block (`lean:AnnotatedExample.add_comm`), plus source
hashes, line spans, and `trust:asserted_annotation`.
-/

/-
@zil target=self
self#formalizes@claim:addition_commutative.
self#requires@assumption:natural_number_axioms.
@endzil
-/
theorem AnnotatedExample.add_comm (m n : Nat) : m + n = n + m :=
  Nat.add_comm m n
