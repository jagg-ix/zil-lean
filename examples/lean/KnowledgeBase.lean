import Zil

open Zil

/-!
This module is imported by `05_ImportedKnowledge.lean`.
Its facts and rule are persisted through the Lean environment extension.
-/

zil_fact
  node(lean.Imported.metric)
    ⟶[formalizes]
  node(claim.importedMetric)

zil_fact
  node(lean.Imported.metric)
    ⟶[requires]
  node(requirement.importedLorentzian)

zil_theorem_rule importedRequirementRule
  {declaration claim requirement : Zil.Node}
  (hFormalizes : declaration ⟶[formalizes] claim)
  (hRequires : declaration ⟶[requires] requirement)
  : claim ⟶[requiresClaim] requirement

zil_register_rule importedRequirementRule
