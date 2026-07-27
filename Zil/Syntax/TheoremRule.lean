import Lean
import Zil.Syntax.Relation
import Zil.Core.Rule

namespace Zil.Syntax

open Lean Macro

declare_syntax_cat zilRuleHyp
syntax "(" ident " : " zilRelation ")" : zilRuleHyp

/-- Theorem-shaped graph-rule frontend. Binder types are required to be `Zil.Node`. -/
syntax (name := zilTheoremRuleDecl)
  "zil_theorem_rule " ident
  " {" ident* " : " ident "}" ppLine
  zilRuleHyp* ppLine
  " : " zilRelation : command

private def expandHyp : Syntax → MacroM (TSyntax `term)
  | `(zilRuleHyp| ($_:ident : $relation:zilRelation)) => expandRelation relation
  | stx => Macro.throwErrorAt stx "invalid theorem-shaped ZIL hypothesis"

macro_rules
  | `(zil_theorem_rule $ruleName:ident
        {$vars:ident* : $binderType:ident}
        $hypotheses:zilRuleHyp*
        : $concl:zilRelation) => do
      unless binderType.getId == `Zil.Node do
        Macro.throwErrorAt binderType "theorem-shaped rule binders must have type Zil.Node"
      let ruleNameTerm := quote ruleName.getId
      let variableTerms : Syntax.TSepArray `term "," := .ofElems (vars.map fun v => quote v.getId)
      let premiseTerms : Syntax.TSepArray `term "," := .ofElems (← hypotheses.mapM expandHyp)
      let conclusionTerm ← expandRelation concl
      `(def $ruleName : Zil.Rule :=
          { name := $ruleNameTerm
            «variables» := #[$variableTerms,*]
            «premises» := #[$premiseTerms,*]
            «conclusion» := $conclusionTerm
            trust := .graphDerived })

end Zil.Syntax
