import Zil
import Zil.Test.NativeSyntax
import Zil.Test.TypedProfiles
import Zil.Test.Environment.B
import Zil.Test.Environment.Diamond

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

#guard formalizes.isGround
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
  unless typedSchwarzschildRequirement.valid do
    throw <| IO.userError "typed relation profile validation failed"
  if invalidFormalizesRequirement.valid then
    throw <| IO.userError "typed relation profile accepted a category error"
  IO.println "zil-lean IR, syntax, profiles, and persistent environment validation passed"