import Zil.Engine.Provenance

namespace Zil.Impact

/-- Relations interpreted as `dependent -> dependency` by the default policy. -/
structure Policy where
  relations : Array Name
  deriving Repr, Inhabited

namespace Policy

/-- Project relations whose object changing can require review of the subject. -/
def default : Policy := {
  relations := #[
    `zil.dependsOn,
    `zil.uses,
    `zil.requires,
    `zil.validates,
    `zil.implements,
    `zil.formalizes,
    `zil.supports
  ]
}

end Policy

/-- One dependency edge with the provenance fact that established it. -/
structure Edge where
  dependent : Name
  dependency : Name
  relation : Name
  factId : Nat
  deriving Repr, BEq, Inhabited

/-- Native dependency graph extracted from one provenance closure. -/
structure Graph where
  nodes : Array Name := #[]
  edges : Array Edge := #[]
  deriving Repr, Inhabited

/-- One affected node and its deterministic shortest reverse-dependency path. -/
structure Impact where
  node : Name
  distance : Nat
  path : Array Edge
  deriving Repr, Inhabited

/-- Complete change-impact result. -/
structure Report where
  changed : Name
  known : Bool
  cyclicNodes : Array Name
  impacts : Array Impact
  deriving Repr, Inhabited

private def pushName (names : Array Name) (name : Name) : Array Name :=
  if names.contains name then names else names.push name

private def insertName (value : Name) : List Name → List Name
  | [] => [value]
  | head :: tail =>
      match compare value.toString head.toString with
      | .lt => value :: head :: tail
      | .eq => head :: tail
      | .gt => head :: insertName value tail

private def sortedNames (names : Array Name) : Array Name :=
  (names.foldl (init := []) fun out name => insertName name out).toArray

private def edgeOrder (left right : Edge) : Ordering :=
  match compare left.dependency.toString right.dependency.toString with
  | .lt => .lt
  | .gt => .gt
  | .eq =>
      match compare left.dependent.toString right.dependent.toString with
      | .lt => .lt
      | .gt => .gt
      | .eq =>
          match compare left.relation.toString right.relation.toString with
          | .lt => .lt
          | .gt => .gt
          | .eq => compare left.factId right.factId

private def insertEdge (value : Edge) : List Edge → List Edge
  | [] => [value]
  | head :: tail =>
      match edgeOrder value head with
      | .lt => value :: head :: tail
      | .eq => head :: tail
      | .gt => head :: insertEdge value tail

private def sortedEdges (edges : Array Edge) : Array Edge :=
  (edges.foldl (init := []) fun out edge => insertEdge edge out).toArray

private def nodeName? : Zil.Term → Option Name
  | .node node => some node.name
  | .var _ => none

private def edgeOf
    (policy : Policy)
    (node : Zil.Engine.Provenance.FactNode) : Option Edge := do
  if !policy.relations.contains node.fact.relation then none
  let dependent ← nodeName? node.fact.subject
  let dependency ← nodeName? node.fact.object
  pure {
    dependent
    dependency
    relation := node.fact.relation
    factId := node.id
  }

/-- Extract dependency edges from base and derived provenance facts. -/
def fromTrace
    (trace : Zil.Engine.Provenance.Trace)
    (policy : Policy := .default) : Graph :=
  let edges := sortedEdges (trace.facts.filterMap (edgeOf policy))
  let nodes := edges.foldl (init := #[]) fun out edge =>
    pushName (pushName out edge.dependent) edge.dependency
  { nodes := sortedNames nodes, edges }

/-- Build a dependency graph directly from a checked native program. -/
def fromProgram
    (program : Zil.Program)
    (policy : Policy := .default)
    (fuel : Nat := 64) : Except String Graph := do
  let trace ← Zil.Engine.Provenance.traceProgram program fuel
  pure (fromTrace trace policy)

namespace Graph

/-- Outgoing dependencies of one dependent node. -/
def outgoing (graph : Graph) (dependent : Name) : Array Edge :=
  graph.edges.filter fun edge => edge.dependent == dependent

/-- Reverse edges: nodes directly depending on the supplied dependency. -/
def reverse (graph : Graph) (dependency : Name) : Array Edge :=
  graph.edges.filter fun edge => edge.dependency == dependency

private def reaches
    (graph : Graph)
    (current goal : Name)
    (visited : Array Name)
    (fuel : Nat) : Bool :=
  match fuel with
  | 0 => false
  | fuel + 1 =>
      if visited.contains current then false
      else
        (graph.outgoing current).any fun edge =>
          edge.dependency == goal ||
          reaches graph edge.dependency goal (visited.push current) fuel

/-- Nodes participating in direct or transitive dependency cycles. -/
def cyclicNodes (graph : Graph) : Array Name :=
  sortedNames <| graph.nodes.filter fun node =>
    (graph.outgoing node).any fun edge =>
      edge.dependency == node ||
      reaches graph edge.dependency node #[node] (graph.nodes.size + 1)

end Graph

private structure Frontier where
  node : Name
  distance : Nat
  path : Array Edge

private structure SearchState where
  queue : List Frontier
  visited : Array Name
  impacts : Array Impact

private def enqueueDependents (graph : Graph) (state : SearchState) : SearchState :=
  match state.queue with
  | [] => state
  | current :: rest =>
      let initial : SearchState := { state with queue := rest }
      (graph.reverse current.node).foldl (init := initial) fun next edge =>
        if next.visited.contains edge.dependent then next
        else
          let path := current.path.push edge
          {
            queue := next.queue ++ [{
              node := edge.dependent
              distance := current.distance + 1
              path
            }]
            visited := next.visited.push edge.dependent
            impacts := next.impacts.push {
              node := edge.dependent
              distance := current.distance + 1
              path
            }
          }

private def search
    (graph : Graph)
    (state : SearchState) : Nat → SearchState
  | 0 => state
  | fuel + 1 =>
      if state.queue.isEmpty then state
      else search graph (enqueueDependents graph state) fuel

/-- Compute one deterministic shortest impact path per reverse-dependent node. -/
def analyze (graph : Graph) (changed : Name) : Report :=
  let known := graph.nodes.contains changed
  let initial : SearchState := {
    queue := if known then [{ node := changed, distance := 0, path := #[] }] else []
    visited := if known then #[changed] else #[]
    impacts := #[]
  }
  let result := search graph initial (graph.nodes.size + 1)
  {
    changed
    known
    cyclicNodes := graph.cyclicNodes
    impacts := result.impacts
  }

private def edgeText (edge : Edge) : String :=
  edge.dependent.toString ++ "#" ++ edge.relation.toString ++ "@" ++
  edge.dependency.toString ++ ":fact=" ++ toString edge.factId

private def pathText (path : Array Edge) : String :=
  String.intercalate "|" (path.toList.map edgeText)

private def namesText (names : Array Name) : String :=
  String.intercalate "," (names.toList.map Name.toString)

/-- Stable dependency graph report. -/
def renderGraph (graph : Graph) : String :=
  let rows := graph.edges.toList.map fun edge =>
    String.intercalate "\t" [
      "edge", edge.dependent.toString, edge.relation.toString,
      edge.dependency.toString, toString edge.factId
    ]
  String.intercalate "\n" <|
    ["ZIL-DEPENDENCY-GRAPH\t1",
     "nodes\t" ++ toString graph.nodes.size,
     "edges\t" ++ toString graph.edges.size,
     "cycles\t" ++ namesText graph.cyclicNodes] ++ rows ++ [""]

/-- Stable change-impact report. -/
def renderImpact (report : Report) : String :=
  let rows := report.impacts.toList.map fun impact =>
    String.intercalate "\t" [
      "impact", impact.node.toString, toString impact.distance,
      if impact.distance == 1 then "direct" else "transitive",
      pathText impact.path
    ]
  String.intercalate "\n" <|
    ["ZIL-CHANGE-IMPACT\t1",
     "status\t" ++ (if report.known then "known" else "unknown"),
     "changed\t" ++ report.changed.toString,
     "cycles\t" ++ namesText report.cyclicNodes,
     "affected\t" ++ toString report.impacts.size] ++ rows ++ [""]

end Zil.Impact
