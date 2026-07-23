import examples.lean.KnowledgeBase

open Zil

/-!
# 5. Knowledge across Lean imports

Importing `KnowledgeBase` reconstructs its ZIL facts and rules from the `.olean`
environment. The imported graph can then be queried or closed normally.
-/

run_cmd do
  let env ← getEnv
  unless Zil.Environment.containsRule env `importedRequirementRule do
    throwError "the imported rule was not reconstructed"

  let target := RelExpr.mk'
    (.ground `claim.importedMetric)
    `zil.requiresClaim
    (.ground `requirement.importedLorentzian)

  let closed := Zil.Engine.closureOfEnvironment env
  unless closed.any (·.semanticallyEqual target) do
    throwError "the imported facts and rule did not derive the target"

  logInfo m!"imported facts: {(Zil.Environment.facts env).size}"
  logInfo m!"imported rules: {(Zil.Environment.rules env).size}"
  logInfo m!"closure facts: {closed.size}"
