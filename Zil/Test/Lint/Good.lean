import Zil

namespace Zil.Test.Lint.Good

open Zil.Syntax

theorem sampleDeclaration : True := by trivial

zil_rule propagateRequirement where
  variables declaration claim requirement
  premises
    declaration ⟶[formalizes] claim
    declaration ⟶[requires] requirement
  conclusion
    claim ⟶[requiresClaim] requirement

zil_register_rule propagateRequirement

zil_fact node(lean.Zil.Test.Lint.Good.sampleDeclaration) ⟶[formalizes] node(claim.lintGood)
zil_fact node(lean.Zil.Test.Lint.Good.sampleDeclaration) ⟶[requires] node(requirement.lintGood)
zil_fact node(claim.lintGood) ⟶[supportedBy] node(paper.lintGood)

zil_link sampleDeclaration with
  node(lean.Zil.Test.Lint.Good.sampleDeclaration) ⟶[formalizes] node(claim.lintGood)

run_cmd do
  let env ← getEnv
  unless Zil.Lint.clean env do
    let report := String.intercalate "\n" ((Zil.Lint.scan env).toList.map Zil.Lint.render)
    throwError "expected clean formalization fixture:\n{report}"

#zil_lint!

end Zil.Test.Lint.Good
