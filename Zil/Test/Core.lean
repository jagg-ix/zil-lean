import Zil

open Zil

namespace Zil.Test

private def legacyFormalizes : RelExpr :=
  relationExpr "?declaration" `formalizes "?claim"
    { frontend := "legacy-zc" }

private def nativeFormalizes : RelExpr :=
  relationExpr "?declaration" `formalizes "?claim"
    { frontend := "lean-native", line := some 42 }

#guard legacyFormalizes.semanticEq nativeFormalizes
#guard legacyFormalizes.relation == `zil.formalizes

private def requirementRule : Rule :=
  { name := `schwarzschildClaimRequirement
    variables := #[`claim, `requirement, `declaration]
    premises := #[
      relationExpr "?declaration" `formalizes "?claim",
      relationExpr "?declaration" `requires "?requirement"
    ]
    conclusion := relationExpr "?claim" `requires_claim "?requirement" }

#guard requirementRule.valid
#guard requirementRule.conclusion.relation == `zil.requiresClaim
#guard requirementRule.trust == .graph

private def badRule : Rule :=
  { name := `bad
    variables := #[`claim]
    premises := #[relationExpr "?declaration" `formalizes "?claim"]
    conclusion := relationExpr "?claim" `supportedBy "?source" }

#guard !badRule.valid

private def requirementQuery : Query :=
  { name := `requirementsForClaim
    variables := #[`claim, `requirement, `declaration]
    select := #[`requirement]
    premises := #[
      relationExpr "?declaration" `formalizes "?claim",
      relationExpr "?declaration" `requires "?requirement"
    ] }

#guard requirementQuery.valid

end Zil.Test
