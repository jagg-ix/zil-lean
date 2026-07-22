import Zil.Test.Environment.Left
import Zil.Test.Environment.Right

open Lean

run_cmd do
  let env ← getEnv
  unless (Zil.Environment.rules env).size == 1 do
    throwError "diamond imports duplicated a persisted ZIL rule"
  unless (Zil.Environment.profiles env).size == 1 do
    throwError "diamond imports duplicated a persisted ZIL profile"
  unless (Zil.Environment.facts env).size == 2 do
    throwError "diamond imports duplicated persisted ZIL facts"
  let links := Zil.Environment.linksForDeclaration env
    `Zil.Test.EnvironmentA.sampleDeclaration
  unless links.size == 1 do
    throwError "diamond imports duplicated a declaration link"
