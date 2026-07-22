import Zil.Engine.Provenance

open Zil

namespace Examples.Provenance

private def declaration : Term := .ground `lean.Schwarzschild.metric
private def claim : Term := .ground `claim.schwarzschildMetric
private def requirement : Term := .ground `requirement.lorentzianMetric

private def facts : Array RelExpr := #[
  .mk' declaration `zil.formalizes claim,
  .mk' declaration `zil.requires requirement
]

private def transferRule : Rule :=
  { name := `schwarzschildClaimRequirement
    variables := #[`declaration, `claim, `requirement]
    premises := #[
      .mk' (.variable `declaration) `zil.formalizes (.variable `claim),
      .mk' (.variable `declaration) `zil.requires (.variable `requirement)
    ]
    conclusion :=
      .mk' (.variable `claim) `zil.requiresClaim (.variable `requirement)
    trust := .graphDerived }

private def target : RelExpr :=
  .mk' claim `zil.requiresClaim requirement

private def renderOrigin : Zil.Engine.Provenance.Origin → String
  | .asserted => "asserted"
  | .ruleApplication rule binding trust =>
      s!"rule={rule}, binding={repr binding}, trust={repr trust}"

private def renderNode (node : Zil.Engine.Provenance.Node) : String :=
  s!"[{node.id}] {Zil.Codec.encodeRelation node.fact}\n" ++
  s!"    origin: {renderOrigin node.origin}\n" ++
  s!"    premises: {repr node.premises}"

/-- Build and print the explanation in topological order. -/
def main : IO Unit := do
  let dag := Zil.Engine.Provenance.build facts #[transferRule]
  let root ← match Zil.Engine.Provenance.rootFor? dag target with
    | some root => pure root
    | none => throw <| IO.userError "target was not derived"
  let explanation := Zil.Engine.Provenance.explain dag root
  unless explanation.size == 3 do
    throw <| IO.userError s!"expected two asserted premises and one derived root, got {explanation.size}"
  for node in explanation do
    IO.println (renderNode node)

end Examples.Provenance
