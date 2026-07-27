module

public import Zil.Datalog.Basic
public import Zil.Datalog.Revision

@[expose] public section

namespace Zil.Datalog

abbrev FactId := Nat

structure FactIndexEntry where
  node : Value
  relation : String
  factIds : List FactId
  deriving Repr, DecidableEq, Inhabited

structure RelationIndexEntry where
  relation : String
  polarity : RuleDependencyPolarity
  adjacent : List String
  deriving Repr, DecidableEq, Inhabited

/-- Frozen indexes for general ZIL facts and rule dependencies. Outgoing facts
map object to subject; incoming facts map subject back to object. -/
structure KnowledgeIndex where
  facts : List Atom
  outgoing : List FactIndexEntry
  incoming : List FactIndexEntry
  ruleOutgoing : List RelationIndexEntry
  ruleIncoming : List RelationIndexEntry
  deriving Repr, DecidableEq, Inhabited

def insertFactId (entries : List FactIndexEntry) (node : Value)
    (relation : String) (factId : FactId) : List FactIndexEntry :=
  match entries with
  | [] => [{ node, relation, factIds := [factId] }]
  | entry :: rest =>
      if entry.node == node && entry.relation == relation then
        { entry with factIds := entry.factIds ++ [factId] } :: rest
      else entry :: insertFactId rest node relation factId

def insertRelation (entries : List RelationIndexEntry) (relation : String)
    (polarity : RuleDependencyPolarity) (adjacent : String) : List RelationIndexEntry :=
  match entries with
  | [] => [{ relation, polarity, adjacent := [adjacent] }]
  | entry :: rest =>
      if entry.relation == relation && entry.polarity == polarity then
        { entry with adjacent := (entry.adjacent ++ [adjacent]).eraseDups } :: rest
      else entry :: insertRelation rest relation polarity adjacent

def KnowledgeIndex.build (program : Program) : KnowledgeIndex :=
  let factIndexes := program.facts.zipIdx.foldl (fun indexes indexed =>
    let atom := indexed.1
    let factId := indexed.2
    (insertFactId indexes.1 atom.object atom.relation factId,
      insertFactId indexes.2 atom.subject atom.relation factId)) ([], [])
  let ruleIndexes := program.dependencies.foldl (fun indexes dependency =>
    (insertRelation indexes.1 dependency.source dependency.polarity dependency.target,
      insertRelation indexes.2 dependency.target dependency.polarity dependency.source)) ([], [])
  { facts := program.facts
    outgoing := factIndexes.1
    incoming := factIndexes.2
    ruleOutgoing := ruleIndexes.1
    ruleIncoming := ruleIndexes.2 }

def FactIndexEntry.matches (entry : FactIndexEntry) (node : Value)
    (relations : List String) : Bool :=
  entry.node == node && (relations.isEmpty || relations.contains entry.relation)

def KnowledgeIndex.outgoingFactIds (index : KnowledgeIndex) (node : Value)
    (relations : List String := []) : List FactId :=
  (index.outgoing.filter (·.matches node relations)).flatMap (·.factIds)

def KnowledgeIndex.incomingFactIds (index : KnowledgeIndex) (node : Value)
    (relations : List String := []) : List FactId :=
  (index.incoming.filter (·.matches node relations)).flatMap (·.factIds)

def KnowledgeIndex.fact? (index : KnowledgeIndex) (factId : FactId) : Option Atom :=
  index.facts[factId]?

inductive TraversalDirection where
  | forward
  | reverse
  deriving Repr, DecidableEq, Inhabited

structure TraversalLimits where
  maxDepth : Nat := 32
  maxNodes : Nat := 4096
  maxBranching : Nat := 256
  deriving Repr, DecidableEq, Inhabited

structure TraversalResult where
  direct : List Value := []
  transitive : List Value := []
  truncated : Bool := false
  deriving Repr, DecidableEq, Inhabited

def KnowledgeIndex.neighbors (index : KnowledgeIndex) (direction : TraversalDirection)
    (relations : List String) (node : Value) : List Value :=
  let ids := match direction with
    | .forward => index.outgoingFactIds node relations
    | .reverse => index.incomingFactIds node relations
  (ids.filterMap fun factId => index.fact? factId |>.map fun atom =>
    match direction with | .forward => atom.subject | .reverse => atom.object).eraseDups

def KnowledgeIndex.traverseAux (index : KnowledgeIndex)
    (direction : TraversalDirection) (relations : List String) (limits : TraversalLimits)
    (root : Value) :
    Nat → List Value → List Value → Bool → List Value × Bool
  | 0, frontier, visited, truncated => (visited, truncated || !frontier.isEmpty)
  | depth + 1, frontier, visited, truncated =>
      if frontier.isEmpty || visited.length ≥ limits.maxNodes then
        (visited, truncated || (!frontier.isEmpty && visited.length ≥ limits.maxNodes))
      else
        let candidates := (frontier.flatMap (index.neighbors direction relations)).eraseDups
          |>.filter fun node => node != root && !visited.contains node
        let branchTruncated := candidates.length > limits.maxBranching
        let branched := candidates.take limits.maxBranching
        let capacity := limits.maxNodes - visited.length
        let admitted := branched.take capacity
        let nodeTruncated := branched.length > capacity
        index.traverseAux direction relations limits root depth admitted (visited ++ admitted)
          (truncated || branchTruncated || nodeTruncated)

/-- Bounded cycle-safe traversal. The start node is excluded. -/
def KnowledgeIndex.traverse (index : KnowledgeIndex) (direction : TraversalDirection)
    (start : Value) (relations : List String := [])
    (limits : TraversalLimits := {}) : TraversalResult :=
  let rawDirect := index.neighbors direction relations start
  let directTruncated := rawDirect.length > limits.maxBranching ||
    rawDirect.length > limits.maxNodes
  let direct := rawDirect.take limits.maxBranching |>.take limits.maxNodes
  let result := index.traverseAux direction relations limits start
    (limits.maxDepth - 1) direct direct directTruncated
  { direct, transitive := result.1, truncated := result.2 }

def KnowledgeIndex.dependencies (index : KnowledgeIndex) (node : Value)
    (relations : List String := []) (limits : TraversalLimits := {}) : TraversalResult :=
  index.traverse .forward node relations limits

def KnowledgeIndex.impact (index : KnowledgeIndex) (changed : Value)
    (relations : List String := []) (limits : TraversalLimits := {}) : TraversalResult :=
  index.traverse .reverse changed relations limits

def KnowledgeIndex.relationNeighbors (entries : List RelationIndexEntry)
    (relation : String) (polarity : Option RuleDependencyPolarity := none) : List String :=
  (entries.filter fun entry => entry.relation == relation &&
    polarity.all fun expected => entry.polarity == expected).flatMap (·.adjacent) |>.eraseDups

structure FrozenKnowledge where
  revision : KnowledgeRevision
  program : Program
  index : KnowledgeIndex
  deriving Repr, DecidableEq, Inhabited

def FrozenKnowledge.build (revision : KnowledgeRevision) (program : Program) : FrozenKnowledge :=
  { revision, program, index := KnowledgeIndex.build program }

end Zil.Datalog
