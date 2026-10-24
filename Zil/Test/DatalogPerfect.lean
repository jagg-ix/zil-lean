import Zil.Datalog.Perfect
import Zil.Datalog.Matching
import Lean

/-!
# `unify` means what the declarative reading says, and the evaluator returns the stable model

`Zil.Datalog.Matching` proves that `unify` and `instantiate` compute the declarative reading of a rule (groundings, as in the paper), and
`Zil.Datalog.Perfect` proves that the result of the stratum-by-stratum evaluation is the stable model. These tests use the theorems on
concrete programs, and check that no theorem of the two files uses an axiom beyond the three of classical logic.
-/

open Zil.Datalog

private def node (i : Nat) : Value := .symbol s!"n{i}"
private def edge (i j : Nat) : Atom := { object := node i, relation := "edge", subject := node j }
private def pattern (relation : String) (a b : String) : Pattern :=
  { object := .variable a, relation, subject := .variable b }

/-- `reach` over a chain of 6 edges, and the vertices `n0` does not reach (a negative literal). -/
private def withNegation : Program where
  facts := (List.range 6).map (fun i => edge i (i + 1)) ++
    (List.range 8).map fun i => { object := node i, relation := "vertex", subject := .symbol "yes" }
  rules := [
    { name := "base", head := pattern "reach" "x" "y", literals := [.positive (pattern "edge" "x" "y")] },
    { name := "step", head := pattern "reach" "x" "z",
      literals := [.positive (pattern "reach" "x" "y"), .positive (pattern "edge" "y" "z")] },
    { name := "unreached", head := { object := .variable "x", relation := "unreached", subject := .value (.symbol "yes") },
      literals := [.positive { object := .variable "x", relation := "vertex", subject := .symbol "yes" |> Term.value },
                   .negative { object := .value (node 0), relation := "reach", subject := .variable "x" }] }]

-- The rules of the program are safe, so the declarative reading applies.
#guard withNegation.safe

-- The evaluator's answer is a stable model, and any other stable model has the same atoms.
example : ∃ model, IsStableModel withNegation model := exists_stableModel_of_ok (fuel := defaultFuel) (by native_decide)

example (model : Interpretation) :
    IsModel withNegation model ↔ IsModelGround withNegation model :=
  isModel_iff_ground (Program.safe_isSafe (by native_decide))

example (model : Interpretation) :
    IsStableModel withNegation model ↔
      IsModelGround withNegation model ∧ ∀ atom, atom ∈ model → DerivesGround withNegation model atom :=
  isStableModel_iff_ground (Program.safe_isSafe (by native_decide))

-- What matching means: the pattern `?x#edge@?y` under a grounding is the atom `n1#edge@n2`, and `unify` finds exactly that.
example : Matches (fun x => if x == "x" then node 1 else node 2) (pattern "edge" "x" "y") (edge 1 2) := by
  refine ⟨rfl, rfl, rfl, ?_⟩
  intro k t hkt
  simp [pattern] at hkt

example : ∃ σ, unify (pattern "edge" "x" "y") (edge 1 2) [] = some σ := by
  have hm : Matches (fun x => if x == "x" then node 1 else node 2) (pattern "edge" "x" "y") (edge 1 2) := by
    refine ⟨rfl, rfl, rfl, ?_⟩
    intro k t hkt
    simp [pattern] at hkt
  obtain ⟨σ, hσ, _⟩ := unify_complete (Compat.empty _) hm
  exact ⟨σ, hσ⟩

-- A pattern that does not match is not unified: a different relation, a different object.
#guard (unify (pattern "edge" "x" "y") (edge 1 2) []).isSome
#guard (unify (pattern "reach" "x" "y") (edge 1 2) []).isNone
#guard (unify { object := .value (node 5), relation := "edge", subject := .variable "y" } (edge 1 2) []).isNone

-- The theorems use no axiom beyond the three of classical logic.
open Lean Elab Command in
run_cmd do
  for theoremName in [``unify_sound, ``unify_complete, ``bodyMatches_sound, ``bodyMatches_complete,
      ``mem_applyRuleUnder_iff_ground, ``isModel_iff_ground, ``derivesUnder_iff_ground, ``isStableModel_iff_ground,
      ``saturate_adds_heads, ``saturate_derivesUnder, ``saturateStrata_adds, ``saturateStrata_derivesUnder,
      ``deriveProgramChecked_isStableModel, ``deriveProgramChecked_unique, ``evaluator_eq_certificate] do
    let axioms ← liftCoreM <| collectAxioms theoremName
    for ax in axioms do
      unless ax == ``propext || ax == ``Classical.choice || ax == ``Quot.sound do
        throwError "{theoremName} depends on {ax}"
