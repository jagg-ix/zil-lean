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
import Zil.Test.CertifiedRules
import Zil.Test.Exchange
import Zil.Test.Delta

open Zil

private def declaration : Term := .ground `lean.Schwarzschild.metric
private def claim : Term := .ground `claim.schwarzschildMetric
private def formalizes : RelExpr := .mk' declaration `zil.formalizes claim

#guard formalizes.isGround
#guard theoremShapedRequirement.allVariablesBound
#guard typedSchwarzschildRequirement.valid
#guard certified.isCertified

/-- Executable smoke target used by `lake exe zilLeanTests`. -/
def main : IO Unit := do
  unless certified.graphRule.trust == .certified do
    throw <| IO.userError "certified wrapper lost its trust boundary"
  unless theoremShapedRequirement.trust == .graphDerived do
    throw <| IO.userError "ordinary theorem-shaped graph rule was upgraded"
  IO.println "zil-lean cross-runtime exchange and incremental delta validation passed"