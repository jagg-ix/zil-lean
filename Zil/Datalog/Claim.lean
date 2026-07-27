module

public meta import Lean.Elab.Tactic

@[expose] public section

open Lean Meta Elab Tactic

namespace Zil.Datalog

/-- Persistent declaration metadata linking an ordinary Lean declaration to a
stable ZIL claim name. -/
meta initialize zilClaimAttr : ParametricAttribute Name ←
  registerParametricAttribute {
    name := `zil_claim
    descr := "link a Lean declaration to a stable ZIL claim name"
    getParam := fun _ stx => Attribute.Builtin.getId stx
  }

/-- Persistent declaration metadata linking a Lean declaration to a stable ZIL
concept. This records subject matter, not proof of any claim. -/
meta initialize zilConceptAttr : ParametricAttribute Name ←
  registerParametricAttribute {
    name := `zil_concept
    descr := "link a Lean declaration to a stable ZIL concept name"
    getParam := fun _ stx => Attribute.Builtin.getId stx
  }

/-- Persistent declaration metadata recording a named assumption, capability,
or other ZIL requirement of a Lean declaration. -/
meta initialize zilRequiresAttr : ParametricAttribute Name ←
  registerParametricAttribute {
    name := `zil_requires
    descr := "link a Lean declaration to a named ZIL requirement"
    getParam := fun _ stx => Attribute.Builtin.getId stx
  }

/-- Persistent declaration metadata recording the abstraction level of the
statement proved by a Lean declaration. The accepted vocabulary is validated
by the formalization-contract layer. -/
meta initialize zilLevelAttr : ParametricAttribute Name ←
  registerParametricAttribute {
    name := `zil_level
    descr := "classify the abstraction level of a Lean declaration"
    getParam := fun _ stx => Attribute.Builtin.getId stx
  }

/-- Mark a declaration for explicit inclusion by selective ZIL exporters. -/
meta initialize zilExportAttr : TagAttribute ←
  registerTagAttribute `zil_export
    "include this Lean declaration in selective ZIL environment exports"

meta structure DeclarationMetadata where
  claim : Option Name := none
  concept : Option Name := none
  requirement : Option Name := none
  level : Option Name := none
  exportSelected : Bool := false
  deriving Repr, Inhabited

meta def declarationMetadata (env : Environment) (declaration : Name) : DeclarationMetadata := {
  claim := zilClaimAttr.getParam? env declaration
  concept := zilConceptAttr.getParam? env declaration
  requirement := zilRequiresAttr.getParam? env declaration
  level := zilLevelAttr.getParam? env declaration
  exportSelected := zilExportAttr.hasTag env declaration
}

/-- Find all imported and local declarations linked to a stable ZIL claim name. -/
meta def declarationsForClaim (env : Environment) (claim : Name) : Array Name :=
  env.constants.fold (init := #[]) fun found declaration _ =>
    if zilClaimAttr.getParam? env declaration == some claim then
      found.push declaration
    else found
  |>.qsort Name.quickLt

meta def declarationsForConcept (env : Environment) (concept : Name) : Array Name :=
  env.constants.fold (init := #[]) fun found declaration _ =>
    if zilConceptAttr.getParam? env declaration == some concept then
      found.push declaration
    else found
  |>.qsort Name.quickLt

/-- Find all imported and local declarations linked to a named ZIL requirement. -/
meta def declarationsRequiring (env : Environment) (requirement : Name) : Array Name :=
  env.constants.fold (init := #[]) fun found declaration _ =>
    if zilRequiresAttr.getParam? env declaration == some requirement then
      found.push declaration
    else found
  |>.qsort Name.quickLt

/-- Find all imported and local declarations classified at an abstraction level. -/
meta def declarationsAtLevel (env : Environment) (level : Name) : Array Name :=
  env.constants.fold (init := #[]) fun found declaration _ =>
    if zilLevelAttr.getParam? env declaration == some level then
      found.push declaration
    else found
  |>.qsort Name.quickLt

meta def exportedDeclarations (env : Environment) : Array Name :=
  env.constants.fold (init := #[]) fun found declaration _ =>
    if zilExportAttr.hasTag env declaration then found.push declaration else found
  |>.qsort Name.quickLt

syntax (name := zilApplyTac) "zil_apply " ident : tactic

/-- Resolve a ZIL claim through persistent declaration metadata and apply the
linked kernel declaration to the current goal. -/
@[tactic zilApplyTac]
meta def evalZilApply : Tactic := fun stx => do
  let `(tactic| zil_apply $claim:ident) := stx | throwUnsupportedSyntax
  let claimName := claim.getId
  let declarations := declarationsForClaim (← getEnv) claimName
  let declaration ← match declarations with
    | #[declaration] => pure declaration
    | #[] => throwErrorAt claim "no Lean declaration is linked to ZIL claim '{claimName}'"
    | _ => throwErrorAt claim
        "ZIL claim '{claimName}' has multiple linked declarations: {declarations.toList}"
  evalTactic (← `(tactic| apply $(mkIdent declaration)))

end Zil.Datalog
