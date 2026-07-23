import Zil.Core.Rule

namespace Zil

/-- Semantic categories used to validate relation endpoints. -/
inductive NodeKind where
  | declaration
  | claim
  | requirement
  | evidenceSource
  | concept
  | file
  | theorem
  | unknown
  deriving Repr, BEq, Inhabited

namespace NodeKind

/-- Resolve the stable Lean-facing spelling of a node kind. -/
def ofName (name : Name) : NodeKind :=
  match name.toString with
  | "declaration" => .declaration
  | "claim" => .claim
  | "requirement" => .requirement
  | "evidenceSource" => .evidenceSource
  | "concept" => .concept
  | "file" => .file
  | "theorem" => .theorem
  | _ => .unknown

/-- Infer a kind for conventional ground-node namespaces. -/
def inferGround (name : Name) : NodeKind :=
  let text := name.toString
  if text.startsWith "claim." then .claim
  else if text.startsWith "requirement." then .requirement
  else if text.startsWith "paper." || text.startsWith "source." then .evidenceSource
  else if text.startsWith "concept." then .concept
  else if text.startsWith "file." then .file
  else if text.startsWith "theorem." then .theorem
  else if text.startsWith "lean." then .declaration
  else .unknown

end NodeKind

/-- Declared type of a rule or query variable. -/
structure VariableKind where
  variable : Name
  kind : NodeKind
  deriving Repr, BEq, Inhabited

/-- Domain and range declaration for one relation. -/
structure RelationSig where
  relation : Name
  subjectKind : NodeKind
  objectKind : NodeKind
  deriving Repr, BEq, Inhabited

/-- Versioned vocabulary and relation-signature collection. -/
structure Profile where
  name : Name
  version : String
  relations : Array RelationSig
  deriving Repr, Inhabited

namespace Profile

private def variableKind? (variables : Array VariableKind) (name : Name) : Option NodeKind :=
  (variables.find? fun entry => entry.variable == name).map (·.kind)

/-- Resolve the semantic kind of a relation term. -/
def termKind? (variables : Array VariableKind) : Term → Option NodeKind
  | .var name => variableKind? variables name
  | .node node =>
      let kind := NodeKind.inferGround node.name
      if kind == .unknown then none else some kind

/-- Check one relation against any matching signature in the profile. -/
def validatesRelation
    (profile : Profile)
    (variables : Array VariableKind)
    (relation : RelExpr) : Bool :=
  match termKind? variables relation.subject, termKind? variables relation.object with
  | some subjectKind, some objectKind =>
      profile.relations.any fun signature =>
        signature.relation == relation.relation &&
        signature.subjectKind == subjectKind &&
        signature.objectKind == objectKind
  | _, _ => false

/-- Check every premise and the conclusion of a rule. -/
def validatesRule
    (profile : Profile)
    (variables : Array VariableKind)
    (rule : Rule) : Bool :=
  rule.allVariablesBound &&
  rule.premises.all (validatesRelation profile variables) &&
  validatesRelation profile variables rule.conclusion

end Profile

/-- A graph rule paired with endpoint kinds and the profile that validates it. -/
structure TypedRule where
  profile : Profile
  variableKinds : Array VariableKind
  rule : Rule
  deriving Repr, Inhabited

namespace TypedRule

def valid (typedRule : TypedRule) : Bool :=
  typedRule.profile.validatesRule typedRule.variableKinds typedRule.rule

end TypedRule
end Zil
