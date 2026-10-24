import Zil.Datalog.Checked
import Lean

/-!
# The Lean-embedded Datalog says when it is incomplete

`holds` and `query` apply the rules 32 times and return what they have, so a rule that follows a path one step per round misses every
fact past the 32nd step, and `holds` answers `false` for a fact that follows. `holdsChecked` and `queryChecked` stop at the fixpoint and
fail when the bound is reached first. The chain here has 40 edges.
-/

open Zil.Datalog

private def steps : Nat := 40

private def node (i : Nat) : Value := .symbol s!"n{i}"

private def edge (i j : Nat) : Atom := { object := node i, relation := "edge", subject := node j }

private def reach (i j : Nat) : Atom := { object := node i, relation := "reach", subject := node j }

private def pattern (relation : String) (a b : String) : Pattern :=
  { object := .variable a, relation, subject := .variable b }

/-- `reach(x, y) :- edge(x, y)` and `reach(x, z) :- reach(x, y), edge(y, z)`: one new step per round. -/
private def chain : Program where
  facts := (List.range steps).map fun i => edge i (i + 1)
  rules := [
    { name := "base", head := pattern "reach" "x" "y", literals := [.positive (pattern "edge" "x" "y")] },
    { name := "step", head := pattern "reach" "x" "z",
      literals := [.positive (pattern "reach" "x" "y"), .positive (pattern "edge" "y" "z")] }]

private def last : Atom := reach 0 steps

-- The bounded evaluator, with its default of 32 rounds, loses the end of the chain and says `false`.
#guard !(holds chain last)

-- The checked evaluator finds it.
#guard match holdsChecked chain last with | .ok answer => answer | .error _ => false

-- A bound that is too small is an error, not `false`: the 40 steps need 40 rounds and one more that finds nothing new.
#guard match holdsChecked chain last 40 with | .error _ => true | .ok _ => false
#guard match holdsChecked chain last 41 with | .ok answer => answer | .error _ => false

-- The query returns every `y` that `n0` reaches.
#guard match queryChecked chain { object := .value (node 0), relation := "reach", subject := .variable "y" } with
  | .ok rows => rows.length == steps
  | .error _ => false

/-- A stratified program: the vertices that `n0` does not reach. The negative literal reads the finished lower stratum. -/
private def withNegation : Program where
  facts := chain.facts ++ (List.range (steps + 2)).map fun i => { object := node i, relation := "vertex", subject := .symbol "yes" }
  rules := chain.rules ++ [
    { name := "unreached", head := { object := .variable "x", relation := "unreached", subject := .value (.symbol "yes") },
      literals := [.positive { object := .variable "x", relation := "vertex", subject := .value (.symbol "yes") },
                   .negative { object := .value (node 0), relation := "reach", subject := .variable "x" }] }]

-- `n0` reaches `n1` to `n40`; of the 42 vertices, `n0` and `n41` are not reached.
#guard match deriveProgramChecked withNegation with
  | .ok facts => (facts.filter (·.relation == "unreached")).length == 2
  | .error _ => false

/-- A program that is not stratified has no answer. -/
private def cyclic : Program where
  facts := [edge 0 1]
  rules := [
    { name := "a", head := pattern "p" "x" "y", literals := [.positive (pattern "edge" "x" "y"), .negative (pattern "q" "x" "y")] },
    { name := "b", head := pattern "q" "x" "y", literals := [.positive (pattern "edge" "x" "y"), .negative (pattern "p" "x" "y")] }]

#guard match deriveProgramChecked cyclic with | .error _ => true | .ok _ => false

-- The theorems of `Zil.Datalog.LeastModel` and `Zil.Datalog.Checked` use no axiom beyond the three of classical logic.
open Lean Elab Command in
run_cmd do
  for theoremName in [``leastModel_of_sound_model, ``derives_mem_model, ``isStableModel_iff, ``deriveProgramChecked_ok,
      ``deriveProgramChecked_leastModel, ``holdsChecked_iff] do
    let axioms ← liftCoreM <| collectAxioms theoremName
    for ax in axioms do
      unless ax == ``propext || ax == ``Classical.choice || ax == ``Quot.sound do
        throwError "{theoremName} depends on {ax}"
