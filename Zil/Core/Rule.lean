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

/-- Every variable occurring in a rule conclusion must be explicitly bound. -/
def conclusionVariablesBound (rule : Rule) : Bool :=
  let bound := rule.variables
  let termBound : Term → Bool
    | .var name => bound.contains name
    | .node _ => true
  termBound rule.conclusion.subject && termBound rule.conclusion.object

end Rule
end Zil
