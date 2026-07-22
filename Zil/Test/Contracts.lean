import Zil.Syntax.Contract
import Zil.Test.Environment.A

open Zil

private def goodContract : Zil.Contract.FileContract :=
  { name := `contract.environmentPersistence
    revision := 1
    advertisedScope := "persistent graph environment"
    abstractionLevel := "canonical relational IR"
    requiredDeclarations := #[`Zil.Test.EnvironmentA.sampleDeclaration]
    requiredRelations := #[
      .mk' (.ground `lean.Zil.Test.EnvironmentA.sampleDeclaration)
        `zil.formalizes (.ground `claim.environmentPersistence)]
    status := .complete }

private def incompleteContract : Zil.Contract.FileContract :=
  { name := `contract.incomplete
    revision := 1
    advertisedScope := "missing theorem fixture"
    abstractionLevel := "declaration"
    requiredDeclarations := #[`Zil.Test.DoesNotExist]
    status := .complete }

zil_register_contract goodContract
zil_register_contract incompleteContract

run_cmd do
  let env ← getEnv
  unless (Zil.Contract.validate env goodContract).isEmpty do
    throwError "valid contract was rejected"
  let issues := Zil.Contract.validate env incompleteContract
  unless issues.any (fun issue => issue.kind == .missingDeclaration) do
    throwError "missing declaration was not diagnosed"
  unless issues.any (fun issue => issue.kind == .prematureCompletion) do
    throwError "premature completion was not diagnosed"
