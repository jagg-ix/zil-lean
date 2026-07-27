import Zil.Native

open Lean Zil

/-!
# 6. A project verification arc as ZIL knowledge

This example uses synthetic project nodes only. It demonstrates how ZIL can derive
certification and release availability from implementation, test, and release facts
without publishing information about an external project or research program.
-/

zil_fact
  node(lean.Parser.parse)
    ⟶[implements]
  node(requirement.parseInput)

zil_fact
  node(lean.Normalize.normalize)
    ⟶[implements]
  node(requirement.canonicalOutput)

zil_fact
  node(lean.Parser.parse)
    ⟶[passedGate]
  node(gate.nativeTests)

zil_fact
  node(lean.Normalize.normalize)
    ⟶[passedGate]
  node(gate.nativeTests)

zil_fact
  node(lean.Parser.parse)
    ⟶[includedIn]
  node(release.exampleV1)

zil_fact
  node(lean.Normalize.normalize)
    ⟶[includedIn]
  node(release.exampleV1)

zil_theorem_rule requirementCertified
  {declaration requirement gate : Zil.Node}
  (hImplements : declaration ⟶[implements] requirement)
  (hGate : declaration ⟶[passedGate] gate)
  : requirement ⟶[certifiedBy] gate

zil_theorem_rule requirementAvailable
  {declaration requirement release : Zil.Node}
  (hImplements : declaration ⟶[implements] requirement)
  (hRelease : declaration ⟶[includedIn] release)
  : requirement ⟶[availableIn] release

private def availableRequirements : Query := {
  name := `availableRequirements
  «variables» := #[`requirement]
  select := #[`requirement]
  «premises» := #[
    .mk' (.variable `requirement) `zil.availableIn
      (.ground `release.exampleV1)
  ]
}

run_cmd do
  let env ← getEnv
  let facts := Zil.Environment.facts env
  let closed := Zil.Engine.closure facts
    #[requirementCertified, requirementAvailable]
  let certified := RelExpr.mk'
    (.ground `requirement.parseInput)
    `zil.certifiedBy
    (.ground `gate.nativeTests)
  unless closed.any (·.semanticallyEqual certified) do
    throwError "closure did not derive certification"
  let answers := Zil.Engine.solve closed availableRequirements
  unless answers.size == 2 do
    throwError m!"expected two available requirements, found {answers.size}"
  logInfo m!"asserted facts: {facts.size}"
  logInfo m!"closure facts: {closed.size}"
  logInfo m!"requirements available in the example release: {answers.size}"
