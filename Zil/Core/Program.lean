module

public import Zil.Core.Userset
public import Zil.Core.Query
public import Zil.Core.Macro
public import Zil.Core.DeclarationSet
public import Std.Data.HashMap

@[expose] public section


namespace Zil

/-- Native representation of one parsed ZIL source unit. -/
structure Program where
  moduleName : Option Name := none
  tuples : Array TupleExpr := #[]
  rules : Array Rule := #[]
  queries : Array Query := #[]
  macros : Array MacroDef := #[]
  expansions : Array MacroExpansion := #[]
  declarations : Array Declaration := #[]
  deriving Repr, Inhabited

namespace Program

/-- View the tuple portion through the existing lossless tuple API. -/
def tupleProgram (program : Program) : TupleProgram :=
  { moduleName := program.moduleName, tuples := program.tuples }

/-- Base facts emitted by tuples and validated declarations. -/
def facts (program : Program) : Array RelExpr :=
  let tupleFacts := program.tupleProgram.lower.facts
  match Zil.DeclarationSet.lower program.declarations with
  | .ok declarationFacts =>
      if declarationFacts.isEmpty then tupleFacts
      else
        -- Semantic equality needs the same relation and subject, so a declaration fact is compared only with
        -- that bucket; scanning every fact made a program with many declarations quadratic to lower.
        let bucketOf := fun (index : Std.HashMap (Name × Term) (Array RelExpr)) (fact : RelExpr) =>
          index.getD (fact.relation, fact.subject) #[]
        let index := tupleFacts.foldl (init := ({} : Std.HashMap (Name × Term) (Array RelExpr)))
          fun index fact => index.insert (fact.relation, fact.subject) ((bucketOf index fact).push fact)
        (declarationFacts.foldl (init := (tupleFacts, index)) fun (out, index) fact =>
          let bucket := bucketOf index fact
          if bucket.any (·.semanticallyEqual fact) then (out, index)
          else (out.push fact, index.insert (fact.relation, fact.subject) (bucket.push fact))).1
  | .error _ => tupleFacts

/-- Source rules plus userset traversal rules emitted by tuple lowering. -/
def allRules (program : Program) : Array Rule :=
  program.tupleProgram.lower.rules ++ program.rules

/-- Structural safety for macros, declarations, rules, and queries before stratification. -/
def valid (program : Program) : Bool :=
  program.macros.all MacroDef.valid &&
  Zil.DeclarationSet.valid program.declarations &&
  program.allRules.all (fun rule => rule.allVariablesBound && rule.safe) &&
  program.queries.all (fun query => query.selectedVariablesBound && query.safe)

end Program

end Zil
