import Zil
import Zil.Test.NativeSyntax

open Zil

private def declaration : Term := .ground `lean.Schwarzschild.metric
private def claim : Term := .ground `claim.schwarzschildMetric
private def requirement : Term := .ground `requirement.lorentzianMetric

private def formalizes : RelExpr :=
  .mk' declaration `zil.formalizes claim

private def requires : RelExpr :=
  .mk' declaration `zil.requires requirement

private def requiresClaim : RelExpr :=
  .mk' claim `zil.requiresClaim requirement

private def transferRule : Rule :=
  { name := `schwarzschildClaimRequirement
    variables := #[]
    premises := #[formalizes, requires]
    conclusion := requiresClaim
    trust := .graphDerived }

private def requirementQuery : Query :=
  { name := `schwarzschildRequirements
    variables := #[`requirement]
    select := #[`requirement]
    premises := #[requires] }

#guard formalizes.semanticallyEqual
  { formalizes with source := { frontend := "embedded", line := some 12 } }

#guard transferRule.conclusionVariablesBound
#guard transferRule.allVariablesBound
#guard requirementQuery.selectedVariablesBound
#guard !(Query.selectedVariablesBound
  { requirementQuery with select := #[`undeclared] })

/-- Executable smoke target used by `lake exe zilLeanTests`. -/
def main : IO Unit := do
  unless formalizes.semanticallyEqual formalizes do
    throw <| IO.userError "relation semantic equality failed"
  unless transferRule.allVariablesBound do
    throw <| IO.userError "rule binding validation failed"
  unless requirementQuery.selectedVariablesBound do
    throw <| IO.userError "query binding validation failed"
  unless schwarzschildClaimRequirement.allVariablesBound do
    throw <| IO.userError "native zil_rule validation failed"
  IO.println "zil-lean core IR and native syntax validation passed"
