import Lean
import Zil.Core.DeclarationSet
import Zil.Environment.Knowledge

namespace Zil.Syntax

open Lean Macro

/-- Validate and register all facts lowered from one typed declaration. -/
syntax (name := zilRegisterDeclarationDecl) "zil_register_declaration " term : command

macro_rules
  | `(zil_register_declaration $declaration:term) =>
      `(run_cmd do
          let value : Zil.Declaration := $declaration
          let issues := value.issues
          unless issues.isEmpty do
            throwError m!"invalid ZIL declaration {value.entityName}: {issues[0]!.message}"
          for fact in value.lower do
            Zil.Environment.addEntry (.fact fact))

/-- Validate a declaration collection before generated modules register it. -/
syntax (name := zilCheckDeclarationsDecl) "#zil_check_declarations " term : command

macro_rules
  | `(#zil_check_declarations $declarations:term) =>
      `(run_cmd do
          let values : Array Zil.Declaration := $declarations
          let issues := Zil.DeclarationSet.issues values
          unless issues.isEmpty do
            throwError m!"invalid ZIL declaration set: {issues[0]!.message}")

end Zil.Syntax
