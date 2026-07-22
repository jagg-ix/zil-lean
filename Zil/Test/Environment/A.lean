import Zil

namespace Zil.Test.EnvironmentA

/-- Declaration used to test stable declaration links across module imports. -/
theorem sampleDeclaration : True := by
  trivial

zil_rule importedRequirementRule where
  variables declaration claim requirement
  premises
    declaration ⟶[formalizes] claim
    declaration ⟶[requires] requirement
  conclusion
    claim ⟶[requiresClaim] requirement

zil_register_rule importedRequirementRule
zil_register_profile Zil.Profile.research

zil_fact
  node(lean.Zil.Test.EnvironmentA.sampleDeclaration)
    ⟶[formalizes]
  node(claim.environmentPersistence)

zil_link Zil.Test.EnvironmentA.sampleDeclaration with
  node(lean.Zil.Test.EnvironmentA.sampleDeclaration)
    ⟶[formalizes]
  node(claim.environmentPersistence)

end Zil.Test.EnvironmentA