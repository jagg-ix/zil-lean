import Lean
import Zil.Environment.Knowledge
import Zil.Core.Userset
import Zil.Syntax.Relation

namespace Zil.Syntax

open Lean Macro

/-- Register a ground fact in the persistent ZIL environment. -/
syntax (name := zilFactDecl) "zil_fact " zilRelation : command

macro_rules
  | `(zil_fact $relation:zilRelation) => do
      let relationTerm ← expandRelation relation
      `(run_cmd do
          let fact : Zil.RelExpr := $relationTerm
          unless fact.isGround do
            throwError "zil_fact requires ground node(...) endpoints"
          Zil.Environment.addEntry (.fact fact))

/-- Register one lossless tuple and all facts/rules produced by its lowering. -/
syntax (name := zilRegisterTupleDecl) "zil_register_tuple " term : command

macro_rules
  | `(zil_register_tuple $tuple:term) =>
      `(run_cmd do
          let value : Zil.TupleExpr := $tuple
          unless value.isGround do
            throwError "zil_register_tuple requires a ground tuple"
          let lowered := value.lower
          for fact in lowered.facts do
            Zil.Environment.addEntry (.fact fact)
          for rule in lowered.rules do
            Zil.Environment.addEntry (.rule rule))

/-- Register an existing closed `Zil.Rule` value in the persistent environment. -/
syntax (name := zilRegisterRuleDecl) "zil_register_rule " term : command

macro_rules
  | `(zil_register_rule $rule:term) =>
      `(run_cmd do
          let value : Zil.Rule := $rule
          Zil.Environment.addEntry (.rule value))

/-- Register an existing closed profile value in the persistent environment. -/
syntax (name := zilRegisterProfileDecl) "zil_register_profile " term : command

macro_rules
  | `(zil_register_profile $profile:term) =>
      `(run_cmd do
          let value : Zil.Profile := $profile
          Zil.Environment.addEntry (.profile value))

/-- Attach one ground relation to an existing Lean declaration name. -/
syntax (name := zilDeclarationLinkDecl)
  "zil_link " ident " with " zilRelation : command

macro_rules
  | `(zil_link $declaration:ident with $relation:zilRelation) => do
      let relationTerm ← expandRelation relation
      let declarationName := quote declaration.getId
      `(run_cmd do
          let link : Zil.RelExpr := $relationTerm
          unless link.isGround do
            throwError "zil_link requires ground node(...) endpoints"
          Zil.Environment.addEntry
            (.declarationLink $declarationName link))

end Zil.Syntax
