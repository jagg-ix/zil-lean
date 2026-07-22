import Zil
import Zil.Test.NativeSyntax
import Zil.Test.TheoremRuleSyntax
import Zil.Test.TypedProfiles
import Zil.Test.Environment.B
import Zil.Test.Environment.Diamond
import Zil.Test.QueryEngine
import Zil.Test.QueryReports
import Zil.Test.Lint.Good
import Zil.Test.Lint.Incomplete
import Zil.Test.Contracts
import Zil.Test.Recovery
import Zil.Test.CanonicalCodec

open Zil

private def declaration : Term := .ground `lean.Schwarzschild.metric
private def claim : Term := .ground `claim.schwarzschildMetric
private def requirement : Term := .ground `requirement.lorentzianMetric

private def formalizes : RelExpr := .mk' declaration `zil.formalizes claim
private def requires : RelExpr := .mk' declaration `zil.requires requirement
private def requiresClaim : RelExpr := .mk' claim `zil.requiresClaim requirement

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

#guard formalizes.semanticallyEqual { formalizes with source := { frontend := "embedded", line := some 12 } }
#guard formalizes.isGround
#guard transferRule.allVariablesBound
#guard requirementQuery.selectedVariablesBound

/-- Executable smoke target used by `lake exe zilLeanTests`. -/
def main : IO Unit := do
  unless theoremShapedRequirement.allVariablesBound do
    throw <| IO.userError "theorem-shaped rule validation failed"
  unless typedSchwarzschildRequirement.valid do
    throw <| IO.userError "typed relation profile validation failed"
  IO.println "zil-lean canonical codec and theorem-shaped syntax validation passed"
