import Zil.TokenLifecycle

namespace Zil.RecoveryAudit

/-- One observed postcondition and its evidence reference. -/
structure Postcondition where
  name : String
  passed : Bool
  evidence : String
  deriving Repr, BEq, Inhabited

/-- Declared rollback or compensation execution. -/
structure RecoveryEvent where
  kind : String
  reference : String
  completed : Bool
  evidence : String
  deriving Repr, BEq, Inhabited

/-- Terminal interpretation of execution and recovery evidence. -/
inductive Outcome where
  | lifecycleInvalid
  | verified
  | recoveryRequired
  | recovered
  | recoveryFailed
  deriving Repr, BEq, Inhabited

namespace Outcome

def token : Outcome → String
  | .lifecycleInvalid => "lifecycle-invalid"
  | .verified => "verified"
  | .recoveryRequired => "recovery-required"
  | .recovered => "recovered"
  | .recoveryFailed => "recovery-failed"

end Outcome

/-- Complete postcondition and recovery audit. -/
structure Audit where
  requestNode : Name
  lifecycle : Zil.TokenLifecycle.Audit
  required : Array String := #[]
  observed : Array Postcondition := #[]
  missing : Array String := #[]
  failed : Array String := #[]
  evidenceMissing : Array String := #[]
  duplicates : Array String := #[]
  recovery : Option RecoveryEvent := none
  recoveryIssues : Array String := #[]
  outcome : Outcome
  actionVerified : Bool
  safe : Bool
  deriving Repr, Inhabited

private def insertString (value : String) : List String → List String
  | [] => [value]
  | head :: tail =>
      match compare value head with
      | .lt => value :: head :: tail
      | .eq => head :: tail
      | .gt => head :: insertString value tail

private def sortedStrings (values : Array String) : Array String :=
  (values.foldl (init := []) fun out value => insertString value out).toArray

private def attr? (fact : Zil.RelExpr) (key : Name) : Option Zil.AttrValue :=
  (Zil.Attribute.find? fact.attrs key).map (·.value)

private def textValue? : Zil.AttrValue → Option String
  | .text value => some value
  | .decimal value => some value
  | .integer value => some (toString value)
  | .boolean value => some (if value then "true" else "false")
  | .term (.node node) => some node.name.toString
  | .term (.var _) => none

private def requiredText (fact : Zil.RelExpr) (key : Name) : Except String String := do
  let value ← match attr? fact key with
    | some value => pure value
    | none => throw s!"recovery audit event is missing {key}"
  let text ← match textValue? value with
    | some text => pure text
    | none => throw s!"recovery audit event attribute {key} must be ground"
  if text.isEmpty then throw s!"recovery audit event attribute {key} must be nonempty"
  pure text

private def requiredBool (fact : Zil.RelExpr) (key : Name) : Except String Bool :=
  match attr? fact key with
  | some (.boolean value) => pure value
  | some _ => throw s!"recovery audit event attribute {key} must be boolean"
  | none => throw s!"recovery audit event is missing {key}"

private def nodeName? : Zil.Term → Option Name
  | .node node => some node.name
  | .var _ => none

private def stripPrefix (prefix value : String) : String :=
  if value.startsWith (prefix ++ ".") then value.drop (prefix.length + 1)
  else value

private def postconditionName (fact : Zil.RelExpr) : Except String String := do
  let object ← match nodeName? fact.object with
    | some value => pure value
    | none => throw "postcondition event object must be ground"
  let name := stripPrefix "post" object.toString
  if name.isEmpty then throw "postcondition event name must be nonempty"
  pure name

private def postconditionFacts
    (program : Zil.Program)
    (requestNode : Name) : Array Zil.RelExpr :=
  program.facts.filter fun fact =>
    fact.subject == .ground requestNode &&
    fact.relation == `zil.postconditionEvent

/-- Decode all postcondition observations for one request node. -/
def postconditionsFromProgram
    (program : Zil.Program)
    (requestNode : Name) : Except String (Array Postcondition) := do
  let mut values : Array Postcondition := #[]
  for fact in postconditionFacts program requestNode do
    values := values.push {
      name := ← postconditionName fact
      passed := ← requiredBool fact `passed
      evidence := match attr? fact `evidence with
        | some value => (textValue? value).getD ""
        | none => ""
    }
  pure values

private def recoveryFact?
    (program : Zil.Program)
    (requestNode : Name) : Option Zil.RelExpr :=
  program.facts.find? fun fact =>
    fact.subject == .ground requestNode &&
    fact.relation == `zil.recoveryEvent

/-- Decode the optional recovery execution for one request node. -/
def recoveryFromProgram
    (program : Zil.Program)
    (requestNode : Name) : Except String (Option RecoveryEvent) := do
  match recoveryFact? program requestNode with
  | none => pure none
  | some fact =>
      pure <| some {
        kind := ← requiredText fact `kind
        reference := ← requiredText fact `reference
        completed := ← requiredBool fact `completed
        evidence := match attr? fact `evidence with
          | some value => (textValue? value).getD ""
          | none => ""
      }

private def duplicateNames (values : Array Postcondition) : Array String :=
  sortedStrings <| values.foldl (init := #[]) fun out value =>
    if (values.filter fun candidate => candidate.name == value.name).size > 1 then
      out.push value.name
    else out

private def findPostcondition?
    (values : Array Postcondition)
    (name : String) : Option Postcondition :=
  values.find? fun value => value.name == name

private def recoveryIssues
    (rollback : Zil.ActionToken.Rollback)
    (recovery : Option RecoveryEvent) : Array String :=
  match recovery with
  | none => #["recovery-missing"]
  | some event => Id.run do
      let mut issues : Array String := #[]
      unless event.kind == rollback.kind do issues := issues.push "recovery-kind-mismatch"
      unless event.reference == rollback.reference do
        issues := issues.push "recovery-reference-mismatch"
      unless event.completed do issues := issues.push "recovery-incomplete"
      if event.evidence.isEmpty then issues := issues.push "recovery-evidence-missing"
      return issues

/-- Audit required postconditions and any declared recovery operation. -/
def audit
    (requestNode : Name)
    (lifecycle : Zil.TokenLifecycle.Audit)
    (observed : Array Postcondition)
    (recovery : Option RecoveryEvent) : Audit := Id.run do
  let required := match lifecycle.state with
    | some state => state.token.action.requiredPostconditions
    | none => #[]
  let duplicates := duplicateNames observed
  let mut missing : Array String := #[]
  let mut failed : Array String := #[]
  let mut evidenceMissing : Array String := #[]
  for name in required do
    match findPostcondition? observed name with
    | none => missing := missing.push name
    | some value =>
        unless value.passed do failed := failed.push name
        if value.passed && value.evidence.isEmpty then
          evidenceMissing := evidenceMissing.push name
  let lifecycleConsumed := match lifecycle.state with
    | some state => lifecycle.ok && state.status == .consumed
    | none => false
  let postconditionsPass :=
    lifecycleConsumed && missing.isEmpty && failed.isEmpty &&
    evidenceMissing.isEmpty && duplicates.isEmpty
  if postconditionsPass then
    let unexpectedRecovery := if recovery.isSome then #["unexpected-recovery"] else #[]
    return {
      requestNode
      lifecycle
      required
      observed
      missing
      failed
      evidenceMissing
      duplicates
      recovery
      recoveryIssues := unexpectedRecovery
      outcome := if unexpectedRecovery.isEmpty then .verified else .recoveryFailed
      actionVerified := unexpectedRecovery.isEmpty
      safe := unexpectedRecovery.isEmpty
    }
  if !lifecycleConsumed then
    return {
      requestNode
      lifecycle
      required
      observed
      missing
      failed
      evidenceMissing
      duplicates
      recovery
      recoveryIssues := #["lifecycle-not-consumed"]
      outcome := .lifecycleInvalid
      actionVerified := false
      safe := false
    }
  let issues := recoveryIssues lifecycle.state.get!.token.rollback recovery
  if recovery.isNone then
    return {
      requestNode
      lifecycle
      required
      observed
      missing
      failed
      evidenceMissing
      duplicates
      recovery
      recoveryIssues := issues
      outcome := .recoveryRequired
      actionVerified := false
      safe := false
    }
  return {
    requestNode
    lifecycle
    required
    observed
    missing
    failed
    evidenceMissing
    duplicates
    recovery
    recoveryIssues := issues
    outcome := if issues.isEmpty then .recovered else .recoveryFailed
    actionVerified := false
    safe := issues.isEmpty
  }

/-- Replay lifecycle, postconditions, and recovery declarations for one request. -/
def auditProgram
    (program : Zil.Program)
    (requestNode : Name) : Except String Audit := do
  let lifecycle ← Zil.TokenLifecycle.auditProgram program requestNode
  let observed ← postconditionsFromProgram program requestNode
  let recovery ← recoveryFromProgram program requestNode
  pure (audit requestNode lifecycle observed recovery)

private def stringsText (values : Array String) : String :=
  String.intercalate "," values.toList

private def observedRows (values : Array Postcondition) : List String :=
  values.toList.map fun value =>
    String.intercalate "\t" [
      "postcondition", value.name,
      if value.passed then "pass" else "fail",
      value.evidence
    ]

private def recoveryRows : Option RecoveryEvent → List String
  | none => []
  | some event => [
      "recovery-kind\t" ++ event.kind,
      "recovery-reference\t" ++ event.reference,
      "recovery-completed\t" ++ (if event.completed then "true" else "false"),
      "recovery-evidence\t" ++ event.evidence
    ]

/-- Stable terminal safety report. -/
def render (audit : Audit) : String :=
  String.intercalate "\n" <|
    ["ZIL-RECOVERY-AUDIT\t1",
     "status\t" ++ (if audit.safe then "safe" else "unsafe"),
     "outcome\t" ++ audit.outcome.token,
     "request\t" ++ audit.requestNode.toString,
     "lifecycle\t" ++ (if audit.lifecycle.ok then "pass" else "fail"),
     "action-verified\t" ++ (if audit.actionVerified then "true" else "false"),
     "required\t" ++ stringsText audit.required,
     "missing\t" ++ stringsText audit.missing,
     "failed\t" ++ stringsText audit.failed,
     "evidence-missing\t" ++ stringsText audit.evidenceMissing,
     "duplicates\t" ++ stringsText audit.duplicates,
     "recovery-issues\t" ++ stringsText audit.recoveryIssues] ++
    observedRows audit.observed ++ recoveryRows audit.recovery ++ [""]

end Zil.RecoveryAudit
