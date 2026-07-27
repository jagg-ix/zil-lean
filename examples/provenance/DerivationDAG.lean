import Zil.Engine.Provenance

open Zil

namespace Examples.Provenance

private def declaration : Term := .ground `lean.Parser.parse
private def claim : Term := .ground `claim.parserContract
private def requirement : Term := .ground `requirement.inputGrammar

private def facts : Array RelExpr := #[
  .mk' declaration `zil.formalizes claim,
  .mk' declaration `zil.requires requirement
]

private def transferRule : Rule :=
  { name := `declarationClaimRequirement
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
  | .base => "asserted"
  | .rule ruleName premiseFactIds _negativeChecks binding =>
      s!"rule={ruleName}, premises={repr premiseFactIds}, binding={repr binding}"

private def renderNode (node : Zil.Engine.Provenance.FactNode) : String :=
  s!"[{node.id}] {Zil.Codec.encodeRelation node.fact}\n" ++
  s!"    origin: {renderOrigin node.origin}\n" ++
  s!"    stratum: {node.stratum}"

/-- Build the checked trace and print the target's derivation in topological order. -/
def main : IO Unit := do
  let trace ← match Zil.Engine.Provenance.traceChecked facts #[transferRule] with
    | .ok trace => pure trace
    | .error message => throw <| IO.userError message
  let root ← match trace.findFact? target with
    | some root => pure root
    | none => throw <| IO.userError "target was not derived"
  let premiseIds := match root.origin with
    | .rule _ premiseFactIds _ _ => premiseFactIds
    | .base => #[]
  let explanation := (premiseIds.filterMap trace.findId?).push root
  unless explanation.size == 3 do
    throw <| IO.userError
      s!"expected two asserted premises and one derived root, got {explanation.size}"
  for node in explanation do
    IO.println (renderNode node)

end Examples.Provenance

/-- Entry point for `lake env lean --run`. -/
def main : IO Unit := Examples.Provenance.main
