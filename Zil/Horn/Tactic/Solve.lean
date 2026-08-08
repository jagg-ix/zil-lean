module

public import Lean.Elab.Tactic
public import Zil.Horn.Certificate

@[expose] public section

namespace Zil.Horn

/-- Prove a concrete `HasSolution program goals limit` goal by evaluating the
bounded Horn resolver in native code. The proposition deliberately exposes the
bound, so tactic success never implies that an arbitrary recursive program
terminates. -/
macro "horn_solve" : tactic => `(tactic| (unfold HasSolution; native_decide))

/-- Prove bounded solvability only after independent proof-tree replay. Each
accepted answer is connected to `Entails` by `solveCertifiedDepth_entails`. -/
macro "horn_certify" : tactic =>
  `(tactic| (unfold HasCertifiedSolution; native_decide))

end Zil.Horn
