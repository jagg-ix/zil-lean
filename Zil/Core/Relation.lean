import Zil.Core.Term

namespace Zil

/-- Origin metadata for a relation or rule. It is excluded from semantic equality. -/
structure Source where
  frontend : String := "unknown"
  file : Option String := none
  line : Option Nat := none
  deriving Repr, Inhabited

/-- Canonical subject-relation-object expression shared by ZIL frontends. -/
structure RelExpr where
  subject : Term
  relation : Name
  object : Term
  source : Source := {}
  deriving Repr, Inhabited

namespace RelExpr

/-- Semantic equality deliberately ignores source/provenance metadata. -/
def semanticallyEqual (left right : RelExpr) : Bool :=
  left.subject == right.subject &&
  left.relation == right.relation &&
  left.object == right.object

/-- Construct a canonical relation without source metadata. -/
def mk' (subject : Term) (relation : Name) (object : Term) : RelExpr :=
  { subject, relation, object }

end RelExpr
end Zil
