import Zil.Engine.Query

namespace Zil.Engine.Provenance

abbrev NodeId := Nat
abbrev Binding := Zil.Engine.Binding

inductive Origin where
  | asserted
  | ruleApplication (rule : Name) (binding : Binding) (trust : Zil.TrustClass)
  deriving Repr, Inhabited

structure Node where
  id : NodeId
  fact : Zil.RelExpr
  origin : Origin
  premises : Array NodeId := #[]
  deriving Repr, Inhabited

structure DAG where
  nodes : Array Node := #[]
  completeness : Zil.Engine.Completeness := .complete
  deriving Repr, Inhabited

private def lookupBinding (binding : Binding) (name : Name) : Option Zil.Term :=
  (binding.find? fun pair => pair.1 == name).map (·.2)

private def bind (binding : Binding) (name : Name) (term : Zil.Term) : Option Binding :=
  match lookupBinding binding name with
  | none => some (binding.push (name, term))
  | some existing => if existing == term then some binding else none

private def unifyTerm (pattern value : Zil.Term) (binding : Binding) : Option Binding :=
  match pattern with
  | .var name => bind binding name value
  | .node node => if value == .node node then some binding else none

private def unifyRelation (pattern fact : Zil.RelExpr) (binding : Binding) : Option Binding :=
  if pattern.relation != fact.relation then none
  else do
    let next ← unifyTerm pattern.subject fact.subject binding
    unifyTerm pattern.object fact.object next

private def instantiateTerm (binding : Binding) : Zil.Term → Option Zil.Term
  | .node node => some (.node node)
  | .var name => lookupBinding binding name

private def instantiateRelation (binding : Binding) (relation : Zil.RelExpr) : Option Zil.RelExpr := do
  let subject ← instantiateTerm binding relation.subject
  let object ← instantiateTerm binding relation.object
  pure { relation with subject, object }

private structure MatchState where
  binding : Binding
  premises : Array NodeId
  deriving Inhabited

private def extendMatches (nodes : Array Node) (patterns : Array Zil.RelExpr) : Array MatchState :=
  patterns.foldl (init := #[{ binding := #[], premises := #[] }]) fun states pattern =>
    states.foldl (init := #[]) fun out state =>
      nodes.foldl (init := out) fun acc node =>
        match unifyRelation pattern node.fact state.binding with
        | some binding => acc.push { binding, premises := state.premises.push node.id }
        | none => acc

private def findFact? (nodes : Array Node) (fact : Zil.RelExpr) : Option NodeId :=
  (nodes.find? fun node => node.fact.semanticallyEqual fact).map (·.id)

private def addAsserted (nodes : Array Node) (fact : Zil.RelExpr) : Array Node :=
  if (findFact? nodes fact).isSome then nodes
  else nodes.push { id := nodes.size, fact, origin := .asserted }

private def applyRule (nodes : Array Node) (rule : Zil.Rule) : Array Node :=
  (extendMatches nodes rule.premises).foldl (init := nodes) fun acc matchState =>
    match instantiateRelation matchState.binding rule.conclusion with
    | none => acc
    | some fact =>
        if (findFact? acc fact).isSome then acc
        else acc.push {
          id := acc.size
          fact
          origin := .ruleApplication rule.name matchState.binding rule.trust
          premises := matchState.premises }

private def step (nodes : Array Node) (rules : Array Zil.Rule) : Array Node :=
  rules.foldl (init := nodes) applyRule

/-- Build a cycle-free derivation DAG by recording the first derivation of each semantic fact. -/
def build (facts : Array Zil.RelExpr) (rules : Array Zil.Rule) (fuel : Nat := 64) : DAG :=
  let initial := facts.foldl (init := #[]) addAsserted
  let rec loop (nodes : Array Node) (remaining : Nat) : DAG :=
    match remaining with
    | 0 =>
        let next := step nodes rules
        { nodes, completeness := if next.size == nodes.size then .complete else .fuelExhausted }
    | n + 1 =>
        let next := step nodes rules
        if next.size == nodes.size then { nodes, completeness := .complete }
        else loop next n
  loop initial fuel

def rootFor? (dag : DAG) (fact : Zil.RelExpr) : Option NodeId :=
  findFact? dag.nodes fact

/-- Return a topologically ordered explanation subtree ending at `root`. -/
def explain (dag : DAG) (root : NodeId) : Array Node :=
  let rec visit (id : NodeId) (seen : Array NodeId) (out : Array Node) : Array NodeId × Array Node :=
    if seen.contains id then (seen, out)
    else
      match dag.nodes.get? id with
      | none => (seen, out)
      | some node =>
          let (seen, out) := node.premises.foldl (init := (seen.push id, out)) fun state premise =>
            visit premise state.1 state.2
          (seen, out.push node)
  (visit root #[] #[]).2

end Zil.Engine.Provenance
