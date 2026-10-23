/-
Reverse direction: ZIL annotations embedded in ordinary Lean4 source.
A scanner read the comment block without touching the code and emitted canonical
`.zc` with the claim link attached to the first declaration after the block
(`lean:AnnotatedExample.add_comm`), plus source hashes, line spans, and
`trust:asserted_annotation`. That scanner was removed with the Clojure runtime
(spec/clojure-removal.md); the annotation format is kept as documentation.
-/

/-
@zil target=self
self#formalizes@claim:addition_commutative.
self#requires@assumption:natural_number_axioms.
@endzil
-/
theorem AnnotatedExample.add_comm (m n : Nat) : m + n = n + m :=
  Nat.add_comm m n
