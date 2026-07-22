import Zil.Engine.Query

namespace Zil.Engine

/-- Whether bounded closure reached a fixpoint. -/
inductive Completeness where
  | complete
  | fuelExhausted
  deriving Repr, BEq, Inhabited

/-- Lightweight graph derivation metadata. This never represents a Lean proof. -/
structure Derivation where
  fact : Zil.RelExpr
  rule : Name
  trust : Zil.TrustClass := .graphDerived
  deriving Repr, Inhabited

/-- Stable metadata attached to query and entailment responses. -/
structure ReportMeta where
  knowledgeRevision : Nat
  profileName : Option Name
  profileVersion : Option String
  completeness : Completeness
  deriving Repr, Inhabited

structure QueryReport where
  bindings : Array Binding
  facts : Array Zil.RelExpr
  derivations : Array Derivation
  meta : ReportMeta
  deriving Repr, Inhabited

structure CheckReport where
  result : Bool
  target : Zil.RelExpr
  derivation : Option Derivation
  meta : ReportMeta
  deriving Repr, Inhabited

private def semanticSubset (left right : Array Zil.RelExpr) : Bool :=
  left.all fun fact => right.any (·.semanticallyEqual fact)

private def closureCompleteness (facts : Array Zil.RelExpr) (rules : Array Zil.Rule)
    (fuel : Nat) : Completeness :=
  let closed := closure facts rules fuel
  let next := closure closed rules 1
  if semanticSubset next closed then .complete else .fuelExhausted

private def profileMetadata (env : Lean.Environment) : Option Name × Option String :=
  match (Zil.Environment.profiles env).get? 0 with
  | some profile => (some profile.name, some profile.version)
  | none => (none, none)

/-- Revision token for optimistic readers. It changes whenever imported/local entries change. -/
def knowledgeRevision (env : Lean.Environment) : Nat :=
  (Zil.Environment.entries env).size

private def metadata (env : Lean.Environment) (fuel : Nat) : ReportMeta :=
  let (profileName, profileVersion) := profileMetadata env
  { knowledgeRevision := knowledgeRevision env
    profileName
    profileVersion
    completeness := closureCompleteness (Zil.Environment.facts env)
      (Zil.Environment.rules env) fuel }

private def derivationFor (rules : Array Zil.Rule) (fact : Zil.RelExpr) : Option Derivation :=
  (rules.find? fun rule => rule.conclusion.relation == fact.relation).map fun rule =>
    { fact, rule := rule.name, trust := rule.trust }

/-- Solve a query and return bindings plus revision/profile/completeness metadata. -/
def reportQuery (env : Lean.Environment) (query : Zil.Query)
    (fuel : Nat := 64) : QueryReport :=
  let closed := closureOfEnvironment env fuel
  let rules := Zil.Environment.rules env
  { bindings := solve closed query
    facts := closed
    derivations := closed.filterMap (derivationFor rules)
    meta := metadata env fuel }

/-- Check one target and include graph derivation metadata when available. -/
def reportCheck (env : Lean.Environment) (target : Zil.RelExpr)
    (fuel : Nat := 64) : CheckReport :=
  let closed := closureOfEnvironment env fuel
  let present := closed.any (·.semanticallyEqual target)
  { result := present
    target
    derivation := if present then derivationFor (Zil.Environment.rules env) target else none
    meta := metadata env fuel }

end Zil.Engine
