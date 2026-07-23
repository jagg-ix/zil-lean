import Zil

open Zil

/-!
# 1. Facts and relations

A ZIL fact is a directed relation:

    subject ⟶[relation] object

Ground nodes are written explicitly with `node(...)`.
-/

zil_fact
  node(lean.Example.metric)
    ⟶[formalizes]
  node(claim.exampleMetric)

zil_fact
  node(lean.Example.metric)
    ⟶[requires]
  node(requirement.lorentzianMetric)

run_cmd do
  let env ← getEnv
  let expected := RelExpr.mk'
    (.ground `lean.Example.metric)
    `zil.formalizes
    (.ground `claim.exampleMetric)
  unless Zil.Environment.containsFact env expected do
    throwError "the formalizes fact was not registered"
  logInfo m!"registered facts: {(Zil.Environment.facts env).size}"
