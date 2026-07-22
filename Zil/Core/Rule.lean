import Zil.Core.Relation

namespace Zil

/-- Distinguishes metadata inference from kernel-certified reasoning. -/
inductive TrustClass where
  | asserted
  | graphDerived
  | certified
  deriving Repr, BEq, Inhabited

/-- Canonical single-head Horn rule. -/
structure Rule where
  name : Name
  variables : Array Name
  premises : Array RelExpr
  conclusion : RelExpr
  trust : TrustClass := .graphDerived
  source : Source := {}
  deriving Repr, Inhabited

namespace Rule

private def termBound (bound : Array Name) : Term → Bool
  | .var name => bound.contains name
  | .node _ => true

private def relationVariablesBound (bound : Array Name) (relation : RelExpr) : Bool :=
  termBound bound relation.subject && termBound bound relation.object

/-- Every variable occurring in a rule conclusion must be explicitly bound. -/
def conclusionVariablesBound (rule : Rule) : Bool :=
  relationVariablesBound rule.variables rule.conclusion

/-- Every variable occurring in premises or the conclusion must be explicitly bound. -/
def allVariablesBound (rule : Rule) : Bool :=
  rule.premises.all (relationVariablesBound rule.variables) &&
  relationVariablesBound rule.variables rule.conclusion

end Rule
end Zil
