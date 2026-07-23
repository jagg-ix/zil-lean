import Zil.Environment.Knowledge
import Zil.Core.Query

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

private def unifyTerm (pattern value : Zil.Term) (binding : Binding) : Option Binding :=
  match pattern with
  | .var name => binding.bind name value
  | .node node => if value == .node node then some binding else none

private def unifyAttrValue
    (pattern value : Zil.AttrValue) (binding : Binding) : Option Binding :=
  match pattern, value with
  | .term patternTerm, .term valueTerm => unifyTerm patternTerm valueTerm binding
  | _, _ => if pattern == value then some binding else none

private def unifyAttributes
    (patterns facts : Array Zil.Attribute) (binding : Binding) : Option Binding :=
  patterns.foldl (init := some binding) fun state pattern =>
    match state with
    | none => none
    | some current =>
        match Zil.Attribute.find? facts pattern.key with
        | none => none
        | some fact => unifyAttrValue pattern.value fact.value current

private def unifyRelation (pattern fact : Zil.RelExpr) (binding : Binding) : Option Binding :=
  if pattern.relation != fact.relation then none
  else
    match unifyTerm pattern.subject fact.subject binding with
    | none => none
    | some next =>
        match unifyTerm pattern.object fact.object next with
        | none => none
        | some endpoints => unifyAttributes pattern.attrs fact.attrs endpoints

private def instantiateTerm (binding : Binding) : Zil.Term → Option Zil.Term
  | .node node => some (.node node)
  | .var name => binding.lookup name

private def instantiateAttrValue
    (binding : Binding) : Zil.AttrValue → Option Zil.AttrValue
  | .term term => (instantiateTerm binding term).map .term
  | value => some value

private def instantiateRelation (binding : Binding) (relation : Zil.RelExpr) : Option Zil.RelExpr := do
  let subject ← instantiateTerm binding relation.subject
  let object ← instantiateTerm binding relation.object
  let mut attrs : Array Zil.Attribute := #[]
  for entry in relation.attrs do
    let value ← instantiateAttrValue binding entry.value
    attrs := attrs.push { entry with value }
  pure { relation with subject, object, attrs }

private def extendBindings (facts : Array Zil.RelExpr)
    (patterns : Array Zil.RelExpr) (seed : Binding := #[]) : Array Binding :=
  patterns.foldl (init := #[seed]) fun bindings pattern =>
    bindings.foldl (init := #[]) fun out binding =>
      facts.foldl (init := out) fun acc fact =>
        match unifyRelation pattern fact binding with
        | some next => acc.push next
        | none => acc

private def hasMatch
    (facts : Array Zil.RelExpr) (pattern : Zil.RelExpr) (binding : Binding) : Bool :=
  facts.any fun fact => (unifyRelation pattern fact binding).isSome

private def negativesHold
    (facts : Array Zil.RelExpr) (patterns : Array Zil.RelExpr) (binding : Binding) : Bool :=
  patterns.all fun pattern => !hasMatch facts pattern binding

private def deriveRule
    (positiveFacts negativeFacts : Array Zil.RelExpr)
    (rule : Zil.Rule) : Array Zil.RelExpr :=
  (extendBindings positiveFacts rule.premises).filterMap fun binding =>
    if negativesHold negativeFacts rule.negativePremises binding then
      instantiateRelation binding rule.conclusion
    else none

private def pushSemantic (facts : Array Zil.RelExpr) (fact : Zil.RelExpr) : Array Zil.RelExpr :=
  if facts.any (·.semanticallyEqual fact) then facts else facts.push fact

/-- One weighted dependency between rule-body and rule-head relations. -/
structure DependencyEdge where
  from : Name
  to : Name
  strict : Bool
  deriving Repr, BEq, Inhabited

/-- Relation-to-stratum assignments. -/
abbrev Strata := Array (Name × Nat)

namespace Strata

def lookup (strata : Strata) (relation : Name) : Nat :=
  ((strata.find? fun entry => entry.1 == relation).map (·.2)).getD 0

private def set (strata : Strata) (relation : Name) (level : Nat) : Strata :=
  if strata.any fun entry => entry.1 == relation then
    strata.map fun entry => if entry.1 == relation then (relation, level) else entry
  else strata.push (relation, level)

end Strata

private def pushName (names : Array Name) (name : Name) : Array Name :=
  if names.contains name then names else names.push name

/-- Weighted relation dependencies used by the stratifier. -/
def dependencyEdges (rules : Array Zil.Rule) : Array DependencyEdge :=
  rules.foldl (init := #[]) fun edges rule =>
    let edges := rule.premises.foldl (init := edges) fun current premise =>
      current.push { from := premise.relation, to := rule.conclusion.relation, strict := false }
    rule.negativePremises.foldl (init := edges) fun current premise =>
      current.push { from := premise.relation, to := rule.conclusion.relation, strict := true }

private def relationNames (rules : Array Zil.Rule) : Array Name :=
  rules.foldl (init := #[]) fun names rule =>
    let names := pushName names rule.conclusion.relation
    let names := rule.premises.foldl (init := names) fun current premise =>
      pushName current premise.relation
    rule.negativePremises.foldl (init := names) fun current premise =>
      pushName current premise.relation

private def relaxEdge (strata : Strata) (edge : DependencyEdge) : Strata :=
  let source := strata.lookup edge.from
  let required := source + if edge.strict then 1 else 0
  let current := strata.lookup edge.to
  if current < required then strata.set edge.to required else strata

private def relaxAll (strata : Strata) (edges : Array DependencyEdge) : Strata :=
  edges.foldl (init := strata) relaxEdge

private def relaxSteps (strata : Strata) (edges : Array DependencyEdge) : Nat → Strata
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

private def rulesAt
    (rules : Array Zil.Rule) (strata : Strata) (level : Nat) : Array Zil.Rule :=
  rules.filter fun rule => strata.lookup rule.conclusion.relation == level

private def closeOneStratum
    (baseFacts : Array Zil.RelExpr)
    (rules : Array Zil.Rule)
    (fuel : Nat) : Array Zil.RelExpr :=
  let rec loop (facts : Array Zil.RelExpr) : Nat → Array Zil.RelExpr
    | 0 => facts
    | remaining + 1 =>
        let next := rules.foldl (init := facts) fun current rule =>
          (deriveRule current baseFacts rule).foldl (init := current) pushSemantic
        if next.size == facts.size then facts else loop next remaining
  loop baseFacts fuel

private def maxStratum (strata : Strata) : Nat :=
  strata.foldl (init := 0) fun current entry => Nat.max current entry.2

private def executeLevels
    (facts : Array Zil.RelExpr)
    (rules : Array Zil.Rule)
    (strata : Strata)
    (fuel : Nat) : Nat → Nat → Array Zil.RelExpr
  | _, 0 => facts
  | level, remaining + 1 =>
      let closed := closeOneStratum facts (rulesAt rules strata level) fuel
      executeLevels closed rules strata fuel (level + 1) remaining

/-- Compute stratified least-fixpoint closure and report unsafe or cyclic programs. -/
def closureChecked
    (facts : Array Zil.RelExpr) (rules : Array Zil.Rule)
    (fuel : Nat := 64) : Except String (Array Zil.RelExpr) := do
  let strata ← stratify rules
  pure <| executeLevels facts rules strata fuel 0 (maxStratum strata + 1)

/-- Compatibility wrapper. Invalid programs leave the supplied fact set unchanged. -/
def closure (facts : Array Zil.RelExpr) (rules : Array Zil.Rule)
    (fuel : Nat := 64) : Array Zil.RelExpr :=
  match closureChecked facts rules fuel with
  | .ok closed => closed
  | .error _ => facts

/-- Compute closure from facts and rules persisted in a Lean environment. -/
def closureOfEnvironment (env : Lean.Environment) (fuel : Nat := 64) : Array Zil.RelExpr :=
  closure (Zil.Environment.facts env) (Zil.Environment.rules env) fuel

/-- Solve a safe conjunctive query with absence checks over a closed fact set. -/
def solve (facts : Array Zil.RelExpr) (query : Zil.Query) : Array Binding :=
  if !query.selectedVariablesBound || !query.safe then #[]
  else
    (extendBindings facts query.premises).filter fun binding =>
      negativesHold facts query.negativePremises binding

/-- Solve a query using the bounded closure of one Lean environment. -/
def solveEnvironment (env : Lean.Environment) (query : Zil.Query)
    (fuel : Nat := 64) : Array Binding :=
  solve (closureOfEnvironment env fuel) query

/-- Test whether one semantic fact is present after stratified closure. -/
def entails (facts : Array Zil.RelExpr) (rules : Array Zil.Rule)
    (target : Zil.RelExpr) (fuel : Nat := 64) : Bool :=
  (closure facts rules fuel).any (·.semanticallyEqual target)

end Zil.Engine
