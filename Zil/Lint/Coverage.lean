import Zil.Engine.Query

namespace Zil.Lint

inductive IssueKind where
  | unsupportedClaim
  | unpropagatedRequirement
  | unlinkedDeclaration
  | linkedWithoutClaim
  deriving Repr, BEq, Inhabited

structure Issue where
  kind : IssueKind
  subject : Zil.Term
  related : Option Zil.Term := none
  message : String
  deriving Repr, Inhabited

private def relationsNamed (facts : Array Zil.RelExpr) (name : Name) : Array Zil.RelExpr :=
  facts.filter fun fact => fact.relation == name

private def containsRelation (facts : Array Zil.RelExpr) (subject : Zil.Term)
    (relation : Name) (object : Zil.Term) : Bool :=
  facts.any fun fact =>
    fact.subject == subject && fact.relation == relation && fact.object == object

private def hasRelationFrom (facts : Array Zil.RelExpr) (subject : Zil.Term)
    (relation : Name) : Bool :=
  facts.any fun fact => fact.subject == subject && fact.relation == relation

private def linkedSubjects (env : Lean.Environment) : Array Zil.Term :=
  (Zil.Environment.entries env).foldl (init := #[]) fun subjects entry =>
    match entry with
    | .declarationLink _ relation =>
        if subjects.contains relation.subject then subjects else subjects.push relation.subject
    | _ => subjects

private def pushIssue (issues : Array Issue) (issue : Issue) : Array Issue :=
  if issues.any fun current =>
      current.kind == issue.kind && current.subject == issue.subject &&
        current.related == issue.related
  then issues
  else issues.push issue

/-- Scan closed graph state for formalization coverage gaps. -/
def scan (env : Lean.Environment) (fuel : Nat := 64) : Array Issue :=
  let facts := Zil.Engine.closureOfEnvironment env fuel
  let formalizes := relationsNamed facts `zil.formalizes
  let requires := relationsNamed facts `zil.requires
  let linkedDeclarations := linkedSubjects env

  let issues := formalizes.foldl (init := #[]) fun issues relation =>
    let issues :=
      if hasRelationFrom facts relation.object `zil.supportedBy then issues
      else pushIssue issues {
        kind := .unsupportedClaim
        subject := relation.object
        related := some relation.subject
        message := s!"claim {repr relation.object} has no supportedBy evidence" }
    if linkedDeclarations.contains relation.subject then issues
    else pushIssue issues {
      kind := .unlinkedDeclaration
      subject := relation.subject
      related := some relation.object
      message := s!"declaration {repr relation.subject} formalizes a claim but has no zil_link metadata" }

  let issues := formalizes.foldl (init := issues) fun issues formalization =>
    requires.foldl (init := issues) fun inner requirement =>
      if requirement.subject != formalization.subject then inner
      else if containsRelation facts formalization.object `zil.requiresClaim requirement.object then inner
      else pushIssue inner {
        kind := .unpropagatedRequirement
        subject := formalization.object
        related := some requirement.object
        message := s!"requirement {repr requirement.object} was not propagated to claim {repr formalization.object}" }

  linkedDeclarations.foldl (init := issues) fun issues declaration =>
    if hasRelationFrom facts declaration `zil.formalizes then issues
    else pushIssue issues {
      kind := .linkedWithoutClaim
      subject := declaration
      message := s!"linked declaration {repr declaration} has no formalizes relation" }

/-- Return true when the environment has no coverage issues. -/
def clean (env : Lean.Environment) (fuel : Nat := 64) : Bool :=
  (scan env fuel).isEmpty

/-- Human-readable deterministic summary. -/
def render (issue : Issue) : String :=
  s!"[{repr issue.kind}] {issue.message}"

end Zil.Lint
