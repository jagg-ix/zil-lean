module

public import Lean.Elab.Tactic
public import Zil.Datalog.Semantics
public import Zil.Datalog.Checked

@[expose] public section

namespace Zil.Datalog

/--
Close a `Holds program atom` goal using the frozen program and the checked
evaluator (`holdsChecked`), which stops at the fixpoint, so a derivation of any
length is found. The tactic performs no I/O and never consults mutable or
network state.
-/
macro "zil_solve" : tactic =>
  `(tactic| exact holds_of_checked (fuel := defaultFuel) (by native_decide))

/--
Close a `¬ Holds program atom` goal for a program without negation: the checked
evaluator reaches its fixpoint and the atom is not in it (`not_holds_of_checked`).
-/
macro "zil_refute" : tactic =>
  `(tactic| exact not_holds_of_checked (fuel := defaultFuel) (by native_decide) (by native_decide))

end Zil.Datalog
