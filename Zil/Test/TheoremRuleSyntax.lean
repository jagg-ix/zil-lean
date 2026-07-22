import Zil.Syntax.TheoremRule

open Zil
open Zil.Syntax

zil_theorem_rule theoremShapedRequirement
  {claim requirement declaration : Zil.Node}
  (hFormalizes : declaration ⟶[formalizes] claim)
  (hRequires : declaration ⟶[requires] requirement)
  : claim ⟶[requiresClaim] requirement

#guard theoremShapedRequirement.variables == #[`claim, `requirement, `declaration]
#guard theoremShapedRequirement.premises.size == 2
#guard theoremShapedRequirement.allVariablesBound
#guard theoremShapedRequirement.conclusion.relation == `zil.requiresClaim
#guard theoremShapedRequirement.trust == .graphDerived
