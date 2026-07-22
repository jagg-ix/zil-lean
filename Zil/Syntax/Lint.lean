import Lean
import Zil.Lint.Coverage

namespace Zil.Syntax

open Lean Elab Command

/-- Report formalization coverage gaps as Lean warnings. -/
syntax (name := zilLint) "#zil_lint" : command

macro_rules
  | `(#zil_lint) =>
      `(run_cmd do
          let env ← getEnv
          for issue in Zil.Lint.scan env do
            logWarning (Zil.Lint.render issue))

/-- Fail elaboration when formalization coverage gaps remain. -/
syntax (name := zilLintStrict) "#zil_lint!" : command

macro_rules
  | `(#zil_lint!) =>
      `(run_cmd do
          let env ← getEnv
          let issues := Zil.Lint.scan env
          unless issues.isEmpty do
            let report := String.intercalate "\n" (issues.toList.map Zil.Lint.render)
            throwError "ZIL formalization coverage failed:\n{report}")

end Zil.Syntax
