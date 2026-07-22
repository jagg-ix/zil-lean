import Lean
import Zil.Environment.Knowledge
import Zil.Syntax.Relation

namespace Zil.Syntax

open Lean Elab Command

/-- Register a ground fact in the persistent ZIL environment. -/
syntax (name := zilFactDecl) "zil_fact " zilRelation : command

elab_rules : command
  | `(zil_fact $relation:zilRelation) => do
      let relationTerm ← expandRelation relation
      let command ← `(Zil.Environment.addEntry (.fact $relationTerm))
      elabCommand command

/-- Register an existing `Zil.Rule` value in the persistent environment. -/
syntax (name := zilRegisterRuleDecl) "zil_register_rule " term : command

elab_rules : command
  | `(zil_register_rule $rule:term) =>
      elabCommand (← `(Zil.Environment.addEntry (.rule $rule)))

/-- Register an existing profile in the persistent environment. -/
syntax (name := zilRegisterProfileDecl) "zil_register_profile " term : command

elab_rules : command
  | `(zil_register_profile $profile:term) =>
      elabCommand (← `(Zil.Environment.addEntry (.profile $profile)))

/-- Attach one ground relation to an existing Lean declaration. -/
syntax (name := zilDeclarationLinkDecl)
  "zil_link " ident " with " zilRelation : command

elab_rules : command
  | `(zil_link $declaration:ident with $relation:zilRelation) => do
      let relationTerm ← expandRelation relation
      let declarationName := quote declaration.getId
      elabCommand (← `(Zil.Environment.addEntry
        (.declarationLink $declarationName $relationTerm)))

end Zil.Syntax
