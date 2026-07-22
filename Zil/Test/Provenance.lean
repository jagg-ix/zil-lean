import Zil.Engine.Provenance

open Zil

private def declaration := Term.ground `lean.Prov.theorem
private def claim := Term.ground `claim.provenance
private def requirement := Term.ground `requirement.provenance

private def facts : Array RelExpr := #[
  .mk' declaration `zil.formalizes claim,
  .mk' declaration `zil.requires requirement
]

private def rule : Rule := {
  name := `provenanceRule
  variables := #[`declaration, `claim, `requirement]
  premises := #[
    .mk' (.variable `declaration) `zil.formalizes (.variable `claim),
    .mk' (.variable `declaration) `zil.requires (.variable `requirement)]
  conclusion := .mk' (.variable `claim) `zil.requiresClaim (.variable `requirement)
  trust := .graphDerived }

private def target := RelExpr.mk' claim `zil.requiresClaim requirement
private def dag := Zil.Engine.Provenance.build facts #[rule]

#guard dag.complete
#guard dag.nodes.size == 3

run_cmd do
  let root ← (Zil.Engine.Provenance.rootFor? dag target).toExcept "missing derived root"
  let explanation := Zil.Engine.Provenance.explain dag root
  unless explanation.size == 3 do
    throwError "expected two asserted leaves and one rule application"
  let node := dag.nodes[root]!
  unless node.premises.size == 2 do
    throwError "derived node did not retain premise edges"
