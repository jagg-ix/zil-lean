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
  " {" ident* " : Zil.Node}" ppLine
  zilRuleHyp* ppLine
  " : " zilRelation : command

private def expandHyp : Syntax → MacroM Syntax
  | `(zilRuleHyp| ($name:ident : $relation:zilRelation)) => expandRelation relation
  | stx => Macro.throwErrorAt stx "invalid theorem-shaped ZIL hypothesis"

macro_rules
  | `(zil_theorem_rule $ruleName:ident
        {$variables:ident* : Zil.Node}
        $hypotheses:zilRuleHyp*
        : $conclusion:zilRelation) => do
      let ruleNameTerm := quote ruleName.getId
      let variableTerms := variables.map fun variable => quote variable.getId
      let premiseTerms ← hypotheses.mapM expandHyp
      let conclusionTerm ← expandRelation conclusion
      `(def $ruleName : Zil.Rule :=
          { name := $ruleNameTerm
            variables := #[$variableTerms,*]
            premises := #[$premiseTerms,*]
            conclusion := $conclusionTerm
            trust := .graphDerived })

end Zil.Syntax
