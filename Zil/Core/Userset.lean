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

/-- A lossless representation of one original ZIL tuple. -/
structure TupleExpr where
  object : Term
  relation : Name
  subject : TupleSubject
  attrs : Array Attribute := #[]
  source : Source := {}
  deriving Repr, Inhabited

/-- Existing Horn-engine input produced from one lossless tuple. -/
structure LoweredTuple where
  facts : Array RelExpr := #[]
  rules : Array Rule := #[]
  deriving Repr, Inhabited

namespace TupleExpr

/-- Construct a tuple with a direct subject. -/
def direct
    (object : Term) (relation : Name) (subject : Term)
    (attrs : Array Attribute := #[]) : TupleExpr :=
  { object, relation, subject := .direct subject, attrs }

/-- Construct a tuple whose subject is a userset. -/
def withUserset
    (object : Term) (relation : Name)
    (usersetObject : Node) (usersetRelation : Name)
    (attrs : Array Attribute := #[]) : TupleExpr :=
  { object, relation, subject := .userset ⟨usersetObject, usersetRelation⟩, attrs }

/-- Semantic equality preserves the direct/userset distinction and tuple attributes. -/
def semanticallyEqual (left right : TupleExpr) : Bool :=
  left.object == right.object &&
  left.relation == right.relation &&
  left.subject == right.subject &&
  Attribute.arraysSemanticallyEqual left.attrs right.attrs

/-- True when the tuple contains no endpoint or attribute variables. -/
def isGround (tuple : TupleExpr) : Bool :=
  let subjectGround := match tuple.subject with
    | .direct subject => !subject.isVariable
    | .userset _ => true
  !tuple.object.isVariable && subjectGround && Attribute.allGround tuple.attrs

/-- Deterministic name for a userset traversal rule. Source lines keep attributed rules distinct. -/
def usersetRuleName (outer inner : Name) (source : Source) : Name :=
  let suffix := source.line.map (fun line => s!"line_{line}") |>.getD "generated"
  Name.str `zil s!"userset_{outer}_via_{inner}_{suffix}"

/-- Lower the tuple's immediately stored relation. -/
def lowerFact (tuple : TupleExpr) : RelExpr :=
  match tuple.subject with
  | .direct subject =>
      { subject := tuple.object, relation := tuple.relation,
        object := subject, attrs := tuple.attrs, source := tuple.source }
  | .userset userset =>
      { subject := tuple.object, relation := tuple.relation,
        object := .node userset.object, attrs := tuple.attrs, source := tuple.source }

/-- Build the traversal rule required by a userset tuple. -/
def lowerUsersetRule? (tuple : TupleExpr) : Option Rule :=
  match tuple.subject with
  | .direct _ => none
  | .userset userset =>
      let objectVar := Term.variable `object
      let usersetVar := Term.variable `userset
      let subjectVar := Term.variable `subject
      some {
        name := usersetRuleName tuple.relation userset.relation tuple.source
        variables := #[`object, `userset, `subject]
        premises := #[
          RelExpr.mkWithAttrs objectVar tuple.relation usersetVar tuple.attrs,
          RelExpr.mk' usersetVar userset.relation subjectVar
        ]
        conclusion := RelExpr.mkWithAttrs objectVar tuple.relation subjectVar tuple.attrs
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

private def rulesSemanticallyEqual (left right : Rule) : Bool :=
  left.variables == right.variables &&
  left.premises.size == right.premises.size &&
  (left.premises.zip right.premises).all fun pair => pair.1.semanticallyEqual pair.2 &&
  left.conclusion.semanticallyEqual right.conclusion

private def appendRuleIfMissing (rules : Array Rule) (candidate : Rule) : Array Rule :=
  if rules.any (fun rule => rulesSemanticallyEqual rule candidate) then rules
  else rules.push candidate

/-- Lower all tuples, sharing semantically identical userset traversal rules. -/
def lower (program : TupleProgram) : LoweredTuple :=
  program.tuples.foldl (init := {}) fun result tuple =>
    let next := tuple.lower
    let rules := next.rules.foldl (init := result.rules) appendRuleIfMissing
    { facts := result.facts ++ next.facts, rules }

end TupleProgram

end Zil
