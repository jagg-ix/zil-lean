import Lean
import Zil.Trust.Certified

namespace Zil.Syntax

open Lean Elab Command

/-- Register a proof-carrying certified rule. Ordinary `zil_register_rule` remains graph-only. -/
syntax (name := zilRegisterCertifiedRuleDecl) "zil_register_certified_rule " term : command

elab_rules : command
  | `(zil_register_certified_rule $entry:term) => do
      let value ← liftTermElabM do
        let expression ← Elab.Term.elabTermEnsuringType entry (mkConst ``Zil.Trust.CertifiedRule)
        Meta.evalExpr Zil.Trust.CertifiedRule (mkConst ``Zil.Trust.CertifiedRule) expression
      liftCoreM <| Zil.Trust.addCertifiedRule value

/-- Reject ordinary registration attempts that manually set `.certified`. -/
syntax (name := zilRegisterGraphRuleSafeDecl) "zil_register_graph_rule " term : command

elab_rules : command
  | `(zil_register_graph_rule $rule:term) => do
      let value ← liftTermElabM do
        let expression ← Elab.Term.elabTermEnsuringType rule (mkConst ``Zil.Rule)
        Meta.evalExpr Zil.Rule (mkConst ``Zil.Rule) expression
      if value.trust == .certified then
        throwError "ordinary graph-rule registration cannot claim certified trust; use zil_register_certified_rule"
      liftCoreM <| Zil.Environment.addEntry (.rule value)

end Zil.Syntax
