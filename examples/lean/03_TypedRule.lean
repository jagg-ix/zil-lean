import Zil.Native

open Lean Zil

/-!
# 3. Typed relation profiles

Typed rules validate relation endpoints against a profile. Here `formalizes`
expects a declaration and a claim, while `requires` expects a declaration and a
requirement. A `Zil.TypedRule` pairs a graph rule with declared endpoint kinds
and the profile that validates them.
-/

private def research : Profile := {
  name := `profile.research
  version := "1"
  relations := #[
    { relation := `zil.formalizes, subjectKind := .declaration, objectKind := .claim },
    { relation := `zil.requires, subjectKind := .declaration, objectKind := .requirement },
    { relation := `zil.requiresClaim, subjectKind := .claim, objectKind := .requirement }
  ]
}

private def researchKinds : Array VariableKind := #[
  { «variable» := `declaration, kind := .declaration },
  { «variable» := `claim, kind := .claim },
  { «variable» := `requirement, kind := .requirement }
]

zil_theorem_rule requirementPropagation
  {declaration claim requirement : Zil.Node}
  (hFormalizes : declaration ⟶[formalizes] claim)
  (hRequires : declaration ⟶[requires] requirement)
  : claim ⟶[requiresClaim] requirement

private def typedRequirementPropagation : TypedRule := {
  profile := research
  variableKinds := researchKinds
  rule := requirementPropagation
}

#guard typedRequirementPropagation.valid
#guard typedRequirementPropagation.rule.premises.size == 2
#guard typedRequirementPropagation.rule.conclusion.relation ==
  `zil.requiresClaim

/-!
A category error remains representable for diagnostics, but profile validation
rejects it: `formalizes` cannot point at a requirement.
-/

zil_theorem_rule invalidFormalization
  {declaration requirement : Zil.Node}
  (hFormalizes : declaration ⟶[formalizes] requirement)
  : declaration ⟶[requires] requirement

private def typedInvalidFormalization : TypedRule := {
  profile := research
  variableKinds := researchKinds
  rule := invalidFormalization
}

#guard !typedInvalidFormalization.valid

run_cmd do
  logInfo m!"typed rule: {typedRequirementPropagation.rule.name}"
  logInfo m!"valid: {typedRequirementPropagation.valid}"
  logInfo m!"rejected: {!typedInvalidFormalization.valid}"
