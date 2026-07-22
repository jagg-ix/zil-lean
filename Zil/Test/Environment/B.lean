import Zil.Test.Environment.A

open Lean

run_cmd do
  let env ← getEnv
  let target : Zil.RelExpr :=
    .mk'
      (.ground `lean.Zil.Test.EnvironmentA.sampleDeclaration)
      `zil.formalizes
      (.ground `claim.environmentPersistence)
  unless Zil.Environment.containsFact env target do
    throwError "imported ZIL fact was not restored from .olean"
  unless Zil.Environment.containsRule env `Zil.Test.EnvironmentA.importedRequirementRule do
    throwError "imported ZIL rule was not restored from .olean"
  unless Zil.Environment.containsProfile env `zil.profile.research "0.1" do
    throwError "imported ZIL profile was not restored from .olean"
  let links := Zil.Environment.linksForDeclaration env
    `Zil.Test.EnvironmentA.sampleDeclaration
  unless links.size == 1 do
    throwError m!"expected exactly one imported declaration link, found {links.size}"
  unless (Zil.Environment.facts env).size == 2 do
    throwError "expected one fact plus one declaration-linked fact"
