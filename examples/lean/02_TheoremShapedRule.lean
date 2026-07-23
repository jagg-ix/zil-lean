import Zil

open Zil

/-!
# 2. A theorem-shaped graph rule

The syntax resembles a Lean theorem, but it creates a graph rule rather than a
kernel theorem. Each hypothesis becomes a premise and the final relation becomes
the rule conclusion.
-/

zil_theorem_rule propagateRequirement
  {declaration claim requirement : Zil.Node}
  (hFormalizes : declaration ⟶[formalizes] claim)
  (hRequires : declaration ⟶[requires] requirement)
  : claim ⟶[requiresClaim] requirement

#guard propagateRequirement.variables ==
  #[`declaration, `claim, `requirement]

#guard propagateRequirement.premises.size == 2
#guard propagateRequirement.conclusion.relation == `zil.requiresClaim
#guard propagateRequirement.trust == .graphDerived

run_cmd do
  logInfo m!"rule: {propagateRequirement.name}"
  logInfo m!"premises: {propagateRequirement.premises.size}"
  logInfo m!"trust: {repr propagateRequirement.trust}"
