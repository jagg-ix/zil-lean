import Zil.Profile.Core

namespace Zil.Profile

/-- Initial research/formalization vocabulary used by Lean-native ZIL rules. -/
def research : Zil.Profile :=
  { name := `zil.profile.research
    version := "0.1"
    relations := #[
      { relation := `zil.formalizes
        subjectKind := .declaration
        objectKind := .claim },
      { relation := `zil.requires
        subjectKind := .declaration
        objectKind := .requirement },
      { relation := `zil.requiresClaim
        subjectKind := .claim
        objectKind := .requirement },
      { relation := `zil.supportedBy
        subjectKind := .declaration
        objectKind := .evidenceSource },
      { relation := `zil.supportedBy
        subjectKind := .claim
        objectKind := .evidenceSource }
    ] }

end Zil.Profile
