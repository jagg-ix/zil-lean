import Zil.Core.Relation

namespace Zil

/-- Canonical conjunctive query representation. -/
structure Query where
  name : Name
  variables : Array Name
  select : Array Name
  premises : Array RelExpr
  source : Source := {}
  deriving Repr, BEq, Inhabited

namespace Query

/-- Selected variables must be declared and a query must have at least one premise. -/
def valid (query : Query) : Bool :=
  !query.premises.isEmpty &&
  query.select.all fun name => query.variables.contains name

end Query
end Zil
