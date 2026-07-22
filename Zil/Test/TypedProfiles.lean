import Zil.Profile.Research
import Zil.Syntax.TypedRule

open Zil
open Zil.Syntax

zil_typed_rule typedSchwarzschildRequirement using Zil.Profile.research where
  variables
    declaration : declaration
    claim : claim
    requirement : requirement
  premises
    declaration ⟶[formalizes] claim
    declaration ⟶[requires] requirement
  conclusion
    claim ⟶[requiresClaim] requirement

zil_typed_rule typedSchwarzschildEvidence using Zil.Profile.research where
  variables
    declaration : declaration
    claim : claim
    source : evidenceSource
  premises
    declaration ⟶[formalizes] claim
    declaration ⟶[supportedBy] source
  conclusion
    claim ⟶[supportedBy] source

/-- Syntactically valid, but semantically invalid: `formalizes` expects a Claim object. -/
zil_typed_rule invalidFormalizesRequirement using Zil.Profile.research where
  variables
    declaration : declaration
    requirement : requirement
  premises
    declaration ⟶[formalizes] requirement
  conclusion
    declaration ⟶[formalizes] requirement

/-- Ground nodes are validated from stable namespace prefixes. -/
def validGroundRelation : RelExpr :=
  .mk' (.ground `lean.Schwarzschild.metric) `zil.formalizes
    (.ground `claim.schwarzschildMetric)

/-- A paper cannot be the subject of `formalizes`. -/
def invalidPaperFormalizer : RelExpr :=
  .mk' (.ground `paper.schwarzschild1916) `zil.formalizes
    (.ground `claim.schwarzschildMetric)

#guard typedSchwarzschildRequirement.valid
#guard typedSchwarzschildEvidence.valid
#guard !invalidFormalizesRequirement.valid
#guard Zil.Profile.research.validatesRelation #[] validGroundRelation
#guard !Zil.Profile.research.validatesRelation #[] invalidPaperFormalizer
#guard Zil.Profile.research.version == "0.1"
