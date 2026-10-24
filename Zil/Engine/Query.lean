module

import Std.Data.HashMap
public import Zil.Environment.Knowledge
public import Zil.Core.Query

@[expose] public section

namespace Zil.Engine

abbrev Binding := Array (Name × Zil.Term)

namespace Binding

def lookup (binding : Binding) (name : Name) : Option Zil.Term :=
  (binding.find? fun pair => pair.1 == name).map (·.2)

def bind (binding : Binding) (name : Name) (term : Zil.Term) : Option Binding :=
  match binding.lookup name with
  | none => some (binding.push (name, term))
  | some existing => if existing == term then some binding else none

end Binding

def unifyTerm (pattern value : Zil.Term) (binding : Binding) : Option Binding :=
  match pattern with
  | .var name => binding.bind name value
  | .node node => if value == .node node then some binding else none

def unifyAttrValue
    (pattern value : Zil.AttrValue) (binding : Binding) : Option Binding :=
  match pattern, value with
  | .term patternTerm, .term valueTerm => unifyTerm patternTerm valueTerm binding
  | _, _ => if pattern == value then some binding else none

def unifyAttributes
    (patterns facts : Array Zil.Attribute) (binding : Binding) : Option Binding :=
  patterns.foldl (init := some binding) fun state pattern =>
    match state with
    | none => none
    | some current =>
        match Zil.Attribute.find? facts pattern.key with
        | none => none
        | some fact => unifyAttrValue pattern.value fact.value current

def unifyRelation (pattern fact : Zil.RelExpr) (binding : Binding) : Option Binding :=
  if pattern.relation != fact.relation then none
  else
    match unifyTerm pattern.subject fact.subject binding with
    | none => none
    | some next =>
        match unifyTerm pattern.object fact.object next with
        | none => none
        | some endpoints => unifyAttributes pattern.attrs fact.attrs endpoints

/-- Relation and endpoint indexes preserve source order within every fact bucket. -/
structure FactIndex where
  byRelation : Std.HashMap Name (Array Zil.RelExpr) := {}
  bySubject : Std.HashMap (Name × Zil.Term) (Array Zil.RelExpr) := {}
  byObject : Std.HashMap (Name × Zil.Term) (Array Zil.RelExpr) := {}
  deriving Inhabited

namespace FactIndex

/-- Grow a bucket in place. Reading the bucket out and inserting a longer copy kept the old array shared with
    the map, so every insert copied the whole bucket: building the index of a large relation was quadratic. -/
def appendBucket {key : Type} [BEq key] [Hashable key]
    (index : Std.HashMap key (Array Zil.RelExpr))
    (value : key) (fact : Zil.RelExpr) : Std.HashMap key (Array Zil.RelExpr) :=
  if index.contains value then index.modify value (·.push fact) else index.insert value #[fact]

/-- Add one fact to its relation, subject and object indexes. -/
def insert (index : FactIndex) (fact : Zil.RelExpr) : FactIndex :=
  { byRelation := appendBucket index.byRelation fact.relation fact
    bySubject := appendBucket index.bySubject (fact.relation, fact.subject) fact
    byObject := appendBucket index.byObject (fact.relation, fact.object) fact }

/-- Build indexes once for a stable fact set. -/
def build (facts : Array Zil.RelExpr) : FactIndex :=
  facts.foldl insert {}

def relation (index : FactIndex) (name : Name) : Array Zil.RelExpr :=
  index.byRelation[name]?.getD #[]

def subject (index : FactIndex) (relation : Name) (value : Zil.Term) : Array Zil.RelExpr :=
  index.bySubject[(relation, value)]?.getD #[]

def object (index : FactIndex) (relation : Name) (value : Zil.Term) : Array Zil.RelExpr :=
  index.byObject[(relation, value)]?.getD #[]

/-- Semantic equality needs the same relation and subject, so only that bucket is searched: a whole relation's
    bucket made deduplicating a large derived relation (a transitive closure) quadratic. -/
def containsSemantic (index : FactIndex) (fact : Zil.RelExpr) : Bool :=
  (index.subject fact.relation fact.subject).any (·.semanticallyEqual fact)

/-- Narrow candidates by any endpoint already fixed or bound in the current join. -/
def candidates (index : FactIndex) (pattern : Zil.RelExpr) (binding : Binding) : Array Zil.RelExpr :=
  let subject := match pattern.subject with
    | .node node => some (.node node)
    | .var name => binding.lookup name
  let object := match pattern.object with
    | .node node => some (.node node)
    | .var name => binding.lookup name
  match subject, object with
  | some subject, some object =>
      (index.subject pattern.relation subject).filter (·.object == object)
  | some subject, none => index.subject pattern.relation subject
  | none, some object => index.object pattern.relation object
  | none, none => index.relation pattern.relation

end FactIndex

def instantiateTerm (binding : Binding) : Zil.Term → Option Zil.Term
  | .node node => some (.node node)
  | .var name => binding.lookup name

def instantiateAttrValue
    (binding : Binding) : Zil.AttrValue → Option Zil.AttrValue
  | .term term => (instantiateTerm binding term).map .term
  | value => some value

def instantiateRelation (binding : Binding) (relation : Zil.RelExpr) : Option Zil.RelExpr := do
  let subject ← instantiateTerm binding relation.subject
  let object ← instantiateTerm binding relation.object
  let mut attrs : Array Zil.Attribute := #[]
  for entry in relation.attrs do
    let value ← instantiateAttrValue binding entry.value
    attrs := attrs.push { entry with value }
  pure { relation with subject, object, attrs }

def extendBindingsIndexed (index : FactIndex)
    (patterns : Array Zil.RelExpr) (seed : Binding := #[]) : Array Binding :=
  patterns.foldl (init := #[seed]) fun bindings pattern =>
    bindings.foldl (init := #[]) fun out binding =>
      (index.candidates pattern binding).foldl (init := out) fun acc fact =>
        match unifyRelation pattern fact binding with
        | some next => acc.push next
        | none => acc

def extendBindings (facts : Array Zil.RelExpr)
    (patterns : Array Zil.RelExpr) (seed : Binding := #[]) : Array Binding :=
  extendBindingsIndexed (FactIndex.build facts) patterns seed

def hasMatch
    (facts : Array Zil.RelExpr) (pattern : Zil.RelExpr) (binding : Binding) : Bool :=
  facts.any fun fact => (unifyRelation pattern fact binding).isSome

def hasMatchIndexed
    (index : FactIndex) (pattern : Zil.RelExpr) (binding : Binding) : Bool :=
  (index.candidates pattern binding).any fun fact =>
    (unifyRelation pattern fact binding).isSome

def negativesHold
    (facts : Array Zil.RelExpr) (patterns : Array Zil.RelExpr) (binding : Binding) : Bool :=
  patterns.all fun pattern => !hasMatch facts pattern binding

def negativesHoldIndexed
    (index : FactIndex) (patterns : Array Zil.RelExpr) (binding : Binding) : Bool :=
  patterns.all fun pattern => !hasMatchIndexed index pattern binding

def deriveRuleIndexed
    (positiveFacts negativeFacts : FactIndex)
    (rule : Zil.Rule) : Array Zil.RelExpr :=
  (extendBindingsIndexed positiveFacts rule.premises).filterMap fun binding =>
    if negativesHoldIndexed negativeFacts rule.negativePremises binding then
      instantiateRelation binding rule.conclusion
    else none

def deriveRule
    (positiveFacts negativeFacts : Array Zil.RelExpr)
    (rule : Zil.Rule) : Array Zil.RelExpr :=
  deriveRuleIndexed (FactIndex.build positiveFacts) (FactIndex.build negativeFacts) rule

def pushSemantic (facts : Array Zil.RelExpr) (fact : Zil.RelExpr) : Array Zil.RelExpr :=
  if facts.any (·.semanticallyEqual fact) then facts else facts.push fact

/-- One weighted dependency between rule-body and rule-head relations. -/
structure DependencyEdge where
  source : Name
  target : Name
  strict : Bool
  deriving Repr, BEq, Inhabited

/-- Relation-to-stratum assignments. -/
abbrev Strata := Array (Name × Nat)

namespace Strata

def lookup (strata : Strata) (relation : Name) : Nat :=
  ((strata.find? fun entry => entry.1 == relation).map (·.2)).getD 0

def set (strata : Strata) (relation : Name) (level : Nat) : Strata :=
  if strata.any fun entry => entry.1 == relation then
    strata.map fun entry => if entry.1 == relation then (relation, level) else entry
  else strata.push (relation, level)

end Strata

def pushName (names : Array Name) (name : Name) : Array Name :=
  if names.contains name then names else names.push name

/-- Weighted relation dependencies used by the stratifier. -/
def dependencyEdges (rules : Array Zil.Rule) : Array DependencyEdge :=
  rules.foldl (init := #[]) fun edges rule =>
    let edges := rule.premises.foldl (init := edges) fun current premise =>
      current.push { source := premise.relation, target := rule.conclusion.relation, strict := false }
    rule.negativePremises.foldl (init := edges) fun current premise =>
      current.push { source := premise.relation, target := rule.conclusion.relation, strict := true }

def relationNames (rules : Array Zil.Rule) : Array Name :=
  rules.foldl (init := #[]) fun names rule =>
    let names := pushName names rule.conclusion.relation
    let names := rule.premises.foldl (init := names) fun current premise =>
      pushName current premise.relation
    rule.negativePremises.foldl (init := names) fun current premise =>
      pushName current premise.relation

def relaxEdge (strata : Strata) (edge : DependencyEdge) : Strata :=
  let source := strata.lookup edge.source
  let required := source + (if edge.strict then 1 else 0)
  let current := strata.lookup edge.target
  if current < required then strata.set edge.target required else strata

def relaxAll (strata : Strata) (edges : Array DependencyEdge) : Strata :=
  edges.foldl (init := strata) relaxEdge

def relaxSteps (strata : Strata) (edges : Array DependencyEdge) : Nat → Strata
  | 0 => strata
  | count + 1 => relaxSteps (relaxAll strata edges) edges count

/-- Compute a valid stratum for every relation or reject a strict dependency cycle. -/
def stratify (rules : Array Zil.Rule) : Except String Strata := do
  for rule in rules do
    unless rule.allVariablesBound do
      throw s!"rule {rule.name} contains an undeclared variable"
    unless rule.safe do
      throw s!"rule {rule.name} is unsafe: negative and head variables must be positively bound"
  let names := relationNames rules
  let initial : Strata := names.map fun name => (name, 0)
  let edges := dependencyEdges rules
  let settled := relaxSteps initial edges names.size
  let next := relaxAll settled edges
  unless next == settled do
    throw "program is not stratifiable: negative dependency cycle"
  pure settled

def rulesAt
    (rules : Array Zil.Rule) (strata : Strata) (level : Nat) : Array Zil.Rule :=
  rules.filter fun rule => strata.lookup rule.conclusion.relation == level

/-- The number of rounds the closure of one stratum may take. A round that adds nothing ends the loop, so a large bound costs nothing
when the closure is reached; it is only a limit. Each round adds at least one fact, so no program that has a closure comes near it. -/
def defaultFuel : Nat := 1000000

/-- Close one stratum, and say whether the fixpoint was reached. A round that adds no fact ends the loop with `true`. Using up `fuel`
rounds first ends it with `false` and the facts derived so far: the last round counts, so a closure that needs `n` rounds needs `fuel`
of at least `n + 1` to be known to be complete. -/
def closeOneStratum
    (baseFacts : Array Zil.RelExpr)
    (rules : Array Zil.Rule)
    (fuel : Nat) : Array Zil.RelExpr × Bool :=
  let negativeIndex := FactIndex.build baseFacts
  let rec loop (facts : Array Zil.RelExpr) (index : FactIndex) : Nat → Array Zil.RelExpr × Bool
    | 0 => (facts, false)
    | remaining + 1 =>
        let (next, nextIndex) := rules.foldl (init := (facts, index)) fun (current, currentIndex) rule =>
          (deriveRuleIndexed currentIndex negativeIndex rule).foldl
            (init := (current, currentIndex)) fun (stateFacts, stateIndex) fact =>
              if stateIndex.containsSemantic fact then (stateFacts, stateIndex)
              else (stateFacts.push fact, stateIndex.insert fact)
        if next.size == facts.size then (facts, true) else loop next nextIndex remaining
  loop baseFacts (FactIndex.build baseFacts) fuel

def maxStratum (strata : Strata) : Nat :=
  strata.foldl (init := 0) fun current entry => Nat.max current entry.2

/-- Close every stratum in order. The second component is the lowest stratum whose rounds ran out before its fixpoint, if any; the
facts are then the closure so far. -/
def executeLevels
    (facts : Array Zil.RelExpr)
    (rules : Array Zil.Rule)
    (strata : Strata)
    (fuel : Nat) : Nat → Nat → Array Zil.RelExpr × Option Nat
  | _, 0 => (facts, none)
  | level, remaining + 1 =>
      let (closed, converged) := closeOneStratum facts (rulesAt rules strata level) fuel
      let (final, unfinished) := executeLevels closed rules strata fuel (level + 1) remaining
      (final, if converged then unfinished else some level)

/-- Compute the stratified least-fixpoint closure, and report unsafe or cyclic programs. It fails, and does not return a partial
closure, when the rounds run out before a stratum reaches its fixpoint. -/
def closureChecked
    (facts : Array Zil.RelExpr) (rules : Array Zil.Rule)
    (fuel : Nat := defaultFuel) : Except String (Array Zil.RelExpr) := do
  let strata ← stratify rules
  let (closed, unfinished) := executeLevels facts rules strata fuel 0 (maxStratum strata + 1)
  match unfinished with
  | none => pure closed
  | some level =>
      throw s!"closure did not reach its fixpoint in stratum {level} within {fuel} rounds; the facts derived so far are not the closure"

/-- Compatibility wrapper for callers that have no way to receive an error. Invalid programs leave the supplied fact set unchanged.
If the rounds run out, the facts derived so far are returned, which is a bounded closure and not the closure: with a `fuel` of your
own, use `closureChecked` to be told. -/
def closure (facts : Array Zil.RelExpr) (rules : Array Zil.Rule)
    (fuel : Nat := defaultFuel) : Array Zil.RelExpr :=
  match stratify rules with
  | .ok strata => (executeLevels facts rules strata fuel 0 (maxStratum strata + 1)).1
  | .error _ => facts

/-- Compute closure from facts and rules persisted in a Lean environment. -/
def closureOfEnvironment (env : Lean.Environment) (fuel : Nat := defaultFuel) : Array Zil.RelExpr :=
  closure (Zil.Environment.facts env) (Zil.Environment.rules env) fuel

/-- Solve a safe conjunctive query with absence checks over a closed fact set. -/
def solveIndexed (index : FactIndex) (query : Zil.Query) : Array Binding :=
  if !query.selectedVariablesBound || !query.safe then #[]
  else
    (extendBindingsIndexed index query.premises).filter fun binding =>
      negativesHoldIndexed index query.negativePremises binding

def solve (facts : Array Zil.RelExpr) (query : Zil.Query) : Array Binding :=
  solveIndexed (FactIndex.build facts) query

/-- Solve a query using the bounded closure of one Lean environment. -/
def solveEnvironment (env : Lean.Environment) (query : Zil.Query)
    (fuel : Nat := defaultFuel) : Array Binding :=
  solve (closureOfEnvironment env fuel) query

/-- Test whether one semantic fact is present after stratified closure. -/
def entails (facts : Array Zil.RelExpr) (rules : Array Zil.Rule)
    (target : Zil.RelExpr) (fuel : Nat := defaultFuel) : Bool :=
  (closure facts rules fuel).any (·.semanticallyEqual target)

end Zil.Engine
