import Zil.Core.Relation

namespace Zil

/-- Canonical conjunctive query over relation expressions. -/
structure Query where
  name : Name
  variables : Array Name
  select : Array Name
  premises : Array RelExpr
  source : Source := {}
  deriving Repr, Inhabited

namespace Query

/-- Selected variables must be declared by the query. -/
def selectedVariablesBound (query : Query) : Bool :=
  query.select.all (fun name => query.variables.contains name)

end Query
end Zil
