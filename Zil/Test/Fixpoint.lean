import Zil.Authorization
import Zil.Parser.DeclarationProgram
import Zil.Native

/-!
# The closure reaches its fixpoint, or fails

The engine used to stop after 64 rounds per stratum and return what it had, without an error, so a rule that follows a chain one step
per round lost everything past the 65th step: a long chain of calls or dependencies. These tests use a chain of 70 steps (the first
fact is given, the others take one round each), and an access rule that follows a chain of 70 services.
-/

open Zil

private def steps : Nat := 70

/-- `n0 -> n1 -> ... -> n70` and the rules that follow it from `n0`: one new fact for each round. -/
private def chainSource : String :=
  "MODULE chain.fixpoint.\n" ++
  String.join ((List.range steps).map fun i => s!"n:n{i}#next@n:n{i + 1}.\n") ++
  "n:n0#reaches@n:n1.\n" ++
  "RULE step:\n" ++
  "IF n:n0#reaches@?b AND ?b#next@?c\n" ++
  "THEN n:n0#reaches@?c.\n" ++
  "QUERY from_start:\n" ++
  "FIND ?b WHERE n:n0#reaches@?b.\n"

private def chainProgram : Except String Zil.Program :=
  match Zil.Parser.DeclarationProgram.parseText chainSource with
  | .ok program => .ok program
  | .error error => .error error.render

/-- Facts of the full closure: the 70 `next` facts and `reaches` from `n0` to each of `n1 ... n70`. -/
private def fullClosure : Nat := steps + steps

private def failsToConverge {α : Type} : Except String α → Bool
  | .error message => message.startsWith "closure did not reach its fixpoint"
  | .ok _ => false

-- the default is large enough: the closure is complete
#guard match chainProgram with
  | .ok program =>
      match Zil.Engine.closureChecked program.facts program.allRules with
      | .ok closed => closed.size == fullClosure
      | .error _ => false
  | .error _ => false

#guard match chainProgram with
  | .ok program =>
      match Zil.Engine.closureChecked program.facts program.allRules, program.queries[0]? with
      | .ok closed, some query => (Zil.Engine.solve closed query).size == steps
      | _, _ => false
  | .error _ => false

-- a bound that is too small is an error, and not a shorter closure; the last round, which finds nothing new, counts
#guard match chainProgram with
  | .ok program => failsToConverge (Zil.Engine.closureChecked program.facts program.allRules (fuel := 64))
  | .error _ => false

#guard match chainProgram with
  | .ok program => failsToConverge (Zil.Engine.closureChecked program.facts program.allRules (fuel := steps - 1))
  | .error _ => false

#guard match chainProgram with
  | .ok program =>
      match Zil.Engine.closureChecked program.facts program.allRules (fuel := steps) with
      | .ok closed => closed.size == fullClosure
      | .error _ => false
  | .error _ => false

-- the wrapper that cannot return an error documents that it returns the bounded closure
#guard match chainProgram with
  | .ok program =>
      let bounded := Zil.Engine.closure program.facts program.allRules (fuel := 64)
      bounded.size < fullClosure && bounded.size > steps
  | .error _ => false

#guard match chainProgram with
  | .ok program => (Zil.Engine.closure program.facts program.allRules).size == fullClosure
  | .error _ => false

-- the provenance trace follows the same contract
#guard match chainProgram with
  | .ok program =>
      match Zil.Engine.Provenance.traceProgram program with
      | .ok trace => trace.facts.size == fullClosure
      | .error _ => false
  | .error _ => false

#guard match chainProgram with
  | .ok program => failsToConverge (Zil.Engine.Provenance.traceProgram program 64)
  | .error _ => false

-- access along a chain of 70 services, with the rule written as one step per round: a decision that used to come out "denied" is "allowed".
-- (Groups nested with the `#member` userset syntax converge in about log2 of their depth, because the rule that is generated doubles
-- the reach each round; they were never cut off.)
private def accessSource : String :=
  "MODULE chain.access.\n" ++
  String.join ((List.range steps).map fun i => s!"service:s{i}#depends_on@service:s{i + 1}.\n") ++
  s!"service:s{steps}#operator@user:12.\n" ++
  "RULE serviceAccess:\n" ++
  "IF ?service#depends_on@?dependency AND ?dependency#operator@?user\n" ++
  "THEN ?service#operator@?user.\n"

private def accessProgram : Except String Zil.Program :=
  match Zil.Parser.DeclarationProgram.parseText accessSource with
  | .ok program => .ok program
  | .error error => .error error.render

private def operator : Zil.Authorization.Request :=
  { object := .ground `service.s0, relation := `zil.operator, subject := .ground `user.u12 }

#guard match accessProgram with
  | .ok program =>
      match Zil.Authorization.decide program operator with
      | .ok decision => decision.allowed
      | .error _ => false
  | .error _ => false

#guard match accessProgram with
  | .ok program => failsToConverge (Zil.Authorization.decide program operator (fuel := 64))
  | .error _ => false
