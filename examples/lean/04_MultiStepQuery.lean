import Zil

open Zil

/-!
# 4. Multi-step inference and querying

This example uses two Horn rules. The first propagates a declaration requirement
to its claim. The second marks a required claim as reviewable when the claim has
supporting evidence.
-/

zil_theorem_rule propagateRequirement
  {declaration claim requirement : Zil.Node}
  (hFormalizes : declaration ⟶[formalizes] claim)
  (hRequires : declaration ⟶[requires] requirement)
  : claim ⟶[requiresClaim] requirement

zil_theorem_rule findReviewableClaim
  {claim requirement evidence : Zil.Node}
  (hRequirement : claim ⟶[requiresClaim] requirement)
  (hEvidence : claim ⟶[supportedBy] evidence)
  : claim ⟶[reviewableAgainst] requirement

private def facts : Array RelExpr := #[
  .mk' (.ground `lean.Example.metric) `zil.formalizes
    (.ground `claim.exampleMetric),
  .mk' (.ground `lean.Example.metric) `zil.requires
    (.ground `requirement.lorentzianMetric),
  .mk' (.ground `claim.exampleMetric) `zil.supportedBy
    (.ground `paper.exampleEvidence)
]

private def rules : Array Rule := #[
  propagateRequirement,
  findReviewableClaim
]

private def reviewableQuery : Query := {
  name := `reviewableRequirements
  variables := #[`requirement]
  select := #[`requirement]
  premises := #[
    .mk' (.ground `claim.exampleMetric) `zil.reviewableAgainst
      (.variable `requirement)
  ]
}

run_cmd do
  let closed := Zil.Engine.closure facts rules
  let target := RelExpr.mk'
    (.ground `claim.exampleMetric)
    `zil.reviewableAgainst
    (.ground `requirement.lorentzianMetric)
  unless closed.any (·.semanticallyEqual target) do
    throwError "multi-step closure did not derive the target"
  let answers := Zil.Engine.solve closed reviewableQuery
  unless answers.size == 1 do
    throwError m!"expected one query answer, found {answers.size}"
  logInfo m!"closure facts: {closed.size}"
  logInfo m!"query answers: {repr answers}"
