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

private def deriveRule (facts : Array Zil.RelExpr) (rule : Zil.Rule) : Array Zil.RelExpr :=
  (extendBindings facts rule.premises).filterMap fun binding =>
    instantiateRelation binding rule.conclusion

private def pushSemantic (facts : Array Zil.RelExpr) (fact : Zil.RelExpr) : Array Zil.RelExpr :=
  if facts.any (·.semanticallyEqual fact) then facts else facts.push fact

private def step (rules : Array Zil.Rule) (facts : Array Zil.RelExpr) : Array Zil.RelExpr :=
  rules.foldl (init := facts) fun acc rule =>
    (deriveRule acc rule).foldl (init := acc) pushSemantic

/-- Compute bounded least-fixpoint closure. Fuel prevents accidental nontermination. -/
def closure (facts : Array Zil.RelExpr) (rules : Array Zil.Rule)
    (fuel : Nat := 64) : Array Zil.RelExpr :=
  match fuel with
  | 0 => facts
  | fuel + 1 =>
      let next := step rules facts
      if next.size == facts.size then facts else closure next rules fuel

/-- Compute closure from facts and rules persisted in a Lean environment. -/
def closureOfEnvironment (env : Lean.Environment) (fuel : Nat := 64) : Array Zil.RelExpr :=
  closure (Zil.Environment.facts env) (Zil.Environment.rules env) fuel

/-- Solve a conjunctive query against a closed fact set. -/
def solve (facts : Array Zil.RelExpr) (query : Zil.Query) : Array Binding :=
  extendBindings facts query.premises

/-- Solve a query using the bounded closure of one Lean environment. -/
def solveEnvironment (env : Lean.Environment) (query : Zil.Query)
    (fuel : Nat := 64) : Array Binding :=
  solve (closureOfEnvironment env fuel) query

/-- Test whether one semantic fact is present after closure. -/
def entails (facts : Array Zil.RelExpr) (rules : Array Zil.Rule)
    (target : Zil.RelExpr) (fuel : Nat := 64) : Bool :=
  (closure facts rules fuel).any (·.semanticallyEqual target)

end Zil.Engine
