import Zil.Core.Rule

namespace Zil

/-- A Zanzibar-style userset: all nodes related to one object by one relation. -/
structure UsersetRef where
  object : Node
  relation : Name
  deriving Repr, BEq, Inhabited

/-- The subject position of an original `object#relation@subject` tuple. -/
inductive TupleSubject where
  | direct : Term → TupleSubject
  | userset : UsersetRef → TupleSubject
  deriving Repr, BEq, Inhabited

/-- A lossless representation of one original ZIL tuple.

Unlike `RelExpr`, this type preserves whether the tuple subject was a direct term
or a userset such as `group:eng#member`. -/
structure TupleExpr where
  object : Term
  relation : Name
  subject : TupleSubject
  source : Source := {}
  deriving Repr, Inhabited

/-- Existing Horn-engine input produced from one lossless tuple. -/
structure LoweredTuple where
  facts : Array RelExpr := #[]
  rules : Array Rule := #[]
  deriving Repr, Inhabited

namespace TupleExpr

/-- Construct a tuple with a direct subject. -/
def direct (object : Term) (relation : Name) (subject : Term) : TupleExpr :=
  { object, relation, subject := .direct subject }

/-- Construct a tuple whose subject is a userset. -/
def withUserset
    (object : Term) (relation : Name)
    (usersetObject : Node) (usersetRelation : Name) : TupleExpr :=
  { object, relation, subject := .userset ⟨usersetObject, usersetRelation⟩ }

/-- Semantic equality preserves the direct/userset distinction and ignores source data. -/
def semanticallyEqual (left right : TupleExpr) : Bool :=
  left.object == right.object &&
  left.relation == right.relation &&
  left.subject == right.subject

/-- Deterministic name for the Horn rule used to follow a userset. -/
def usersetRuleName (outer inner : Name) : Name :=
  Name.str `zil s!"userset_{outer}_via_{inner}"

/-- Lower the tuple's immediately stored relation. -/
def lowerFact (tuple : TupleExpr) : RelExpr :=
  match tuple.subject with
  | .direct subject =>
      { subject := tuple.object, relation := tuple.relation,
        object := subject, source := tuple.source }
  | .userset userset =>
      { subject := tuple.object, relation := tuple.relation,
        object := .node userset.object, source := tuple.source }

/-- Build the traversal rule required by a userset tuple. -/
def lowerUsersetRule? (tuple : TupleExpr) : Option Rule :=
  match tuple.subject with
  | .direct _ => none
  | .userset userset =>
      let objectVar := Term.variable `object
      let usersetVar := Term.variable `userset
      let subjectVar := Term.variable `subject
      some {
        name := usersetRuleName tuple.relation userset.relation
        variables := #[`object, `userset, `subject]
        premises := #[
          RelExpr.mk' objectVar tuple.relation usersetVar,
          RelExpr.mk' usersetVar userset.relation subjectVar
        ]
        conclusion := RelExpr.mk' objectVar tuple.relation subjectVar
        trust := .graphDerived
        source := tuple.source
      }

/-- Lower one lossless tuple to the existing fact/rule engine representation. -/
def lower (tuple : TupleExpr) : LoweredTuple :=
  match tuple.lowerUsersetRule? with
  | none => { facts := #[tuple.lowerFact] }
  | some rule => { facts := #[tuple.lowerFact], rules := #[rule] }

end TupleExpr

/-- A parsed original ZIL tuple unit. -/
structure TupleProgram where
  moduleName : Option Name := none
  tuples : Array TupleExpr := #[]
  deriving Repr, Inhabited

namespace TupleProgram

private def appendRuleIfMissing (rules : Array Rule) (candidate : Rule) : Array Rule :=
  if rules.any (fun rule => rule.name == candidate.name) then rules
  else rules.push candidate

/-- Lower all tuples, sharing one userset traversal rule per relation pair. -/
def lower (program : TupleProgram) : LoweredTuple :=
  program.tuples.foldl (init := {}) fun result tuple =>
    let next := tuple.lower
    let rules := next.rules.foldl (init := result.rules) appendRuleIfMissing
    { facts := result.facts ++ next.facts, rules }

end TupleProgram

end Zil
