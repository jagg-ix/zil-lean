module

public import Zil.Datalog.Basic
public import Zil.Engine.Provenance
public meta import Zil.Datalog.Basic
public meta import Zil.Engine.Provenance

open Lean

namespace Physlib.Meta.ZilEngineAdapter

@[expose] public section

def symbolPrefix : Name := `Physlib.Meta.ZilEngineAdapter.symbolValue
def stringPrefix : Name := `Physlib.Meta.ZilEngineAdapter.stringValue
def integerPrefix : Name := `Physlib.Meta.ZilEngineAdapter.integerValue
def booleanPrefix : Name := `Physlib.Meta.ZilEngineAdapter.booleanValue
def variablePrefix : Name := `Physlib.Meta.ZilEngineAdapter.variable
def relationPrefix : Name := `Physlib.Meta.ZilEngineAdapter.relation
def attributePrefix : Name := `Physlib.Meta.ZilEngineAdapter.attribute
def rulePrefix : Name := `Physlib.Meta.ZilEngineAdapter.rule

def valueName : Zil.Datalog.Value → Name
  | .symbol value => Name.str symbolPrefix value
  | .string value => Name.str stringPrefix value
  | .integer value => Name.str integerPrefix (toString value)
  | .boolean value => Name.str booleanPrefix (toString value)

def valueOfName? : Name → Option Zil.Datalog.Value
  | .str pre payload =>
      if pre == symbolPrefix then some (.symbol payload)
      else if pre == stringPrefix then some (.string payload)
      else if pre == integerPrefix then payload.toInt?.map .integer
      else if pre == booleanPrefix then
        if payload == "true" then some (.boolean true)
        else if payload == "false" then some (.boolean false)
        else none
      else none
  | _ => none

def variableName (value : String) : Name := Name.str variablePrefix value
def relationName (value : String) : Name := Name.str relationPrefix value
def attributeName (value : String) : Name := Name.str attributePrefix value
def nativeRuleName (value : String) : Name := Name.str rulePrefix value

def relationOfName? : Name → Option String
  | .str pre payload => if pre == relationPrefix then some payload else none
  | _ => none

def attributeOfName? : Name → Option String
  | .str pre payload => if pre == attributePrefix then some payload else none
  | _ => none

def ruleOfName (name : Name) : String :=
  match name with
  | .str pre payload => if pre == rulePrefix then payload else name.toString
  | _ => name.toString

def valueTerm (value : Zil.Datalog.Value) : Zil.Term := .node ⟨valueName value⟩

def termToNative : Zil.Datalog.Term → Zil.Term
  | .variable value => .var (variableName value)
  | .value value => valueTerm value

def attributeValueToNative (value : Zil.Datalog.Value) : Zil.AttrValue := .term (valueTerm value)
def patternAttributeValueToNative (value : Zil.Datalog.Term) : Zil.AttrValue := .term (termToNative value)

def atomToNative (atom : Zil.Datalog.Atom) : Zil.RelExpr :=
  { subject := valueTerm atom.object
    relation := relationName atom.relation
    object := valueTerm atom.subject
    attrs := atom.attrs.toArray.map fun entry =>
      { key := attributeName entry.1, value := attributeValueToNative entry.2 } }

def patternToNative (pattern : Zil.Datalog.Pattern) : Zil.RelExpr :=
  { subject := termToNative pattern.object
    relation := relationName pattern.relation
    object := termToNative pattern.subject
    attrs := pattern.attrs.toArray.map fun entry =>
      { key := attributeName entry.1, value := patternAttributeValueToNative entry.2 } }

def valueOfTerm? : Zil.Term → Option Zil.Datalog.Value
  | .node node => valueOfName? node.name
  | .var _ => none

def valueOfAttr? : Zil.AttrValue → Option Zil.Datalog.Value
  | .term term => valueOfTerm? term
  | _ => none

def nativeToAtom? (relation : Zil.RelExpr) : Option Zil.Datalog.Atom := do
  let object ← valueOfTerm? relation.subject
  let relationNameText ← relationOfName? relation.relation
  let subject ← valueOfTerm? relation.object
  let attrs ← relation.attrs.toList.mapM fun entry => do
    let key ← attributeOfName? entry.key
    let value ← valueOfAttr? entry.value
    pure (key, value)
  pure { object, relation := relationNameText, subject, attrs }

def ruleVariables (rule : Zil.Datalog.Rule) : List String :=
  (rule.head.variables ++ rule.literals.flatMap Zil.Datalog.Literal.variables).eraseDups

def ruleToNative (rule : Zil.Datalog.Rule) : Zil.Rule :=
  let positives := rule.literals.filterMap fun
    | .positive pattern => some (patternToNative pattern)
    | .negative _ => none
  let negatives := rule.literals.filterMap fun
    | .negative pattern => some (patternToNative pattern)
    | .positive _ => none
  { name := nativeRuleName rule.name
    variables := (ruleVariables rule).toArray.map variableName
    premises := positives.toArray
    negativePremises := negatives.toArray
    conclusion := patternToNative rule.head }

partial def closeOneStratumToFixpoint
    (initial : Zil.Engine.Provenance.Trace) (rules : Array Zil.Rule) (level : Nat) :
    Zil.Engine.Provenance.Trace :=
  let negativeFacts := initial.facts
  let rec loop (trace : Zil.Engine.Provenance.Trace) : Zil.Engine.Provenance.Trace :=
    let next := rules.foldl (init := trace) fun current rule =>
      (Zil.Engine.Provenance.deriveRule current.facts negativeFacts rule).foldl
        (init := current) fun out candidate => Zil.Engine.Provenance.appendCandidate out candidate level
    if next.facts.size == trace.facts.size then next else loop next
  loop initial

partial def executeLevelsToFixpoint
    (trace : Zil.Engine.Provenance.Trace) (rules : Array Zil.Rule) (strata : Zil.Engine.Strata) :
    Nat → Nat → Zil.Engine.Provenance.Trace
  | _, 0 => trace
  | level, remaining + 1 =>
      let closed := closeOneStratumToFixpoint trace (Zil.Engine.Provenance.rulesAt rules strata level) level
      executeLevelsToFixpoint closed rules strata (level + 1) remaining

partial def traceCheckedToFixpoint
    (facts : Array Zil.RelExpr) (rules : Array Zil.Rule) : Except String Zil.Engine.Provenance.Trace := do
  let strata ← Zil.Engine.stratify rules
  let initial := Zil.Engine.Provenance.baseTrace facts
  pure <| executeLevelsToFixpoint initial rules strata 0 (Zil.Engine.Provenance.maxStratum strata + 1)

structure ClosureResult where
  trace : Zil.Engine.Provenance.Trace
  atoms : List Zil.Datalog.Atom
  error : Option String := none
  deriving Inhabited

partial def closeProgram (program : Zil.Datalog.Program) : ClosureResult :=
  let facts := program.facts.toArray.map atomToNative
  let rules := program.rules.toArray.map ruleToNative
  match traceCheckedToFixpoint facts rules with
  | .ok trace => { trace, atoms := trace.facts.toList.filterMap fun node => nativeToAtom? node.fact }
  | .error error => { trace := Zil.Engine.Provenance.baseTrace facts, atoms := program.facts, error := some error }

def provenanceSummary (result : ClosureResult) (atom : Zil.Datalog.Atom) : String :=
  match result.trace.findFact? (atomToNative atom) with
  | none => "no native witness"
  | some node => match node.origin with
    | .base => s!"base fact #{node.id}"
    | .rule rule premiseIds negativeChecks _ =>
        s!"rule {ruleOfName rule}; fact #{node.id}; premises [{Zil.Engine.Provenance.idsText premiseIds}]; negative checks {negativeChecks.size}"

def roundTripProbe : Zil.Datalog.Atom :=
  { object := .symbol "declaration:probe", relation := "requires",
    subject := .string "claim.with/punctuation",
    attrs := [("count", .integer (-3)), ("enabled", .boolean true)] }

open Zil.Datalog

def pat (object : Zil.Datalog.Term) (relation : String) (subject : Zil.Datalog.Term) : Pattern :=
  { object, relation, subject }

def hasTestRule : Rule :=
  { name := "hasTest", head := pat (.variable "d") "hasTest" (.variable "d"),
    literals := [.positive (pat (.variable "d") "experimental_bound" (.variable "b"))] }

def untestedRule : Rule :=
  { name := "untested", head := pat (.variable "d") "untestedPrediction" (.variable "c"),
    literals := [.positive (pat (.variable "d") "derives" (.variable "c")),
                 .negative (pat (.variable "d") "hasTest" (.variable "d"))] }

def sample : Program :=
  { facts := [{ object := .symbol "D1", relation := "derives", subject := .symbol "C1" },
              { object := .symbol "D1", relation := "experimental_bound", subject := .symbol "B1" },
              { object := .symbol "D2", relation := "derives", subject := .symbol "C2" }],
    rules := [hasTestRule, untestedRule] }

def untestedAtom (d c : String) : Atom :=
  { object := .symbol d, relation := "untestedPrediction", subject := .symbol c }

run_cmd do
  unless nativeToAtom? (atomToNative roundTripProbe) == some roundTripProbe do
    throwError "adapter round-trip failed"
  let result := closeProgram sample
  if let some error := result.error then throwError "closure failed: {error}"
  unless untestedAtom "D2" "C2" ∈ result.atoms do throwError "missing expected derivation"
  if untestedAtom "D1" "C1" ∈ result.atoms then throwError "negation regression"

end

end Physlib.Meta.ZilEngineAdapter
