import Zil.Codec.Canonical

open Zil

private def declaration := Term.ground `lean.Codec.example
private def claim := Term.ground `claim.codecRoundTrip
private def requirement := Term.ground `requirement.codec

private def relation : RelExpr :=
  .mk' declaration `zil.formalizes claim

private def rule : Rule :=
  { name := `codecRequirementRule
    variables := #[`declaration, `claim, `requirement]
    premises := #[
      .mk' (.variable `declaration) `zil.formalizes (.variable `claim),
      .mk' (.variable `declaration) `zil.requires (.variable `requirement)]
    conclusion := .mk' (.variable `claim) `zil.requiresClaim (.variable `requirement)
    trust := .graphDerived }

#guard Zil.Codec.relationRoundTrips relation
#guard Zil.Codec.ruleRoundTrips rule
#guard (Zil.Codec.decodeRelation "broken").isError
#guard (Zil.Codec.decodeRule "rule-only").isError

run_cmd do
  let encoded := Zil.Codec.encodeRule rule
  match Zil.Codec.decodeRule encoded with
  | .error error => throwError "canonical rule round-trip failed: {error}"
  | .ok decoded =>
      unless decoded.allVariablesBound do
        throwError "decoded canonical rule lost variable bindings"
      unless decoded.conclusion.relation == `zil.requiresClaim do
        throwError "decoded canonical rule changed its conclusion"
