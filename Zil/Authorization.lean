import Zil.Core.Program
import Zil.Engine.Query

namespace Zil.Authorization

/-- One exact Zanzibar-style authorization request. -/
structure Request where
  object : Zil.Term
  relation : Name
  subject : Zil.Term
  attrs : Array Zil.Attribute := #[]
  deriving Repr, Inhabited

namespace Request

/-- Relation-engine representation of the authorization request. -/
def fact (request : Request) : Zil.RelExpr := {
  subject := request.object
  relation := request.relation
  object := request.subject
  attrs := request.attrs
}

/-- Authorization endpoints and attributes must be ground. -/
def valid (request : Request) : Bool := request.fact.isGround

end Request

/-- How an allowed decision was established. -/
inductive Source where
  | direct
  | derived
  | none
  deriving Repr, BEq, Inhabited

namespace Source

def token : Source → String
  | .direct => "direct"
  | .derived => "derived"
  | .none => "none"

end Source

/-- Deterministic authorization result over one closed ZIL program. -/
structure Decision where
  request : Request
  allowed : Bool
  source : Source
  baseFactCount : Nat
  closedFactCount : Nat
  derivingRules : Array Name := #[]
  deriving Repr, Inhabited

private def containsFact (facts : Array Zil.RelExpr) (target : Zil.RelExpr) : Bool :=
  facts.any (·.semanticallyEqual target)

private def insertString (value : String) : List String → List String
  | [] => [value]
  | head :: tail =>
      match compare value head with
      | .lt | .eq => value :: head :: tail
      | .gt => head :: insertString value tail

private def sortedUniqueNames (names : Array Name) : Array Name :=
  let strings := names.foldl (init := []) fun out name =>
    if out.contains name.toString then out else insertString name.toString out
  strings.toArray.map Name.mkSimple

private def candidateRules (program : Zil.Program) (relation : Name) : Array Name :=
  program.allRules
    |>.filter (fun rule => rule.conclusion.relation == relation)
    |>.map (·.name)
    |> sortedUniqueNames

/-- Decide one request using checked stratified closure. -/
def decide
    (program : Zil.Program)
    (request : Request)
    (fuel : Nat := 64) : Except String Decision := do
  unless program.valid do throw "authorization program is structurally invalid"
  unless request.valid do throw "authorization request must be ground"
  let facts := program.facts
  let target := request.fact
  let direct := containsFact facts target
  let closed ← Zil.Engine.closureChecked facts program.allRules fuel
  let allowed := containsFact closed target
  let source := if direct then Source.direct else if allowed then Source.derived else Source.none
  let rules := if source == .derived then candidateRules program request.relation else #[]
  pure {
    request
    allowed
    source
    baseFactCount := facts.size
    closedFactCount := closed.size
    derivingRules := rules
  }

private def termText : Zil.Term → String
  | .node node => node.name.toString
  | .var name => "?" ++ name.toString

private def rulesText (rules : Array Name) : String :=
  String.intercalate "," (rules.toList.map Name.toString)

/-- Stable tab-separated authorization report. -/
def render (decision : Decision) : String :=
  String.intercalate "\n" [
    "ZIL-AUTHORIZATION\t1",
    "decision\t" ++ (if decision.allowed then "allow" else "deny"),
    "source\t" ++ decision.source.token,
    "object\t" ++ termText decision.request.object,
    "relation\t" ++ decision.request.relation.toString,
    "subject\t" ++ termText decision.request.subject,
    "base-facts\t" ++ toString decision.baseFactCount,
    "closed-facts\t" ++ toString decision.closedFactCount,
    "deriving-rules\t" ++ rulesText decision.derivingRules
  ] ++ "\n"

end Zil.Authorization
