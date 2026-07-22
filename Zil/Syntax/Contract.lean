import Lean
import Zil.Contract.Core

namespace Zil.Syntax

open Lean Elab Command

/-- Register a closed `Zil.Contract.FileContract` value. -/
syntax (name := zilRegisterContract) "zil_register_contract " term : command

macro_rules
  | `(zil_register_contract $contract:term) =>
      `(run_cmd Zil.Contract.add $contract)

syntax (name := zilContractCheck) "#zil_contract_check" : command
syntax (name := zilContractCheckStrict) "#zil_contract_check!" : command

private def render (issue : Zil.Contract.Issue) : MessageData :=
  m!"[{repr issue.kind}] {issue.contract}@{issue.revision}: {issue.message}"

elab_rules : command
  | `(#zil_contract_check) => do
      let issues := Zil.Contract.validateLatest (← getEnv)
      for issue in issues do logWarning (render issue)
  | `(#zil_contract_check!) => do
      let issues := Zil.Contract.validateLatest (← getEnv)
      unless issues.isEmpty do
        throwError m!"formalization contract validation failed:\n{MessageData.joinSep (issues.map render) (m!"\n")}"

end Zil.Syntax
