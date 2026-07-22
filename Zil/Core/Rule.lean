import Zil.Core.Relation

namespace Zil

/-- Trust class distinguishes graph inference from kernel-certified reasoning. -/
inductive RuleTrust where
  | graph
  | certified
  deriving Repr, BEq, Inhabited

/-- Canonical single-head Horn rule shared with the standalone runtime. -/
structure Rule where
  name : Name
  variables : Array Name
  premises : Array RelExpr
  conclusion : RelExpr
  trust : RuleTrust := .graph
  source : Source := {}
  deriving Repr, BEq, Inhabited

namespace Rule

/-- Variables occurring in a relation expression. -/
def variablesIn (relation : RelExpr) : Array Name :=
  let fromTerm : Term → Array Name
    | .var name => #[name]
    | .node _ => #[]
  fromTerm relation.subject ++ fromTerm relation.object

/-- Every variable used by a rule must be explicitly declared. -/
def hasOnlyDeclaredVariables (rule : Rule) : Bool :=
  let used := rule.premises.foldl (init := variablesIn rule.conclusion)
    fun acc premise => acc ++ variablesIn premise
  used.all fun name => rule.variables.contains name

/-- A rule must contain at least one premise and use only declared variables. -/
def valid (rule : Rule) : Bool :=
  !rule.premises.isEmpty && rule.hasOnlyDeclaredVariables

end Rule
end Zil
