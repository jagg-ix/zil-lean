import Lean
import Zil.Profile.Core
import Zil.Syntax.Rule

namespace Zil.Syntax

open Lean Macro

declare_syntax_cat zilVariableKind
syntax ident " : " ident : zilVariableKind

/--
Declare a graph rule together with variable endpoint kinds and a validating profile.
The generated value is a `Zil.TypedRule`; use `.valid` or `#guard` to gate it.
-/
syntax (name := zilTypedRuleDecl)
  "zil_typed_rule " ident " using " ident " where" ppLine
  ppIndent("variables" ppLine ppIndent(zilVariableKind*)) ppLine
  ppIndent("premises" ppLine ppIndent(zilRelation*)) ppLine
  ppIndent("conclusion" ppLine ppIndent(zilRelation)) : command

private def expandVariableKind : Syntax → MacroM (Syntax × Syntax)
  | `(zilVariableKind| $variable:ident : $kind:ident) =>
      pure (quote variable.getId, quote kind.getId)
  | stx => Macro.throwErrorAt stx "invalid ZIL variable-kind declaration"

macro_rules
  | `(zil_typed_rule $ruleName:ident using $profile:ident where
        variables
          $variableKinds:zilVariableKind*
        premises
          $premises:zilRelation*
        conclusion
          $conclusion:zilRelation) => do
      let ruleNameTerm := quote ruleName.getId
      let expandedKinds ← variableKinds.mapM expandVariableKind
      let variableNames := expandedKinds.map (·.1)
      let kindTerms ← expandedKinds.mapM fun pair => do
        let variableName := pair.1
        let kindName := pair.2
        `(Zil.VariableKind.mk $variableName (Zil.NodeKind.ofName $kindName))
      let premiseTerms ← premises.mapM expandRelation
      let conclusionTerm ← expandRelation conclusion
      `(def $ruleName : Zil.TypedRule :=
          { profile := $profile
            variableKinds := #[$kindTerms,*]
            rule :=
              { name := $ruleNameTerm
                variables := #[$variableNames,*]
                premises := #[$premiseTerms,*]
                conclusion := $conclusionTerm
                trust := .graphDerived } })

end Zil.Syntax
