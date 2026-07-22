import Zil.Profile.Core

namespace Zil.Profile

/-- Initial research/formalization vocabulary used by Lean-native ZIL rules. -/
def research : Zil.Profile :=
  { name := `zil.profile.research
    version := "0.1"
    relations := #[
      { relation := `formalizes
        subjectKind := .declaration
        objectKind := .claim },
      { relation := `requires
        subjectKind := .declaration
        objectKind := .requirement },
      { relation := `requiresClaim
        subjectKind := .claim
        objectKind := .requirement },
      { relation := `supportedBy
        subjectKind := .declaration
        objectKind := .evidenceSource },
      { relation := `supportedBy
        subjectKind := .claim
        objectKind := .evidenceSource }
    ] }

end Zil.Profile
