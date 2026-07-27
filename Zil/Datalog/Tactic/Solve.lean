module

public import Lean.Elab.Tactic
public import Zil.Datalog.Semantics

@[expose] public section

namespace Zil.Datalog

/--
Close a `Holds program atom` goal using the frozen program and the certified
bounded evaluator. The default fuel is deliberately explicit and local: the
tactic performs no I/O and never consults mutable or network state.
-/
macro "zil_solve" : tactic =>
  `(tactic|
    exact holds_of_deriveProgram_mem (fuel := 32) (by native_decide))

end Zil.Datalog
