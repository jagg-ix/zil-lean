import Lean
import Zil.Core.Relation

namespace Zil.Syntax

open Lean Macro

/-- Endpoints used by the Lean-native ZIL relation frontend. Bare identifiers are
rule variables; `node(name)` denotes a ground knowledge node. -/
declare_syntax_cat zilEndpoint
syntax ident : zilEndpoint
syntax "node(" ident ")" : zilEndpoint

/-- A Lean-native subject-relation-object expression. -/
declare_syntax_cat zilRelation
syntax:50 zilEndpoint:51 " ⟶[" ident "] " zilEndpoint:50 : zilRelation

private def expandEndpoint : Syntax → MacroM Syntax
  | `(zilEndpoint| $id:ident) =>
      `(Zil.Term.variable $(quote id.getId))
  | `(zilEndpoint| node($id:ident)) =>
      `(Zil.Term.ground $(quote id.getId))
  | stx => Macro.throwErrorAt stx "invalid ZIL relation endpoint"

/-- Unqualified core relation names are stored under the canonical `zil` namespace. -/
def canonicalRelationName : Name → Name
  | .str .anonymous value => .str `zil value
  | name => name

/-- Lower native relation syntax into the canonical `Zil.RelExpr` IR. -/
def expandRelation : Syntax → MacroM Syntax
  | `(zilRelation| $subject:zilEndpoint ⟶[$relation:ident] $object:zilEndpoint) => do
      let subjectTerm ← expandEndpoint subject
      let objectTerm ← expandEndpoint object
      let relationName := canonicalRelationName relation.getId
      `(Zil.RelExpr.mk' $subjectTerm $(quote relationName) $objectTerm)
  | stx => Macro.throwErrorAt stx "invalid ZIL relation expression"

end Zil.Syntax
