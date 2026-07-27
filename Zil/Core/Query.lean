import Zil.Core.Relation

namespace Zil

/-- Canonical conjunctive query with positive and stratified-negative premises. -/
structure Query where
  name : Name
  variables : Array Name
  select : Array Name
  premises : Array RelExpr
  negativePremises : Array RelExpr := #[]
  source : Source := {}
  deriving Repr, Inhabited

namespace Query

private def pushName (names : Array Name) (name : Name) : Array Name :=
  if names.contains name then names else names.push name

private def relationsVariables (relations : Array RelExpr) : Array Name :=
  relations.foldl (init := #[]) fun names relation =>
    relation.variables.foldl (init := names) pushName

/-- Variables bound by positive premises. -/
def positiveVariables (query : Query) : Array Name :=
  relationsVariables query.premises

/-- Variables used by negative premises. -/
def negativeVariables (query : Query) : Array Name :=
  relationsVariables query.negativePremises

/-- Selected variables must be declared by the query. -/
def selectedVariablesBound (query : Query) : Bool :=
  query.select.all (fun name => query.variables.contains name)

/-- Negative and selected variables must be bound by positive premises. -/
def safe (query : Query) : Bool :=
  let positive := query.positiveVariables
  query.negativeVariables.all positive.contains &&
  query.select.all positive.contains

end Query
end Zil
