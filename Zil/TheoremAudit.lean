import Zil.Core.Program

namespace Zil.TheoremAudit

inductive Criticality where
  | low
  | medium
  | high
  | critical
  deriving Repr, BEq, Inhabited

namespace Criticality

def ofTerm? : Zil.Term → Option Criticality
  | .node node =>
      match node.name.toString with
      | "value.low" => some .low
      | "value.medium" => some .medium
      | "value.high" => some .high
      | "value.critical" => some .critical
      | _ => none
  | .var _ => none

def token : Criticality → String
  | .low => "low"
  | .medium => "medium"
  | .high => "high"
  | .critical => "critical"

/-- High and critical theorem contracts require explicit proof evidence. -/
def requiresProofEvidence : Criticality → Bool
  | .high | .critical => true
  | _ => false

end Criticality

inductive EvidenceClass where
  | kernel
  | empirical
  | documentary
  | graph
  | unknown
  deriving Repr, BEq, Inhabited

namespace EvidenceClass

def token : EvidenceClass → String
  | .kernel => "kernel"
  | .empirical => "empirical"
  | .documentary => "documentary"
  | .graph => "graph"
  | .unknown => "unknown"

end EvidenceClass

structure EvidenceRef where
  node : Name
  evidenceClass : EvidenceClass
  deriving Repr, BEq, Inhabited

structure TheoremContract where
  theorem : Name
  assumptions : Array Name
  lemmas : Array Name
  guarantees : Array Name
  proofEvidence : Array Name
  criticality : Criticality
  unconditional : Bool
  nonvacuous : Bool
  missingAssumptions : Array Name
  missingLemmas : Array Name
  issues : Array String
  ok : Bool
  deriving Repr, Inhabited

structure ClaimAudit where
  claim : Name
  supports : Array EvidenceRef
  assertedProved : Bool
  issues : Array String
  ok : Bool
  deriving Repr, Inhabited

structure Report where
  moduleName : Name
  theorems : Array TheoremContract
  claims : Array ClaimAudit
  theoremFailures : Nat
  claimFailures : Nat
  ok : Bool
  deriving Repr, Inhabited

private def nodeName? : Zil.Term → Option Name
  | .node node => some node.name
  | .var _ => none

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

private def factsFor (program : Zil.Program) (subject : Name) : Array Zil.RelExpr :=
  program.facts.filter fun fact => fact.subject == .ground subject

private def objectsFor
    (program : Zil.Program)
    (subject relation : Name) : Array Name :=
  sortedNames <| (factsFor program subject).foldl (init := #[]) fun out fact =>
    if fact.relation == relation then
      match nodeName? fact.object with
      | some name => pushName out name
      | none => out
    else out

private def hasFact
    (program : Zil.Program)
    (subject relation object : Name) : Bool :=
  program.facts.any fun fact =>
    fact.subject == .ground subject &&
    fact.relation == relation &&
    fact.object == .ground object

private def subjectsOfKind (program : Zil.Program) (kind : Name) : Array Name :=
  sortedNames <| program.facts.foldl (init := #[]) fun out fact =>
    if fact.relation == `zil.kind && fact.object == .ground kind then
      match nodeName? fact.subject with
      | some name => pushName out name
      | none => out
    else out

private def declaredKind? (program : Zil.Program) (node kind : Name) : Bool :=
  hasFact program node `zil.kind kind

private def hasAnyKind (program : Zil.Program) (node : Name) : Bool :=
  (factsFor program node).any fun fact => fact.relation == `zil.kind

private def trueFact (program : Zil.Program) (subject relation : Name) : Bool :=
  hasFact program subject relation `value.true

private def theoremCriticality
    (program : Zil.Program)
    (theorem : Name) : Criticality :=
  let values := (factsFor program theorem).filterMap fun fact =>
    if fact.relation == `zil.criticality then Criticality.ofTerm? fact.object else none
  values[0]?.getD .low

private def proofEvidence (program : Zil.Program) (theorem : Name) : Array Name :=
  let relations : Array Name := #[`zil.proofToken, `zil.validatedBy, `zil.proves]
  sortedNames <| (factsFor program theorem).foldl (init := #[]) fun out fact =>
    if relations.contains fact.relation then
      match nodeName? fact.object with
      | some name => pushName out name
      | none => out
    else out

private def missingDeclared
    (program : Zil.Program)
    (nodes : Array Name)
    (kind : Name) : Array Name :=
  nodes.filter fun node => !declaredKind? program node kind

private def theoremContract
    (program : Zil.Program)
    (theorem : Name) : TheoremContract := Id.run do
  let assumptions := objectsFor program theorem `zil.requiresAssumption
  let lemmas := objectsFor program theorem `zil.requiresLemma
  let guarantees := objectsFor program theorem `zil.ensures
  let evidence := proofEvidence program theorem
  let criticality := theoremCriticality program theorem
  let unconditional := trueFact program theorem `zil.unconditional
  let nonvacuous := !assumptions.isEmpty || !lemmas.isEmpty || unconditional
  let missingAssumptions := missingDeclared program assumptions `entity.assumption
  let missingLemmas := missingDeclared program lemmas `entity.lemma
  let mut issues : Array String := #[]
  unless nonvacuous do
    issues := issues.push "vacuous-contract"
  if guarantees.isEmpty then
    issues := issues.push "guarantee-missing"
  for assumption in missingAssumptions do
    issues := issues.push s!"missing-assumption:{assumption}"
  for lemma in missingLemmas do
    issues := issues.push s!"missing-lemma:{lemma}"
  if criticality.requiresProofEvidence && evidence.isEmpty then
    issues := issues.push "proof-evidence-missing"
  return {
    theorem
    assumptions
    lemmas
    guarantees
    proofEvidence := evidence
    criticality
    unconditional
    nonvacuous
    missingAssumptions
    missingLemmas
    issues
    ok := issues.isEmpty
  }

private def evidenceClass (program : Zil.Program) (node : Name) : EvidenceClass :=
  if declaredKind? program node `entity.theorem ||
     declaredKind? program node `entity.proof then .kernel
  else if declaredKind? program node `entity.experiment ||
          declaredKind? program node `entity.dataset ||
          declaredKind? program node `entity.measurement then .empirical
  else if declaredKind? program node `entity.document ||
          declaredKind? program node `entity.paper ||
          declaredKind? program node `entity.source ||
          declaredKind? program node `entity.evidence then .documentary
  else if hasAnyKind program node then .graph
  else .unknown

private def claimAudit (program : Zil.Program) (claim : Name) : ClaimAudit := Id.run do
  let supportNodes := objectsFor program claim `zil.supportedBy
  let supports := supportNodes.map fun node => {
    node
    evidenceClass := evidenceClass program node
  }
  let assertedProved := trueFact program claim `zil.provedClaim
  let mut issues : Array String := #[]
  if supports.isEmpty then
    issues := issues.push "support-missing"
  for support in supports do
    if support.evidenceClass == .unknown then
      issues := issues.push s!"support-kind-missing:{support.node}"
  if assertedProved then
    issues := issues.push "external-claim-proof-boundary"
  return {
    claim
    supports
    assertedProved
    issues
    ok := issues.isEmpty
  }

/-- Audit theorem contracts and external claims over one complete native program. -/
def audit (program : Zil.Program) : Except String Report := do
  unless program.valid do throw "theorem audit requires a structurally valid program"
  let moduleName ← match program.moduleName with
    | some value => pure value
    | none => throw "theorem audit requires MODULE"
  let theoremNodes := subjectsOfKind program `entity.theorem
  let claimNodes := subjectsOfKind program `entity.claim
  let theorems := theoremNodes.map (theoremContract program)
  let claims := claimNodes.map (claimAudit program)
  let theoremFailures := (theorems.filter fun theorem => !theorem.ok).size
  let claimFailures := (claims.filter fun claim => !claim.ok).size
  pure {
    moduleName
    theorems
    claims
    theoremFailures
    claimFailures
    ok := theoremFailures == 0 && claimFailures == 0
  }

private def namesText (names : Array Name) : String :=
  String.intercalate "," (names.toList.map Name.toString)

private def evidenceText (evidence : Array EvidenceRef) : String :=
  String.intercalate "," (evidence.toList.map fun item =>
    item.node.toString ++ ":" ++ item.evidenceClass.token)

private def stringsText (values : Array String) : String :=
  String.intercalate "," values.toList

/-- Stable theorem-contract and external-claim audit report. -/
def render (report : Report) : String :=
  let theoremRows := report.theorems.toList.map fun theorem =>
    String.intercalate "\t" [
      "theorem", theorem.theorem.toString,
      if theorem.ok then "pass" else "fail",
      theorem.criticality.token,
      if theorem.nonvacuous then "nonvacuous" else "vacuous",
      if theorem.unconditional then "unconditional" else "conditional",
      namesText theorem.assumptions,
      namesText theorem.lemmas,
      namesText theorem.guarantees,
      namesText theorem.proofEvidence,
      stringsText theorem.issues
    ]
  let claimRows := report.claims.toList.map fun claim =>
    String.intercalate "\t" [
      "claim", claim.claim.toString,
      if claim.ok then "pass" else "fail",
      if claim.assertedProved then "asserted-proved" else "not-proved",
      evidenceText claim.supports,
      stringsText claim.issues
    ]
  String.intercalate "\n" <|
    ["ZIL-THEOREM-AUDIT\t1",
     "status\t" ++ (if report.ok then "pass" else "fail"),
     "module\t" ++ report.moduleName.toString,
     "theorems\t" ++ toString report.theorems.size,
     "claims\t" ++ toString report.claims.size,
     "theorem-failures\t" ++ toString report.theoremFailures,
     "claim-failures\t" ++ toString report.claimFailures] ++
    theoremRows ++ claimRows ++ [""]

end Zil.TheoremAudit
