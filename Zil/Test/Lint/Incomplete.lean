import Zil

namespace Zil.Test.Lint.Incomplete

open Zil.Syntax

theorem sampleDeclaration : True := by trivial

zil_fact node(lean.Zil.Test.Lint.Incomplete.sampleDeclaration) ⟶[formalizes] node(claim.lintIncomplete)
zil_fact node(lean.Zil.Test.Lint.Incomplete.sampleDeclaration) ⟶[requires] node(requirement.lintIncomplete)

run_cmd do
  let env ← getEnv
  let issues := Zil.Lint.scan env
  unless issues.any (fun issue => issue.kind == .unsupportedClaim) do
    throwError "missing unsupported-claim diagnostic"
  unless issues.any (fun issue => issue.kind == .unlinkedDeclaration) do
    throwError "missing unlinked-declaration diagnostic"
  unless issues.any (fun issue => issue.kind == .unpropagatedRequirement) do
    throwError "missing unpropagated-requirement diagnostic"

#zil_lint

end Zil.Test.Lint.Incomplete
