import Zil.Impact
import Zil.Formalization

namespace Zil.AgentContext

/-- Inputs used to construct one deterministic agent handoff bundle. -/
structure Request where
  taskId : String
  agentId : String
  scope : String
  changedNodes : Array Name
  requestedQueries : Array Name := #[]
  requestedTargets : Array Name := #[]
  deriving Repr, Inhabited

/-- One affected node associated with the changed root that reached it. -/
structure ImpactEntry where
  changed : Name
  node : Name
  distance : Nat
  path : Array Zil.Impact.Edge
  deriving Repr, Inhabited

/-- Deterministic native context package for one agent task. -/
structure Bundle where
  taskId : String
  agentId : String
  scope : String
  moduleName : Name
  changedNodes : Array Name
  unknownChangedNodes : Array Name
  affectedNodes : Array Name
  cycleNodes : Array Name
  impacts : Array ImpactEntry
  relevantFacts : Array Zil.Engine.Provenance.FactNode
  originatingRules : Array Name
  selectedQueries : Array Zil.Query
  selectedTargets : Array Zil.Formalization.Target
  missingQueries : Array Name
  missingTargets : Array Name
  complete : Bool
  issues : Array String
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

private def termNode? : Zil.Term → Option Name
  | .node node => some node.name
  | .var _ => none

private def factTouches (nodes : Array Name) (fact : Zil.RelExpr) : Bool :=
  let subjectMatches := (termNode? fact.subject).map nodes.contains |>.getD false
  let objectMatches := (termNode? fact.object).map nodes.contains |>.getD false
  subjectMatches || objectMatches

private def relationNames (facts : Array Zil.Engine.Provenance.FactNode) : Array Name :=
  facts.foldl (init := #[]) fun out node => pushName out node.fact.relation

private def queryTouches (relations : Array Name) (query : Zil.Query) : Bool :=
  (query.premises ++ query.negativePremises).any fun premise =>
    relations.contains premise.relation

private def ruleNames (facts : Array Zil.Engine.Provenance.FactNode) : Array Name :=
  sortedNames <| facts.foldl (init := #[]) fun out node =>
    match node.origin with
    | .base => out
    | .rule rule _ _ _ => pushName out rule

private def findQuery? (program : Zil.Program) (name : Name) : Option Zil.Query :=
  program.queries.find? fun query => query.name == name

private def findTarget?
    (targets : Array Zil.Formalization.Target)
    (name : Name) : Option Zil.Formalization.Target :=
  targets.find? fun target => target.id == name

private def containsText (text needle : String) : Bool :=
  !needle.isEmpty && (text.splitOn needle).length > 1

private def targetTouches
    (nodes : Array Name)
    (target : Zil.Formalization.Target) : Bool :=
  nodes.any fun node =>
    let token := node.toString
    containsText target.id.toString token ||
    containsText target.moduleName token ||
    containsText target.file token ||
    containsText target.declaration token

private def selectedQueries
    (program : Zil.Program)
    (requested : Array Name)
    (relations : Array Name) : Array Zil.Query :=
  if requested.isEmpty then
    program.queries.filter (queryTouches relations)
  else
    requested.filterMap (findQuery? program)

private def selectedTargets
    (targets : Array Zil.Formalization.Target)
    (requested : Array Name)
    (nodes : Array Name) : Array Zil.Formalization.Target :=
  if requested.isEmpty then
    targets.filter (targetTouches nodes)
  else
    requested.filterMap (findTarget? targets)

private def missingNames
    (requested : Array Name)
    (exists : Name → Bool) : Array Name :=
  sortedNames <| requested.filter fun name => !exists name

private def impactEntries
    (graph : Zil.Impact.Graph)
    (changed : Array Name) : Array ImpactEntry :=
  changed.foldl (init := #[]) fun out root =>
    let report := Zil.Impact.analyze graph root
    report.impacts.foldl (init := out) fun current impact =>
      current.push {
        changed := root
        node := impact.node
        distance := impact.distance
        path := impact.path
      }

private def affectedNames (entries : Array ImpactEntry) : Array Name :=
  sortedNames <| entries.foldl (init := #[]) fun out entry => pushName out entry.node

/-- Build one context bundle from checked native program semantics. -/
def build
    (program : Zil.Program)
    (request : Request)
    (fuel : Nat := 64) : Except String Bundle := do
  unless program.valid do throw "agent context requires a structurally valid program"
  if request.taskId.isEmpty then throw "agent context task ID must be nonempty"
  if request.agentId.isEmpty then throw "agent context agent ID must be nonempty"
  if request.scope.isEmpty then throw "agent context scope must be nonempty"
  if request.changedNodes.isEmpty then throw "agent context requires at least one changed node"
  let moduleName ← match program.moduleName with
    | some value => pure value
    | none => throw "agent context requires MODULE"
  let trace ← Zil.Engine.Provenance.traceProgram program fuel
  let graph := Zil.Impact.fromTrace trace
  let changed := sortedNames request.changedNodes
  let unknownChanged := changed.filter fun name => !graph.nodes.contains name
  let impacts := impactEntries graph changed
  let affected := affectedNames impacts
  let scopeNodes := sortedNames <| changed.foldl (init := affected) pushName
  let facts := trace.facts.filter fun node => factTouches scopeNodes node.fact
  let relations := relationNames facts
  let queries := selectedQueries program request.requestedQueries relations
  let missingQueries := missingNames request.requestedQueries fun name =>
    (findQuery? program name).isSome
  let targets ← Zil.Formalization.fromProgram program
  let selectedTargets := selectedTargets targets request.requestedTargets scopeNodes
  let missingTargets := missingNames request.requestedTargets fun name =>
    (findTarget? targets name).isSome
  let mut issues : Array String := #[]
  for name in unknownChanged do
    issues := issues.push s!"unknown-changed-node:{name}"
  for name in missingQueries do
    issues := issues.push s!"missing-query:{name}"
  for name in missingTargets do
    issues := issues.push s!"missing-formalization-target:{name}"
  pure {
    taskId := request.taskId
    agentId := request.agentId
    scope := request.scope
    moduleName
    changedNodes := changed
    unknownChangedNodes := unknownChanged
    affectedNodes := affected
    cycleNodes := graph.cyclicNodes
    impacts
    relevantFacts := facts
    originatingRules := ruleNames facts
    selectedQueries := queries
    selectedTargets
    missingQueries
    missingTargets
    complete := issues.isEmpty
    issues
  }

private def namesText (names : Array Name) : String :=
  String.intercalate "," (names.toList.map Name.toString)

private def idsText (nodes : Array Zil.Engine.Provenance.FactNode) : String :=
  String.intercalate "," (nodes.toList.map fun node => toString node.id)

private def pathText (path : Array Zil.Impact.Edge) : String :=
  String.intercalate "|" (path.toList.map fun edge =>
    edge.dependent.toString ++ "#" ++ edge.relation.toString ++ "@" ++
    edge.dependency.toString ++ ":fact=" ++ toString edge.factId)

private def factRows (facts : Array Zil.Engine.Provenance.FactNode) : List String :=
  facts.toList.map fun node =>
    String.intercalate "\t" [
      "fact", toString node.id, toString node.stratum,
      Zil.Codec.encodeRelation node.fact
    ]

private def impactRows (impacts : Array ImpactEntry) : List String :=
  impacts.toList.map fun impact =>
    String.intercalate "\t" [
      "impact", impact.changed.toString, impact.node.toString,
      toString impact.distance, pathText impact.path
    ]

private def queryRows (queries : Array Zil.Query) : List String :=
  queries.toList.map fun query =>
    String.intercalate "\t" [
      "query", query.name.toString,
      namesText query.select,
      namesText ((query.premises ++ query.negativePremises).map (·.relation))
    ]

private def targetRows (targets : Array Zil.Formalization.Target) : List String :=
  targets.toList.map fun target =>
    String.intercalate "\t" [
      "target", target.id.toString, target.status.token,
      toString target.priority, target.moduleName,
      target.file, target.declaration,
      namesText target.dependencies
    ]

/-- Canonical context bytes. A durable context bundle ID is `sha256(report-bytes)`. -/
def render (bundle : Bundle) : String :=
  String.intercalate "\n" <|
    ["ZIL-AGENT-CONTEXT\t1",
     "status\t" ++ (if bundle.complete then "complete" else "incomplete"),
     "task\t" ++ bundle.taskId,
     "agent\t" ++ bundle.agentId,
     "scope\t" ++ bundle.scope,
     "module\t" ++ bundle.moduleName.toString,
     "changed\t" ++ namesText bundle.changedNodes,
     "unknown-changed\t" ++ namesText bundle.unknownChangedNodes,
     "affected\t" ++ namesText bundle.affectedNodes,
     "cycles\t" ++ namesText bundle.cycleNodes,
     "fact-ids\t" ++ idsText bundle.relevantFacts,
     "originating-rules\t" ++ namesText bundle.originatingRules,
     "selected-queries\t" ++ namesText (bundle.selectedQueries.map (·.name)),
     "selected-targets\t" ++ namesText (bundle.selectedTargets.map (·.id)),
     "issues\t" ++ String.intercalate "," bundle.issues.toList] ++
    impactRows bundle.impacts ++ factRows bundle.relevantFacts ++
    queryRows bundle.selectedQueries ++ targetRows bundle.selectedTargets ++ [""]

end Zil.AgentContext
