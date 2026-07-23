import Zil.Core.Program
import Zil.Parser.Tuple

namespace Zil.ProofObligation

inductive Tool where
  | z3
  | tlaps
  | lean4
  | acl2
  | manual
  deriving Repr, BEq, Inhabited

namespace Tool

def ofToken? : String → Option Tool
  | "z3" => some .z3
  | "tlaps" => some .tlaps
  | "lean4" => some .lean4
  | "acl2" => some .acl2
  | "manual" => some .manual
  | _ => none

def token : Tool → String
  | .z3 => "z3"
  | .tlaps => "tlaps"
  | .lean4 => "lean4"
  | .acl2 => "acl2"
  | .manual => "manual"

/-- Only Lean evidence can be produced by the native process itself. -/
def nativeBackend : Tool → Bool
  | .lean4 => true
  | _ => false

end Tool

inductive Status where
  | open
  | pending
  | proved
  | failed
  | waived
  deriving Repr, BEq, Inhabited

namespace Status

def ofToken? : String → Option Status
  | "open" => some .open
  | "pending" => some .pending
  | "proved" => some .proved
  | "failed" => some .failed
  | "waived" => some .waived
  | _ => none

def token : Status → String
  | .open => "open"
  | .pending => "pending"
  | .proved => "proved"
  | .failed => "failed"
  | .waived => "waived"

end Status

inductive Criticality where
  | low
  | medium
  | high
  | critical
  deriving Repr, BEq, Inhabited

namespace Criticality

def ofToken? : String → Option Criticality
  | "low" => some .low
  | "medium" => some .medium
  | "high" => some .high
  | "critical" => some .critical
  | _ => none

def token : Criticality → String
  | .low => "low"
  | .medium => "medium"
  | .high => "high"
  | .critical => "critical"

end Criticality

inductive Verdict where
  | satisfied
  | violated
  | blocked
  | waived
  deriving Repr, BEq, Inhabited

namespace Verdict

def token : Verdict → String
  | .satisfied => "satisfied"
  | .violated => "violated"
  | .blocked => "blocked"
  | .waived => "waived"

end Verdict

structure Obligation where
  id : Name
  relation : Name
  statement : String
  tool : Tool
  status : Status
  criticality : Criticality
  logic : Option String := none
  expectation : Option String := none
  evidence : Array String := #[]
  waiverReason : Option String := none
  deriving Repr, Inhabited

structure Result where
  obligation : Obligation
  verdict : Verdict
  relationKnown : Bool
  nativeBackend : Bool
  reasons : Array String := #[]
  deriving Repr, Inhabited

structure Report where
  moduleName : Name
  toolFilter : Option Tool
  results : Array Result
  satisfied : Nat
  violated : Nat
  blocked : Nat
  waived : Nat
  ok : Bool
  deriving Repr, Inhabited

private def attrTokens (declaration : Zil.Declaration) (key : Name) : Array String :=
  match declaration.attr? key with
  | none => #[]
  | some attr => attr.value.members.filterMap Zil.DeclValue.token?

private def attrToken? (declaration : Zil.Declaration) (key : Name) : Option String :=
  (attrTokens declaration key)[0]?

private def nonempty? (value : String) : Bool := !value.trim.isEmpty

private def requiredToken
    (declaration : Zil.Declaration)
    (key : Name) : Except String String := do
  let value ← match attrToken? declaration key with
    | some token => pure token
    | none => throw s!"{declaration.name}: missing {key}"
  if nonempty? value then pure value
  else throw s!"{declaration.name}: {key} must be nonempty"

private def parseRelation (declaration : Zil.Declaration) : Except String Name := do
  let token ← requiredToken declaration `relation
  match Zil.Parser.relationNameFromToken token with
  | .ok relation => pure relation
  | .error error => throw s!"{declaration.name}: {error}"

private def parseTool (declaration : Zil.Declaration) : Except String Tool := do
  let token ← requiredToken declaration `tool
  match Tool.ofToken? token with
  | some value => pure value
  | none => throw s!"{declaration.name}: invalid proof tool {token}"

private def parseStatus (declaration : Zil.Declaration) : Except String Status := do
  match attrToken? declaration `status with
  | none => pure .open
  | some token =>
      match Status.ofToken? token with
      | some value => pure value
      | none => throw s!"{declaration.name}: invalid proof status {token}"

private def parseCriticality (declaration : Zil.Declaration) : Except String Criticality := do
  match attrToken? declaration `criticality with
  | none => pure .low
  | some token =>
      match Criticality.ofToken? token with
      | some value => pure value
      | none => throw s!"{declaration.name}: invalid proof criticality {token}"

private def evidenceRefs (declaration : Zil.Declaration) : Array String :=
  let keys : Array Name := #[`evidence, `artifact_in, `artifact_out, `proof_token, `declaration]
  keys.foldl (init := #[]) fun out key =>
    (attrTokens declaration key).foldl (init := out) fun current value =>
      if nonempty? value && !current.contains value then current.push value else current

/-- Normalize one typed declaration into a proof obligation. -/
def ofDeclaration (declaration : Zil.Declaration) : Except String Obligation := do
  unless declaration.kind == .proofObligation do
    throw s!"{declaration.name}: expected PROOF_OBLIGATION"
  let relation ← parseRelation declaration
  let statement ← requiredToken declaration `statement
  let tool ← parseTool declaration
  let status ← parseStatus declaration
  let criticality ← parseCriticality declaration
  pure {
    id := declaration.entityName
    relation
    statement
    tool
    status
    criticality
    logic := attrToken? declaration `logic
    expectation := attrToken? declaration `expectation
    evidence := evidenceRefs declaration
    waiverReason := attrToken? declaration `waiver_reason
  }

/-- Parse every proof-obligation declaration in source order. -/
def fromProgram (program : Zil.Program) : Except String (Array Obligation) := do
  let declarations := program.declarations.filter fun declaration =>
    declaration.kind == .proofObligation
  let mut out : Array Obligation := #[]
  for declaration in declarations do
    out := out.push (← ofDeclaration declaration)
  let ids := out.map (·.id)
  unless ids.all fun id => (ids.filter (· == id)).size == 1 do
    throw "proof obligation IDs must be unique"
  pure out

private def relationKnown (program : Zil.Program) (relation : Name) : Bool :=
  program.facts.any (·.relation == relation) ||
  program.allRules.any fun rule => rule.conclusion.relation == relation

private def evaluate (program : Zil.Program) (obligation : Obligation) : Result :=
  let known := relationKnown program obligation.relation
  let hasEvidence := !obligation.evidence.isEmpty
  let waiverPresent := obligation.waiverReason.map nonempty? |>.getD false
  let mut reasons : Array String := #[]
  unless known do reasons := reasons.push "unknown-relation"
  let verdict :=
    if !known then .blocked
    else
      match obligation.status with
      | .failed => .violated
      | .open | .pending =>
          if !obligation.tool.nativeBackend && !hasEvidence then
            reasons := reasons.push "backend-unavailable-without-evidence"
          else
            reasons := reasons.push "obligation-not-discharged"
          .blocked
      | .proved =>
          if hasEvidence then .satisfied
          else
            reasons := reasons.push "proved-status-requires-evidence"
            .blocked
      | .waived =>
          if !waiverPresent then
            reasons := reasons.push "waiver-reason-missing"
            .blocked
          else if obligation.criticality == .critical then
            reasons := reasons.push "critical-obligation-cannot-be-waived"
            .blocked
          else .waived
  {
    obligation
    verdict
    relationKnown := known
    nativeBackend := obligation.tool.nativeBackend
    reasons
  }

/-- Audit proof obligations without pretending to execute unavailable backends. -/
def audit
    (program : Zil.Program)
    (toolFilter : Option Tool := none) : Except String Report := do
  unless program.valid do throw "proof obligation governance requires a valid program"
  let moduleName ← match program.moduleName with
    | some value => pure value
    | none => throw "proof obligation governance requires MODULE"
  let obligations ← fromProgram program
  let selected := match toolFilter with
    | none => obligations
    | some tool => obligations.filter fun obligation => obligation.tool == tool
  let results := selected.map (evaluate program)
  let satisfied := (results.filter fun result => result.verdict == .satisfied).size
  let violated := (results.filter fun result => result.verdict == .violated).size
  let blocked := (results.filter fun result => result.verdict == .blocked).size
  let waived := (results.filter fun result => result.verdict == .waived).size
  pure {
    moduleName
    toolFilter
    results
    satisfied
    violated
    blocked
    waived
    ok := violated == 0 && blocked == 0
  }

private def stringsText (values : Array String) : String :=
  String.intercalate "," values.toList

/-- Stable fail-closed proof-obligation governance report. -/
def render (report : Report) : String :=
  let rows := report.results.toList.map fun result =>
    let obligation := result.obligation
    String.intercalate "\t" [
      "obligation", obligation.id.toString,
      obligation.relation.toString,
      obligation.tool.token,
      obligation.status.token,
      obligation.criticality.token,
      result.verdict.token,
      if result.relationKnown then "known" else "unknown",
      if result.nativeBackend then "native" else "external",
      stringsText obligation.evidence,
      stringsText result.reasons,
      obligation.statement
    ]
  String.intercalate "\n" <|
    ["ZIL-PROOF-OBLIGATIONS\t1",
     "status\t" ++ (if report.ok then "pass" else "fail"),
     "module\t" ++ report.moduleName.toString,
     "tool-filter\t" ++ (report.toolFilter.map Tool.token).getD "all",
     "count\t" ++ toString report.results.size,
     "satisfied\t" ++ toString report.satisfied,
     "violated\t" ++ toString report.violated,
     "blocked\t" ++ toString report.blocked,
     "waived\t" ++ toString report.waived] ++ rows ++ [""]

end Zil.ProofObligation
