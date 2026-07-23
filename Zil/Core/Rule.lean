import Zil.Core.Relation

namespace Zil

/-- Distinguishes metadata inference from kernel-certified reasoning. -/
inductive TrustClass where
  | asserted
  | graphDerived
  | certified
  deriving Repr, BEq, Inhabited

/-- Canonical single-head Horn rule with a stratified negative body. -/
structure Rule where
  name : Name
  variables : Array Name
  premises : Array RelExpr
  negativePremises : Array RelExpr := #[]
  conclusion : RelExpr
  trust : TrustClass := .graphDerived
  source : Source := {}
  deriving Repr, Inhabited

namespace Rule

private def pushName (names : Array Name) (name : Name) : Array Name :=
  if names.contains name then names else names.push name

private def relationsVariables (relations : Array RelExpr) : Array Name :=
  relations.foldl (init := #[]) fun names relation =>
    relation.variables.foldl (init := names) pushName

private def relationVariablesBound (bound : Array Name) (relation : RelExpr) : Bool :=
  relation.variables.all bound.contains

/-- Variables bound by positive premises. -/
def positiveVariables (rule : Rule) : Array Name :=
  relationsVariables rule.premises

/-- Variables used by negative premises. -/
def negativeVariables (rule : Rule) : Array Name :=
  relationsVariables rule.negativePremises

/-- Every variable occurring in the conclusion is explicitly declared. -/
def conclusionVariablesBound (rule : Rule) : Bool :=
  relationVariablesBound rule.variables rule.conclusion

/-- Every variable occurring anywhere in the rule is explicitly declared. -/
def allVariablesBound (rule : Rule) : Bool :=
  rule.premises.all (relationVariablesBound rule.variables) &&
  rule.negativePremises.all (relationVariablesBound rule.variables) &&
  relationVariablesBound rule.variables rule.conclusion

/-- Safe negation and grounding: negative/head variables must be bound positively. -/
def safe (rule : Rule) : Bool :=
  let positive := rule.positiveVariables
  rule.negativeVariables.all positive.contains &&
  rule.conclusion.variables.all positive.contains

end Rule
end Zil
