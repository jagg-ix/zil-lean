import Zil.Datalog.Environment

open Lean Elab Command

zil_macro grant(object, subject) => param(object)#viewer@param(subject)
zil_use grant(doc, user)
zil_use grant(service, team)

run_cmd do
  let program := Zil.Datalog.currentProgram (← getEnv)
  unless program.facts.length == 2 do
    throwError "existing zil_macro/zil_use commands did not emit both ground facts"
