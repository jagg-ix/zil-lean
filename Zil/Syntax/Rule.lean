import Lean
import Zil.Core.Rule
import Zil.Syntax.Relation

namespace Zil.Syntax

open Lean Macro

/--
Declare a graph rule using Lean-style `where` blocks.

Bare endpoints are variables. Ground endpoints use `node(name)`.
-/
syntax (name := zilRuleDecl)
  "zil_rule " ident " where" ppLine
  ppIndent("variables" ppSpace ident*) ppLine
  ppIndent("premises" ppLine ppIndent(zilRelation*)) ppLine
  ppIndent("conclusion" ppLine ppIndent(zilRelation)) : command

macro_rules
  | `(zil_rule $ruleName:ident where
        variables $variables:ident*
        premises
          $premises:zilRelation*
        conclusion
          $conclusion:zilRelation) => do
      let ruleNameTerm := quote ruleName.getId
      let variableTerms := variables.map fun variable => quote variable.getId
      let premiseTerms ← premises.mapM expandRelation
      let conclusionTerm ← expandRelation conclusion
      `(def $ruleName : Zil.Rule :=
          { name := $ruleNameTerm
            variables := #[$variableTerms,*]
            premises := #[$premiseTerms,*]
            conclusion := $conclusionTerm
            trust := .graphDerived })

end Zil.Syntax
