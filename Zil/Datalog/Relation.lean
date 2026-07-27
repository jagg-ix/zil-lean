module

public import Zil.Datalog.Revision

@[expose] public section

open Lean

namespace Zil.Datalog

/-- Provenance classification for a relationship tuple. -/
inductive FactOrigin where
  | source
  | derived
  | leanDeclaration
  | generated
  deriving Repr, DecidableEq, Inhabited

/-- A tuple subject is either a node or a reference to another relation set. -/
inductive SubjectRef where
  | node (name : Name)
  | relationSet (object : Name) (relation : Name)
  deriving Repr, DecidableEq, Inhabited

/-- Extensible tuple metadata kept outside relation semantics. -/
abbrev Metadata := List (String × String)

/-- Canonical Zanzibar-shaped relationship data for the native relation layer. -/
structure RelationTuple where
  object : Name
  relation : Name
  subject : SubjectRef
  metadata : Metadata := []
  origin : FactOrigin := .source
  deriving Repr, DecidableEq, Inhabited

/-- Declarative relation semantics for the native Zanzibar-compatible layer. -/
inductive RelationExpr where
  | this
  | computed (relation : Name)
  | union (left right : RelationExpr)
  | intersection (left right : RelationExpr)
  | difference (left right : RelationExpr)
  | compose (tupleset computed : Name)
  deriving Repr, DecidableEq, Inhabited

/-- The monotone relation fragment for which finite semantic evidence can always
be represented by a positive derivation tree. -/
def RelationExpr.Positive : RelationExpr → Prop
  | .this | .computed _ | .compose _ _ => True
  | .union left right | .intersection left right => left.Positive ∧ right.Positive
  | .difference _ _ => False

/-- One versioned relation definition in a profile. -/
structure RelationDef where
  name : Name
  expression : RelationExpr
  deriving Repr, DecidableEq, Inhabited

/-- A versioned collection of relation definitions. -/
structure RelationSchema where
  profile : Name
  version : Nat
  definitions : List RelationDef := []
  deriving Repr, DecidableEq, Inhabited

/-- An immutable tuple snapshot consumed by the native evaluator. -/
structure TupleStore where
  revision : Revision
  tuples : List RelationTuple := []
  deriving Repr, DecidableEq, Inhabited

def RelationSchema.find? (schema : RelationSchema) (relation : Name) : Option RelationExpr :=
  (schema.definitions.find? fun definition => definition.name == relation).map (·.expression)

/-- Every expression reachable through a schema lookup belongs to the positive fragment. -/
def RelationSchema.Positive (schema : RelationSchema) : Prop :=
  ∀ relation expression, schema.find? relation = some expression → expression.Positive

/-- Independent bounded denotational membership for a relation expression. -/
def RelationExprMember (schema : RelationSchema) (store : TupleStore) :
    Nat → Name → Name → Name → RelationExpr → Prop
  | 0, _, _, _, _ => False
  | fuel + 1, object, relation, subject, expression =>
      match expression with
      | .this =>
          (∃ tuple, tuple ∈ store.tuples ∧ tuple.object = object ∧
            tuple.relation = relation ∧ tuple.subject = .node subject) ∨
          (∃ tuple nestedObject nestedRelation nested,
            tuple ∈ store.tuples ∧ tuple.object = object ∧ tuple.relation = relation ∧
            tuple.subject = .relationSet nestedObject nestedRelation ∧
            schema.find? nestedRelation = some nested ∧
            RelationExprMember schema store fuel nestedObject nestedRelation subject nested)
      | .computed nestedRelation =>
          ∃ nested, schema.find? nestedRelation = some nested ∧
            RelationExprMember schema store fuel object nestedRelation subject nested
      | .union left right =>
          RelationExprMember schema store fuel object relation subject left ∨
          RelationExprMember schema store fuel object relation subject right
      | .intersection left right =>
          RelationExprMember schema store fuel object relation subject left ∧
          RelationExprMember schema store fuel object relation subject right
      | .difference left right =>
          RelationExprMember schema store fuel object relation subject left ∧
          ¬RelationExprMember schema store fuel object relation subject right
      | .compose tupleset computed =>
          ∃ edge intermediate nested, edge ∈ store.tuples ∧ edge.object = object ∧
            edge.relation = tupleset ∧ edge.subject = .node intermediate ∧
            schema.find? computed = some nested ∧
            RelationExprMember schema store fuel intermediate computed subject nested

/-- Named relation membership resolves the versioned schema before interpreting its expression. -/
def RelationMember (schema : RelationSchema) (store : TupleStore) (fuel : Nat)
    (object relation subject : Name) : Prop :=
  ∃ expression, schema.find? relation = some expression ∧
    RelationExprMember schema store fuel object relation subject expression

/-- Deterministic failures reported when sealing a relation schema. -/
inductive SchemaValidationError where
  | duplicateRelation (relation : Name)
  | undefinedRelation (owner referenced : Name)
  | invalidComposition (owner referenced : Name)
  | negativeCycle (owner referenced : Name)
  deriving Repr, DecidableEq, Inhabited

/-- A schema dependency is positive (monotone) or negative (under exclusion). -/
inductive DependencyPolarity where
  | positive
  | negative
  deriving Repr, DecidableEq, Inhabited

structure RelationDependency where
  owner : Name
  referenced : Name
  polarity : DependencyPolarity
  deriving Repr, DecidableEq, Inhabited

def DependencyPolarity.flip : DependencyPolarity → DependencyPolarity
  | .positive => .negative
  | .negative => .positive

/-- Collect semantic relation dependencies, propagating polarity through difference. -/
def RelationExpr.dependencies (owner : Name) (polarity : DependencyPolarity) :
    RelationExpr → List RelationDependency
  | .this => []
  | .computed relation => [{ owner, referenced := relation, polarity }]
  | .union left right | .intersection left right =>
      left.dependencies owner polarity ++ right.dependencies owner polarity
  | .difference left right =>
      left.dependencies owner polarity ++ right.dependencies owner polarity.flip
  | .compose _ computedRelation =>
      [{ owner, referenced := computedRelation, polarity }]

def RelationSchema.dependencies (schema : RelationSchema) : List RelationDependency :=
  schema.definitions.flatMap fun definition =>
    definition.expression.dependencies definition.name .positive

def RelationSchema.reachesAux (schema : RelationSchema) (target : Name) :
    Nat → List Name → Name → Bool
  | 0, _, _ => false
  | fuel + 1, visited, current =>
      if current == target then true
      else if visited.contains current then false
      else
        (schema.dependencies.filter (·.owner == current)).any fun edge =>
          schema.reachesAux target fuel (current :: visited) edge.referenced

def RelationSchema.reaches (schema : RelationSchema) (target current : Name) : Bool :=
  schema.reachesAux target (schema.definitions.length + 1) [] current

def RelationSchema.firstNegativeCycle? (schema : RelationSchema) :
    Option RelationDependency :=
  schema.dependencies.find? fun edge =>
    edge.polarity == .negative && schema.reaches edge.owner edge.referenced

def RelationExpr.validateReferences (schema : RelationSchema) (owner : Name) :
    RelationExpr → Except SchemaValidationError Unit
  | .this => pure ()
  | .computed relation =>
      if (schema.find? relation).isSome then pure ()
      else throw (.undefinedRelation owner relation)
  | .union left right | .intersection left right | .difference left right => do
      left.validateReferences schema owner
      right.validateReferences schema owner
  | .compose tupleset computedRelation =>
      if !(schema.find? tupleset).isSome then
        throw (.invalidComposition owner tupleset)
      else if !(schema.find? computedRelation).isSome then
        throw (.invalidComposition owner computedRelation)
      else pure ()

def firstDuplicate? : List Name → Option Name
  | [] => none
  | name :: rest => if rest.contains name then some name else firstDuplicate? rest

/-- Validate all relation names and references before the schema is used by tuples or queries. -/
def RelationSchema.validate (schema : RelationSchema) : Except SchemaValidationError Unit := do
  match firstDuplicate? (schema.definitions.map (·.name)) with
  | some relation => throw (.duplicateRelation relation)
  | none => pure ()
  for definition in schema.definitions do
    definition.expression.validateReferences schema definition.name
  match schema.firstNegativeCycle? with
  | some edge => throw (.negativeCycle edge.owner edge.referenced)
  | none => pure ()

end Zil.Datalog
