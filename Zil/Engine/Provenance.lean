module

public import Zil.Core.Program
public import Zil.Engine.Query
public import Zil.Codec.Canonical
import Std.Data.HashMap

@[expose] public section


namespace Zil.Engine.Provenance

/-- The deterministic first origin recorded for one fact. -/
inductive Origin where
  | base
  | rule
      (ruleName : Name)
      (premiseFactIds : Array Nat)
      (negativeChecks : Array Zil.RelExpr)
      (binding : Zil.Engine.Binding)
  deriving Repr, Inhabited

/-- One fact in the provenance closure. -/
structure FactNode where
  id : Nat
  fact : Zil.RelExpr
  origin : Origin
  stratum : Nat
  deriving Repr, Inhabited

/-- Checked closure plus deterministic provenance nodes. -/
structure Trace where
  facts : Array FactNode := #[]
  deriving Repr, Inhabited

/-- One binding together with the positive facts that witness it. -/
structure WitnessState where
  binding : Zil.Engine.Binding := #[]
  premiseFactIds : Array Nat := #[]
  deriving Repr, Inhabited

/-- One concrete query witness. -/
structure QueryWitness where
  query : Name
  selected : Array (Name × Zil.Term)
  premiseFactIds : Array Nat
  binding : Zil.Engine.Binding
  deriving Repr, Inhabited

/-- Exact fact/authorization explanation over one trace. -/
structure FactExplanation where
  target : Zil.RelExpr
  allowed : Bool
  factId : Option Nat
  source : String
  deriving Repr, Inhabited

namespace Trace

/-- Find a provenance node by semantic fact equality. -/
def findFact? (trace : Trace) (target : Zil.RelExpr) : Option FactNode :=
  trace.facts.find? fun node => node.fact.semanticallyEqual target

/-- Find a provenance node by stable ID. -/
def findId? (trace : Trace) (id : Nat) : Option FactNode :=
  trace.facts.find? fun node => node.id == id

end Trace

def unifyTerm
    (pattern value : Zil.Term)
    (binding : Zil.Engine.Binding) : Option Zil.Engine.Binding :=
  match pattern with
  | .var name => binding.bind name value
  | .node node => if value == .node node then some binding else none

def unifyAttrValue
    (pattern value : Zil.AttrValue)
    (binding : Zil.Engine.Binding) : Option Zil.Engine.Binding :=
  match pattern, value with
  | .term patternTerm, .term valueTerm => unifyTerm patternTerm valueTerm binding
  | _, _ => if pattern == value then some binding else none

def unifyAttributes
    (patterns facts : Array Zil.Attribute)
    (binding : Zil.Engine.Binding) : Option Zil.Engine.Binding :=
  patterns.foldl (init := some binding) fun state pattern =>
    match state with
    | none => none
    | some current =>
        match Zil.Attribute.find? facts pattern.key with
        | none => none
        | some fact => unifyAttrValue pattern.value fact.value current

def unifyRelation
    (pattern fact : Zil.RelExpr)
    (binding : Zil.Engine.Binding) : Option Zil.Engine.Binding :=
  if pattern.relation != fact.relation then none
  else
    match unifyTerm pattern.subject fact.subject binding with
    | none => none
    | some next =>
        match unifyTerm pattern.object fact.object next with
        | none => none
        | some endpoints => unifyAttributes pattern.attrs fact.attrs endpoints

def instantiateTerm
    (binding : Zil.Engine.Binding) : Zil.Term → Option Zil.Term
  | .node node => some (.node node)
  | .var name => binding.lookup name

def instantiateAttrValue
    (binding : Zil.Engine.Binding) : Zil.AttrValue → Option Zil.AttrValue
  | .term term => (instantiateTerm binding term).map .term
  | value => some value

def instantiateRelation
    (binding : Zil.Engine.Binding)
    (relation : Zil.RelExpr) : Option Zil.RelExpr := do
  let subject ← instantiateTerm binding relation.subject
  let object ← instantiateTerm binding relation.object
  let mut attrs : Array Zil.Attribute := #[]
  for entry in relation.attrs do
    let value ← instantiateAttrValue binding entry.value
    attrs := attrs.push { entry with value }
  pure { relation with subject, object, attrs }

/-- Nodes by relation, by relation and subject, and by relation and object, each bucket in the order the nodes were added, which is their
number. A lookup returns the nodes that a scan of all of them would keep, in the order the scan would visit them, so a derivation that
uses the index visits its candidates exactly as it did before and builds the same trace. -/
structure NodeIndex where
  byRelation : Std.HashMap Name (Array FactNode) := {}
  bySubject : Std.HashMap (Name × Zil.Term) (Array FactNode) := {}
  byObject : Std.HashMap (Name × Zil.Term) (Array FactNode) := {}
  deriving Inhabited

namespace NodeIndex

/-- Grow a bucket in place (reading it out and inserting a longer copy would copy the whole bucket for every node). -/
def appendBucket {key : Type} [BEq key] [Hashable key]
    (index : Std.HashMap key (Array FactNode)) (value : key) (node : FactNode) : Std.HashMap key (Array FactNode) :=
  if index.contains value then index.modify value (·.push node) else index.insert value #[node]

def insert (index : NodeIndex) (node : FactNode) : NodeIndex :=
  { byRelation := appendBucket index.byRelation node.fact.relation node
    bySubject := appendBucket index.bySubject (node.fact.relation, node.fact.subject) node
    byObject := appendBucket index.byObject (node.fact.relation, node.fact.object) node }

def ofNodes (nodes : Array FactNode) : NodeIndex := nodes.foldl insert {}

/-- Is there a node whose fact equals `fact`? Equal facts have the same relation and subject, so only that bucket is searched. -/
def containsSemantic (index : NodeIndex) (fact : Zil.RelExpr) : Bool :=
  (index.bySubject.getD (fact.relation, fact.subject) #[]).any (·.fact.semanticallyEqual fact)

/-- The nodes that can match `pattern` under `binding`, narrowed by an endpoint that is fixed or already bound. -/
def candidates (index : NodeIndex) (pattern : Zil.RelExpr) (binding : Zil.Engine.Binding) : Array FactNode :=
  let known : Zil.Term → Option Zil.Term
    | .node node => some (.node node)
    | .var name => binding.lookup name
  match known pattern.subject, known pattern.object with
  | some subject, _ => index.bySubject.getD (pattern.relation, subject) #[]
  | none, some object => index.byObject.getD (pattern.relation, object) #[]
  | none, none => index.byRelation.getD pattern.relation #[]

end NodeIndex

def extendWitnessesIndexed
    (index : NodeIndex)
    (patterns : Array Zil.RelExpr)
    (seed : WitnessState := {}) : Array WitnessState :=
  patterns.foldl (init := #[seed]) fun states pattern =>
    states.foldl (init := #[]) fun out state =>
      (index.candidates pattern state.binding).foldl (init := out) fun current node =>
        match unifyRelation pattern node.fact state.binding with
        | none => current
        | some binding =>
            current.push {
              binding
              premiseFactIds := state.premiseFactIds.push node.id
            }

def extendWitnesses
    (facts : Array FactNode)
    (patterns : Array Zil.RelExpr)
    (seed : WitnessState := {}) : Array WitnessState :=
  extendWitnessesIndexed (NodeIndex.ofNodes facts) patterns seed

def hasMatchIndexed
    (index : NodeIndex)
    (pattern : Zil.RelExpr)
    (binding : Zil.Engine.Binding) : Bool :=
  (index.candidates pattern binding).any fun node => (unifyRelation pattern node.fact binding).isSome

def hasMatch
    (facts : Array FactNode)
    (pattern : Zil.RelExpr)
    (binding : Zil.Engine.Binding) : Bool :=
  facts.any fun node => (unifyRelation pattern node.fact binding).isSome

def negativesHoldIndexed
    (index : NodeIndex)
    (patterns : Array Zil.RelExpr)
    (binding : Zil.Engine.Binding) : Bool :=
  patterns.all fun pattern => !hasMatchIndexed index pattern binding

def negativesHold
    (facts : Array FactNode)
    (patterns : Array Zil.RelExpr)
    (binding : Zil.Engine.Binding) : Bool :=
  patterns.all fun pattern => !hasMatch facts pattern binding

/-- The trace of the database facts, each once, in order. -/
def baseTrace (facts : Array Zil.RelExpr) : Trace :=
  let (trace, _) := facts.foldl (init := (({} : Trace), ({} : NodeIndex))) fun (trace, index) fact =>
    if index.containsSemantic fact then (trace, index)
    else
      let node : FactNode := { id := trace.facts.size, fact, origin := .base, stratum := 0 }
      ({ facts := trace.facts.push node }, index.insert node)
  trace

structure Candidate where
  fact : Zil.RelExpr
  origin : Origin

def deriveRule
    (positiveFacts negativeFacts : NodeIndex)
    (rule : Zil.Rule) : Array Candidate :=
  (extendWitnessesIndexed positiveFacts rule.premises).filterMap fun state =>
    if negativesHoldIndexed negativeFacts rule.negativePremises state.binding then
      match instantiateRelation state.binding rule.conclusion with
      | none => none
      | some fact =>
          let negatives := rule.negativePremises.filterMap (instantiateRelation state.binding)
          some {
            fact
            origin := .rule rule.name state.premiseFactIds negatives state.binding
          }
    else none

/-- Add a derived fact if no node holds it yet. -/
def appendCandidate
    (trace : Trace)
    (index : NodeIndex)
    (candidate : Candidate)
    (stratum : Nat) : Trace × NodeIndex :=
  if index.containsSemantic candidate.fact then (trace, index)
  else
    let node : FactNode := { id := trace.facts.size, fact := candidate.fact, origin := candidate.origin, stratum }
    ({ facts := trace.facts.push node }, index.insert node)

def rulesAt
    (rules : Array Zil.Rule)
    (strata : Zil.Engine.Strata)
    (level : Nat) : Array Zil.Rule :=
  rules.filter fun rule => strata.lookup rule.conclusion.relation == level

def maxStratum (strata : Zil.Engine.Strata) : Nat :=
  strata.foldl (init := 0) fun current entry => Nat.max current entry.2

/-- Close one stratum, and say whether the fixpoint was reached (see `Zil.Engine.closeOneStratum`). The rules are applied in order, and a
rule sees the facts that the rules before it added in the same round; the negated conditions are read against the facts that were there
when the stratum began. -/
def closeOneStratum
    (initial : Trace)
    (rules : Array Zil.Rule)
    (level fuel : Nat) : Trace × Bool :=
  let negativeIndex := NodeIndex.ofNodes initial.facts
  let rec loop (trace : Trace) (index : NodeIndex) : Nat → Trace × Bool
    | 0 => (trace, false)
    | remaining + 1 =>
        let (next, nextIndex) := rules.foldl (init := (trace, index)) fun (current, currentIndex) rule =>
          (deriveRule currentIndex negativeIndex rule).foldl (init := (current, currentIndex)) fun (out, outIndex) candidate =>
            appendCandidate out outIndex candidate level
        if next.facts.size == trace.facts.size then (next, true) else loop next nextIndex remaining
  loop initial (NodeIndex.ofNodes initial.facts) fuel

/-- Close every stratum in order; the second component is the lowest stratum whose rounds ran out before its fixpoint, if any. -/
def executeLevels
    (trace : Trace)
    (rules : Array Zil.Rule)
    (strata : Zil.Engine.Strata)
    (fuel : Nat) : Nat → Nat → Trace × Option Nat
  | _, 0 => (trace, none)
  | level, remaining + 1 =>
      let (closed, converged) := closeOneStratum trace (rulesAt rules strata level) level fuel
      let (final, unfinished) := executeLevels closed rules strata fuel (level + 1) remaining
      (final, if converged then unfinished else some level)

/-- Compute checked stratified closure with one deterministic origin per fact. It fails, and does not return a partial trace, when the
rounds run out before a stratum reaches its fixpoint. -/
def traceChecked
    (facts : Array Zil.RelExpr)
    (rules : Array Zil.Rule)
    (fuel : Nat := Zil.Engine.defaultFuel) : Except String Trace := do
  let strata ← Zil.Engine.stratify rules
  let initial := baseTrace facts
  let (trace, unfinished) := executeLevels initial rules strata fuel 0 (maxStratum strata + 1)
  match unfinished with
  | none => pure trace
  | some level =>
      throw s!"closure did not reach its fixpoint in stratum {level} within {fuel} rounds; the facts derived so far are not the closure"

/-- Compute provenance for one complete native program. -/
def traceProgram (program : Zil.Program) (fuel : Nat := Zil.Engine.defaultFuel) : Except String Trace := do
  unless program.valid do throw "provenance requires a structurally valid program"
  traceChecked program.facts program.allRules fuel

def queryStates (trace : Trace) (query : Zil.Query) : Array WitnessState :=
  if !query.selectedVariablesBound || !query.safe then #[]
  else
    let index := NodeIndex.ofNodes trace.facts
    (extendWitnessesIndexed index query.premises).filter fun state =>
      negativesHoldIndexed index query.negativePremises state.binding

/-- Return concrete positive-premise witnesses for every query result. -/
def queryWitnesses (trace : Trace) (query : Zil.Query) : Array QueryWitness :=
  (queryStates trace query).filterMap fun state =>
    let selected := query.select.filterMap fun name =>
      (state.binding.lookup name).map fun term => (name, term)
    if selected.size != query.select.size then none
    else some {
      query := query.name
      selected
      premiseFactIds := state.premiseFactIds
      binding := state.binding
    }

/-- Explain one exact fact after checked closure. -/
def explainFact (trace : Trace) (target : Zil.RelExpr) : FactExplanation :=
  match trace.findFact? target with
  | none => { target, allowed := false, factId := none, source := "none" }
  | some node =>
      let source := match node.origin with
        | .base => "base"
        | .rule _ _ _ _ => "rule"
      { target, allowed := true, factId := some node.id, source }

def termText : Zil.Term → String
  | .node node => node.name.toString
  | .var name => "?" ++ name.toString

def bindingText (binding : Zil.Engine.Binding) : String :=
  String.intercalate "," (binding.toList.map fun pair =>
    pair.1.toString ++ "=" ++ termText pair.2)

def idsText (ids : Array Nat) : String :=
  String.intercalate "," (ids.toList.map toString)

def negativeText (relations : Array Zil.RelExpr) : String :=
  String.intercalate "|" (relations.toList.map Zil.Codec.encodeRelation)

def factRows (trace : Trace) : List String :=
  trace.facts.toList.flatMap fun node =>
    let fact := "fact\t" ++ toString node.id ++ "\t" ++ toString node.stratum ++
      "\t" ++ Zil.Codec.encodeRelation node.fact
    let origin := match node.origin with
      | .base => "origin\t" ++ toString node.id ++ "\tbase"
      | .rule rule premises negatives binding =>
          String.intercalate "\t" [
            "origin", toString node.id, "rule", rule.toString,
            idsText premises, negativeText negatives, bindingText binding
          ]
    [fact, origin]

/-- Stable complete provenance report. -/
def renderTrace (trace : Trace) : String :=
  String.intercalate "\n" <|
    ["ZIL-PROVENANCE\t1", "facts\t" ++ toString trace.facts.size] ++
    factRows trace ++ [""]

/-- Stable query-witness report including the supporting closure. -/
def renderQueryWitnesses
    (trace : Trace)
    (query : Zil.Query)
    (witnesses : Array QueryWitness) : String :=
  let rows := witnesses.toList.map fun witness =>
    String.intercalate "\t" [
      "witness", witness.query.toString,
      bindingText witness.selected,
      idsText witness.premiseFactIds,
      bindingText witness.binding
    ]
  String.intercalate "\n" <|
    ["ZIL-QUERY-EXPLANATION\t1",
     "query\t" ++ query.name.toString,
     "witnesses\t" ++ toString witnesses.size] ++ rows ++
    ["-- provenance --"] ++ factRows trace ++ [""]

/-- Stable exact-fact explanation including the supporting closure. -/
def renderFactExplanation (trace : Trace) (explanation : FactExplanation) : String :=
  String.intercalate "\n" <|
    ["ZIL-FACT-EXPLANATION\t1",
     "decision\t" ++ (if explanation.allowed then "present" else "absent"),
     "source\t" ++ explanation.source,
     "fact-id\t" ++ (explanation.factId.map toString).getD "",
     "target\t" ++ Zil.Codec.encodeRelation explanation.target,
     "-- provenance --"] ++ factRows trace ++ [""]

end Zil.Engine.Provenance
