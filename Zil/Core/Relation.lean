import Zil.Core.Term

namespace Zil

/-- Provenance attached by a parser, scanner, or Lean elaborator. -/
structure Source where
  frontend : String := "unknown"
  file : Option String := none
  line : Option Nat := none
  deriving Repr, BEq, Inhabited

/-- Canonical graph-oriented relation expression: subject --relation--> object. -/
structure RelExpr where
  subject : Term
  relation : Name
  object : Term
  source : Source := {}
  deriving Repr, BEq, Inhabited

namespace RelExpr

/-- Provenance is operational metadata and is excluded from semantic equality. -/
def semanticEq (left right : RelExpr) : Bool :=
  left.subject == right.subject &&
  left.relation == right.relation &&
  left.object == right.object

end RelExpr

/-- Normalize aliases shared by standalone ZIL and Lean-facing syntax. -/
def canonicalRelation (relation : Name) : Name :=
  match relation.toString with
  | "requires_claim" | "requiresClaim" => `zil.requiresClaim
  | "supported_by" | "supportedBy" => `zil.supportedBy
  | "depends_on" | "dependsOn" => `zil.dependsOn
  | "defined_in" | "definedIn" => `zil.definedIn
  | "type_depends_on" | "typeDependsOn" => `zil.typeDependsOn
  | "formalizes" => `zil.formalizes
  | "requires" => `zil.requires
  | other =>
      if other.contains '.' then relation else Name.str `zil other

/-- Construct a canonical relation from standalone or native frontend tokens. -/
def relationExpr (subject : String) (relation : Name) (object : String)
    (source : Source := {}) : RelExpr :=
  { subject := Term.ofToken subject
    relation := canonicalRelation relation
    object := Term.ofToken object
    source := source }

#guard canonicalRelation `requires_claim == `zil.requiresClaim
#guard canonicalRelation `requiresClaim == `zil.requiresClaim
#guard canonicalRelation `physics.formalizes == `physics.formalizes

end Zil
