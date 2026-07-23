import Zil.Core.Attribute

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
  attrs : Array Attribute := #[]
  source : Source := {}
  deriving Repr, Inhabited

namespace RelExpr

/-- Semantic equality ignores source locations and treats attributes as a finite map. -/
def semanticallyEqual (left right : RelExpr) : Bool :=
  left.subject == right.subject &&
  left.relation == right.relation &&
  left.object == right.object &&
  Attribute.arraysSemanticallyEqual left.attrs right.attrs

/-- True when endpoints and attribute values contain no variables. -/
def isGround (relation : RelExpr) : Bool :=
  !relation.subject.isVariable &&
  !relation.object.isVariable &&
  Attribute.allGround relation.attrs

/-- Construct a canonical relation without attributes or source metadata. -/
def mk' (subject : Term) (relation : Name) (object : Term) : RelExpr :=
  { subject, relation, object }

/-- Construct a canonical relation with an explicit attribute map. -/
def mkWithAttrs
    (subject : Term) (relation : Name) (object : Term)
    (attrs : Array Attribute) : RelExpr :=
  { subject, relation, object, attrs }

end RelExpr
end Zil
