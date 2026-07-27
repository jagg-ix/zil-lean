import Zil.Core.Program
import Zil.Engine.Query
import Zil.Codec.Canonical

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

private def unifyTerm
    (pattern value : Zil.Term)
    (binding : Zil.Engine.Binding) : Option Zil.Engine.Binding :=
  match pattern with
  | .var name => binding.bind name value
  | .node node => if value == .node node then some binding else none

private def unifyAttrValue
    (pattern value : Zil.AttrValue)
    (binding : Zil.Engine.Binding) : Option Zil.Engine.Binding :=
  match pattern, value with
  | .term patternTerm, .term valueTerm => unifyTerm patternTerm valueTerm binding
  | _, _ => if pattern == value then some binding else none

private def unifyAttributes
    (patterns facts : Array Zil.Attribute)
    (binding : Zil.Engine.Binding) : Option Zil.Engine.Binding :=
  patterns.foldl (init := some binding) fun state pattern =>
    match state with
    | none => none
    | some current =>
        match Zil.Attribute.find? facts pattern.key with
        | none => none
        | some fact => unifyAttrValue pattern.value fact.value current

private def unifyRelation
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

private def instantiateTerm
    (binding : Zil.Engine.Binding) : Zil.Term → Option Zil.Term
  | .node node => some (.node node)
  | .var name => binding.lookup name

private def instantiateAttrValue
    (binding : Zil.Engine.Binding) : Zil.AttrValue → Option Zil.AttrValue
  | .term term => (instantiateTerm binding term).map .term
  | value => some value

private def instantiateRelation
    (binding : Zil.Engine.Binding)
    (relation : Zil.RelExpr) : Option Zil.RelExpr := do
  let subject ← instantiateTerm binding relation.subject
  let object ← instantiateTerm binding relation.object
  let mut attrs : Array Zil.Attribute := #[]
  for entry in relation.attrs do
    let value ← instantiateAttrValue binding entry.value
    attrs := attrs.push { entry with value }
  pure { relation with subject, object, attrs }

private def extendWitnesses
    (facts : Array FactNode)
    (patterns : Array Zil.RelExpr)
    (seed : WitnessState := {}) : Array WitnessState :=
  patterns.foldl (init := #[seed]) fun states pattern =>
    states.foldl (init := #[]) fun out state =>
      facts.foldl (init := out) fun current node =>
        match unifyRelation pattern node.fact state.binding with
        | none => current
        | some binding =>
            current.push {
              binding
              premiseFactIds := state.premiseFactIds.push node.id
            }

private def hasMatch
    (facts : Array FactNode)
    (pattern : Zil.RelExpr)
    (binding : Zil.Engine.Binding) : Bool :=
  facts.any fun node => (unifyRelation pattern node.fact binding).isSome

private def negativesHold
    (facts : Array FactNode)
    (patterns : Array Zil.RelExpr)
    (binding : Zil.Engine.Binding) : Bool :=
  patterns.all fun pattern => !hasMatch facts pattern binding

private def appendBase (trace : Trace) (fact : Zil.RelExpr) : Trace :=
  if (trace.findFact? fact).isSome then trace
  else {
    facts := trace.facts.push {
      id := trace.facts.size
      fact
      origin := .base
      stratum := 0
    }
  }

private def baseTrace (facts : Array Zil.RelExpr) : Trace :=
  facts.foldl (init := {}) appendBase

private structure Candidate where
  fact : Zil.RelExpr
  origin : Origin

private def deriveRule
    (positiveFacts negativeFacts : Array FactNode)
    (rule : Zil.Rule) : Array Candidate :=
  (extendWitnesses positiveFacts rule.premises).filterMap fun state =>
    if negativesHold negativeFacts rule.negativePremises state.binding then
      match instantiateRelation state.binding rule.conclusion with
      | none => none
      | some fact =>
          let negatives := rule.negativePremises.filterMap (instantiateRelation state.binding)
          some {
            fact
            origin := .rule rule.name state.premiseFactIds negatives state.binding
          }
    else none

private def appendCandidate
    (trace : Trace)
    (candidate : Candidate)
    (stratum : Nat) : Trace :=
  if (trace.findFact? candidate.fact).isSome then trace
  else {
    facts := trace.facts.push {
      id := trace.facts.size
      fact := candidate.fact
      origin := candidate.origin
      stratum
    }
  }

private def rulesAt
    (rules : Array Zil.Rule)
    (strata : Zil.Engine.Strata)
    (level : Nat) : Array Zil.Rule :=
  rules.filter fun rule => strata.lookup rule.conclusion.relation == level

private def maxStratum (strata : Zil.Engine.Strata) : Nat :=
  strata.foldl (init := 0) fun current entry => Nat.max current entry.2

private def closeOneStratum
    (initial : Trace)
    (rules : Array Zil.Rule)
    (level fuel : Nat) : Trace :=
  let negativeFacts := initial.facts
  let rec loop (trace : Trace) : Nat → Trace
    | 0 => trace
    | remaining + 1 =>
        let next := rules.foldl (init := trace) fun current rule =>
          (deriveRule current.facts negativeFacts rule).foldl (init := current) fun out candidate =>
            appendCandidate out candidate level
        if next.facts.size == trace.facts.size then next else loop next remaining
  loop initial fuel

private def executeLevels
    (trace : Trace)
    (rules : Array Zil.Rule)
    (strata : Zil.Engine.Strata)
    (fuel : Nat) : Nat → Nat → Trace
  | _, 0 => trace
  | level, remaining + 1 =>
      let closed := closeOneStratum trace (rulesAt rules strata level) level fuel
      executeLevels closed rules strata fuel (level + 1) remaining

/-- Compute checked stratified closure with one deterministic origin per fact. -/
def traceChecked
    (facts : Array Zil.RelExpr)
    (rules : Array Zil.Rule)
    (fuel : Nat := 64) : Except String Trace := do
  let strata ← Zil.Engine.stratify rules
  let initial := baseTrace facts
  pure <| executeLevels initial rules strata fuel 0 (maxStratum strata + 1)

/-- Compute provenance for one complete native program. -/
def traceProgram (program : Zil.Program) (fuel : Nat := 64) : Except String Trace := do
  unless program.valid do throw "provenance requires a structurally valid program"
  traceChecked program.facts program.allRules fuel

private def queryStates (trace : Trace) (query : Zil.Query) : Array WitnessState :=
  if !query.selectedVariablesBound || !query.safe then #[]
  else
    (extendWitnesses trace.facts query.premises).filter fun state =>
      negativesHold trace.facts query.negativePremises state.binding

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

private def termText : Zil.Term → String
  | .node node => node.name.toString
  | .var name => "?" ++ name.toString

private def bindingText (binding : Zil.Engine.Binding) : String :=
  String.intercalate "," (binding.toList.map fun pair =>
    pair.1.toString ++ "=" ++ termText pair.2)

private def idsText (ids : Array Nat) : String :=
  String.intercalate "," (ids.toList.map toString)

private def negativeText (relations : Array Zil.RelExpr) : String :=
  String.intercalate "|" (relations.toList.map Zil.Codec.encodeRelation)

private def factRows (trace : Trace) : List String :=
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
