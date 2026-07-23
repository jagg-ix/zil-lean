import Zil.Codec.Userset

open Zil

private def directGroup : TupleExpr :=
  TupleExpr.direct
    (.ground `doc.readme)
    `zil.viewer
    (.ground `group.eng)

private def memberUserset : TupleExpr :=
  TupleExpr.withUserset
    (.ground `doc.readme)
    `zil.viewer
    ⟨`group.eng⟩
    `zil.member

private def nestedMembershipProgram : TupleProgram := {
  moduleName := some `policy.access
  tuples := #[
    memberUserset,
    TupleExpr.withUserset
      (.ground `group.eng)
      `zil.member
      ⟨`group.platform⟩
      `zil.member
  ]
}

#guard !directGroup.semanticallyEqual memberUserset
#guard Zil.Codec.tupleRoundTrips directGroup
#guard Zil.Codec.tupleRoundTrips memberUserset
#guard memberUserset.lower.facts.size == 1
#guard memberUserset.lower.rules.size == 1
#guard nestedMembershipProgram.lower.facts.size == 2
#guard nestedMembershipProgram.lower.rules.size == 2

run_cmd do
  let lowered := memberUserset.lower
  let expectedFact := RelExpr.mk'
    (.ground `doc.readme)
    `zil.viewer
    (.ground `group.eng)
  unless lowered.facts.any (fun fact => fact.semanticallyEqual expectedFact) do
    throwError "userset lowering lost the stored group relation"
  let expectedConclusion := RelExpr.mk'
    (.variable `object)
    `zil.viewer
    (.variable `subject)
  unless lowered.rules.any (fun rule =>
      rule.conclusion.semanticallyEqual expectedConclusion) do
    throwError "userset lowering did not produce the traversal rule"
