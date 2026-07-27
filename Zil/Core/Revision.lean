import Zil.Core.Relation

namespace Zil

/-- Logical fact identity used by revision processing. Attributes are state carried
by the latest operation, while subject/relation/object identify the fact. -/
structure FactKey where
  subject : Term
  relation : Name
  object : Term
  deriving Repr, BEq, Inhabited

namespace FactKey

def ofRelation (relation : RelExpr) : FactKey :=
  { subject := relation.subject, relation := relation.relation, object := relation.object }

end FactKey

inductive FactOperation where
  | assert
  | retract
  deriving Repr, BEq, Inhabited

/-- One append-style update to a logical relation fact. -/
structure RevisionedFact where
  fact : RelExpr
  revision : Nat
  event : Name
  operation : FactOperation := .assert
  deriving Repr, Inhabited

namespace RevisionedFact

def key (record : RevisionedFact) : FactKey := FactKey.ofRelation record.fact

end RevisionedFact

/-- One explicit happens-before edge between events. -/
structure CausalEdge where
  left : Name
  right : Name
  deriving Repr, BEq, Inhabited

/-- Finite strict causal-order graph. -/
structure CausalGraph where
  edges : Array CausalEdge := #[]
  deriving Repr, Inhabited

namespace CausalGraph

private def pushUnique (names : Array Name) (name : Name) : Array Name :=
  if names.contains name then names else names.push name

private def successors (graph : CausalGraph) (frontier : Array Name) : Array Name :=
  graph.edges.foldl (init := #[]) fun out edge =>
    if frontier.contains edge.left then pushUnique out edge.right else out

/-- Transitive happens-before lookup. -/
def before (graph : CausalGraph) (left right : Name) : Bool :=
  if left == right then false
  else
    let rec visit (frontier visited : Array Name) : Nat → Bool
      | 0 => false
      | fuel + 1 =>
          let next := graph.successors frontier |>.filter fun event => !visited.contains event
          if next.contains right then true
          else if next.isEmpty then false
          else visit next (next.foldl (init := visited) pushUnique) fuel
    visit #[left] #[left] (graph.edges.size + 1)

/-- Two distinct events are concurrent when neither causally precedes the other. -/
def concurrent (graph : CausalGraph) (left right : Name) : Bool :=
  left != right && !graph.before left right && !graph.before right left

/-- Every edge is non-reflexive and the transitive closure is acyclic. -/
def valid (graph : CausalGraph) : Bool :=
  graph.edges.all fun edge =>
    edge.left != edge.right && !graph.before edge.right edge.left

/-- Add one edge while preserving the strict partial order. -/
def addEdge (graph : CausalGraph) (edge : CausalEdge) : Except String CausalGraph :=
  if edge.left == edge.right then .error "causal edge is reflexive"
  else if graph.before edge.right edge.left then .error "causal edge creates a cycle"
  else if graph.edges.contains edge then .ok graph
  else .ok { edges := graph.edges.push edge }

/-- All events named by graph edges. -/
def events (graph : CausalGraph) : Array Name :=
  graph.edges.foldl (init := #[]) fun out edge =>
    pushUnique (pushUnique out edge.left) edge.right

end CausalGraph

/-- Append-style revision records paired with an explicit causal graph. -/
structure RevisionStore where
  moduleName : Name := `zil.revision
  records : Array RevisionedFact := #[]
  causal : CausalGraph := {}
  deriving Repr, Inhabited

namespace RevisionStore

private def pushUniqueKey (keys : Array FactKey) (key : FactKey) : Array FactKey :=
  if keys.contains key then keys else keys.push key

private def events (store : RevisionStore) : Array Name :=
  store.records.foldl (init := #[]) fun out record =>
    if out.contains record.event then out else out.push record.event

private def recordUniqueAtRevision (store : RevisionStore) (record : RevisionedFact) : Bool :=
  (store.records.filter fun candidate =>
    candidate.revision == record.revision && candidate.key == record.key).size == 1

/-- Validate ground facts, unique key/revision updates, causal edges, and edge event references. -/
def valid (store : RevisionStore) : Bool :=
  let namedEvents := store.events
  store.records.all (fun record => record.fact.isGround && store.recordUniqueAtRevision record) &&
  store.causal.valid &&
  store.causal.edges.all (fun edge => namedEvents.contains edge.left && namedEvents.contains edge.right)

private def latestFor
    (records : Array RevisionedFact)
    (key : FactKey) : Option RevisionedFact :=
  records.foldl (init := none) fun best record =>
    if record.key != key then best
    else match best with
      | none => some record
      | some current => if current.revision < record.revision then some record else best

/-- Materialize the deterministic relation state at a revision frontier. -/
def snapshotAt (store : RevisionStore) (frontier : Nat) : Except String (Array RelExpr) := do
  unless store.valid do throw "invalid revision store"
  let eligible := store.records.filter fun record => record.revision <= frontier
  let keys := eligible.foldl (init := #[]) fun out record => pushUniqueKey out record.key
  let mut facts : Array RelExpr := #[]
  for key in keys do
    match latestFor eligible key with
    | some record =>
        if record.operation == .assert then facts := facts.push record.fact
    | none => pure ()
  pure facts

/-- Current maximum revision, or zero for an empty store. -/
def latestRevision (store : RevisionStore) : Nat :=
  store.records.foldl (init := 0) fun current record => Nat.max current record.revision

/-- Append a checked update. Revisions may arrive out of order, but one logical
fact may have only one operation at each revision. -/
def append (store : RevisionStore) (record : RevisionedFact) : Except String RevisionStore := do
  unless record.fact.isGround do throw "revisioned fact must be ground"
  if store.records.any (fun current =>
      current.revision == record.revision && current.key == record.key) then
    throw "duplicate fact operation at the same revision"
  pure { store with records := store.records.push record }

end RevisionStore

/-- Sparse vector clock. Missing actor counters are zero. -/
structure VectorClock where
  entries : Array (Name × Nat) := #[]
  deriving Repr, Inhabited

namespace VectorClock

def valid (clock : VectorClock) : Bool :=
  clock.entries.all fun entry =>
    (clock.entries.filter fun candidate => candidate.1 == entry.1).size == 1

def counter (clock : VectorClock) (actor : Name) : Nat :=
  ((clock.entries.find? fun entry => entry.1 == actor).map (·.2)).getD 0

private def actors (left right : VectorClock) : Array Name :=
  (left.entries ++ right.entries).foldl (init := #[]) fun out entry =>
    if out.contains entry.1 then out else out.push entry.1

/-- Standard vector-clock strict order. -/
def before (left right : VectorClock) : Bool :=
  if !left.valid || !right.valid then false
  else
    let names := actors left right
    names.all (fun actor => left.counter actor <= right.counter actor) &&
    names.any (fun actor => left.counter actor < right.counter actor)

def concurrent (left right : VectorClock) : Bool :=
  !left.before right && !right.before left

end VectorClock

/-- Lamport timestamp overlay. It remains metadata and does not create core causal edges. -/
structure LamportClock where
  actor : Name
  counter : Nat
  deriving Repr, BEq, Inhabited

namespace LamportClock

def before (left right : LamportClock) : Bool := left.counter < right.counter

end LamportClock

/-- Hybrid logical-clock overlay. -/
structure HybridClock where
  actor : Name
  wallTime : Nat
  logical : Nat
  deriving Repr, BEq, Inhabited

namespace HybridClock

def before (left right : HybridClock) : Bool :=
  left.wallTime < right.wallTime ||
  (left.wallTime == right.wallTime && left.logical < right.logical)

end HybridClock

/-- Event plus optional clock metadata. -/
structure EventClock where
  event : Name
  vector : Option VectorClock := none
  lamport : Option LamportClock := none
  hybrid : Option HybridClock := none
  deriving Repr, Inhabited

namespace EventClock

/-- Clock metadata must not reverse an explicit core causal edge. -/
def consistentWith (left right : EventClock) (graph : CausalGraph) : Bool :=
  if !graph.before left.event right.event then true
  else
    let vectorOk := match left.vector, right.vector with
      | some l, some r => l.before r
      | _, _ => true
    let lamportOk := match left.lamport, right.lamport with
      | some l, some r => l.before r
      | _, _ => true
    let hybridOk := match left.hybrid, right.hybrid with
      | some l, some r => l.before r
      | _, _ => true
    vectorOk && lamportOk && hybridOk

end EventClock

end Zil
