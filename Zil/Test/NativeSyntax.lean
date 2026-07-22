import Zil.Syntax.Rule

open Zil
open Zil.Syntax

zil_rule schwarzschildClaimRequirement where
  variables claim requirement declaration
  premises
    declaration ⟶[formalizes] claim
    declaration ⟶[requires] requirement
  conclusion
    claim ⟶[requiresClaim] requirement

zil_rule schwarzschildClaimEvidence where
  variables claim source declaration
  premises
    declaration ⟶[formalizes] claim
    declaration ⟶[supportedBy] source
  conclusion
    claim ⟶[supportedBy] source

zil_rule groundClaimEvidence where
  variables declaration
  premises
    declaration ⟶[formalizes] node(claim.schwarzschildMetric)
    declaration ⟶[supportedBy] node(paper.schwarzschild1916)
  conclusion
    node(claim.schwarzschildMetric) ⟶[supportedBy] node(paper.schwarzschild1916)

private def unboundPremiseRule : Rule :=
  { name := `unboundPremiseRule
    variables := #[`claim]
    premises := #[RelExpr.mk' (Term.variable `declaration) `zil.formalizes
      (Term.variable `claim)]
    conclusion := RelExpr.mk' (Term.variable `claim) `zil.status
      (Term.ground `status.proposed) }

#guard schwarzschildClaimRequirement.variables ==
  #[`claim, `requirement, `declaration]
#guard schwarzschildClaimRequirement.premises.size == 2
#guard schwarzschildClaimRequirement.conclusionVariablesBound
#guard schwarzschildClaimRequirement.allVariablesBound
#guard schwarzschildClaimEvidence.allVariablesBound
#guard groundClaimEvidence.allVariablesBound
#guard !unboundPremiseRule.allVariablesBound
#guard schwarzschildClaimRequirement.trust == .graphDerived
#guard schwarzschildClaimRequirement.conclusion.relation == `zil.requiresClaim
#guard groundClaimEvidence.conclusion.subject ==
  Term.ground `claim.schwarzschildMetric
