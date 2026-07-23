import Zil

open Zil

/-!
# 3. Typed relation profiles

Typed rules validate relation endpoints against a profile. Here `formalizes`
expects a declaration and a claim, while `requires` expects a declaration and a
requirement.
-/

zil_typed_rule typedRequirementPropagation using Zil.Profile.research where
  variables
    declaration : declaration
    claim : claim
    requirement : requirement
  premises
    declaration ⟶[formalizes] claim
    declaration ⟶[requires] requirement
  conclusion
    claim ⟶[requiresClaim] requirement

#guard typedRequirementPropagation.valid
#guard typedRequirementPropagation.rule.premises.size == 2
#guard typedRequirementPropagation.rule.conclusion.relation ==
  `zil.requiresClaim

/-!
A category error remains representable for diagnostics, but profile validation
rejects it.
-/

zil_typed_rule invalidFormalization using Zil.Profile.research where
  variables
    declaration : declaration
    requirement : requirement
  premises
    declaration ⟶[formalizes] requirement
  conclusion
    declaration ⟶[requires] requirement

#guard !invalidFormalization.valid
