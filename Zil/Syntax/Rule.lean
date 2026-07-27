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
        variables $vars:ident*
        premises
          $prems:zilRelation*
        conclusion
          $concl:zilRelation) => do
      let ruleNameTerm := quote ruleName.getId
      let variableTerms : Syntax.TSepArray `term "," := .ofElems (vars.map fun v => quote v.getId)
      let premiseTerms : Syntax.TSepArray `term "," := .ofElems (← prems.mapM expandRelation)
      let conclusionTerm ← expandRelation concl
      `(def $ruleName : Zil.Rule :=
          { name := $ruleNameTerm
            «variables» := #[$variableTerms,*]
            «premises» := #[$premiseTerms,*]
            «conclusion» := $conclusionTerm
            trust := .graphDerived })

end Zil.Syntax
