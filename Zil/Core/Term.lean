namespace Zil

/-- A stable knowledge node identifier. -/
structure Node where
  name : Name
  deriving Repr, BEq, Inhabited

/-- A term in a canonical ZIL relation expression. -/
inductive Term where
  | var : Name → Term
  | node : Node → Term
  deriving Repr, BEq, Inhabited

namespace Term

/-- Construct a variable term from a Lean name. -/
def variable (name : Name) : Term := .var name

/-- Construct a ground node term from a Lean name. -/
def ground (name : Name) : Term := .node ⟨name⟩

/-- Return true precisely when the term is a rule/query variable. -/
def isVariable : Term → Bool
  | .var _ => true
  | .node _ => false

end Term
end Zil
