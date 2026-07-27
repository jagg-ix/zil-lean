module

public import Zil.Datalog.Eval

@[expose] public section

namespace Zil.Datalog

/--
A finite, kernel-checked explanation tree for the executable positive fragment.

The `support` list records the exact prior closure used by a rule step. This is
intentionally operational for v0.1: it certifies what the evaluator did without
claiming completeness for unsupported or future ZIL profiles.
-/
inductive Derives (program : Program) : Atom → Prop where
  | fact {atom : Atom} :
      atom ∈ program.facts →
      Derives program atom
  | rule {atom : Atom} (rule : Rule) (support : List Atom) :
      rule ∈ program.rules →
      (∀ candidate, candidate ∈ support → Derives program candidate) →
      atom ∈ applyRule support rule →
      Derives program atom

/-- Every result returned by the bounded evaluator has a checked explanation. -/
theorem derive_sound (program : Program) (fuel : Nat) (atom : Atom)
    (h : atom ∈ derive program fuel) : Derives program atom := by
  induction fuel generalizing atom with
  | zero =>
      apply Derives.fact
      simpa only [derive, List.mem_eraseDups] using h
  | succ fuel ih =>
      have h' : atom ∈
          derive program fuel ++ program.rules.flatMap (applyRule (derive program fuel)) := by
        simpa only [derive, deriveStep, List.mem_eraseDups,
          List.mem_append, List.mem_flatMap] using h
      rw [List.mem_append] at h'
      cases h' with
      | inl previous => exact ih atom previous
      | inr generated =>
          rw [List.mem_flatMap] at generated
          obtain ⟨rule, rule_mem, atom_mem⟩ := generated
          exact Derives.rule rule (derive program fuel) rule_mem
            (fun candidate candidate_mem => ih candidate candidate_mem) atom_mem

/-- Saturating any subset of a program's rules preserves derivability when the
input closure is already derivable. -/
theorem deriveRuleSet_sound (program : Program) (rules : List Rule)
    (hrules : ∀ rule, rule ∈ rules → rule ∈ program.rules) (fuel : Nat)
    (facts : List Atom) (hfacts : ∀ atom, atom ∈ facts → Derives program atom)
    (atom : Atom) (h : atom ∈ deriveRuleSet rules fuel facts) : Derives program atom := by
  induction fuel generalizing facts atom with
  | zero =>
      apply hfacts atom
      simpa only [deriveRuleSet, List.mem_eraseDups] using h
  | succ fuel ih =>
      apply ih ((facts ++ rules.flatMap (applyRule facts)).eraseDups)
      · intro candidate candidate_mem
        simp only [List.mem_eraseDups, List.mem_append, List.mem_flatMap] at candidate_mem
        rcases candidate_mem with previous | generated
        · exact hfacts candidate previous
        · obtain ⟨rule, rule_mem, generated_mem⟩ := generated
          exact Derives.rule rule facts (hrules rule rule_mem) hfacts generated_mem
      · exact h

/-- Ordered stratum evaluation only emits atoms with finite operational
derivations in the original program. -/
theorem deriveStratified_sound (program : Program) (fuel : Nat) (atom : Atom)
    (h : atom ∈ deriveStratified program fuel) : Derives program atom := by
  have fold_sound : ∀ (levels : List Nat) (facts : List Atom),
      (∀ candidate, candidate ∈ facts → Derives program candidate) →
      ∀ candidate, candidate ∈ levels.foldl (fun accumulated stratum =>
        let rules := program.rules.filter fun rule =>
          program.stratumOf rule.head.relation == stratum
        deriveRuleSet rules fuel accumulated) facts → Derives program candidate := by
    intro levels
    induction levels with
    | nil =>
        intro facts hfacts candidate candidate_mem
        exact hfacts candidate candidate_mem
    | cons stratum rest ih =>
        intro facts hfacts candidate candidate_mem
        simp only [List.foldl_cons] at candidate_mem
        apply ih _ (fun generated generated_mem =>
          deriveRuleSet_sound program
            (program.rules.filter fun rule => program.stratumOf rule.head.relation == stratum)
            (by
              intro rule rule_mem
              exact (List.mem_filter.mp rule_mem).1)
            fuel facts hfacts generated generated_mem) candidate candidate_mem
  apply fold_sound (List.range (program.maxStratum + 1)) program.facts
  · intro candidate candidate_mem
    exact Derives.fact candidate_mem
  · simpa only [deriveStratified] using h

/-- The proposition exposed to proof tactics and generated snapshot modules. -/
def Holds (program : Program) (atom : Atom) : Prop := Derives program atom

theorem holds_of_derive_mem {program : Program} {fuel : Nat} {atom : Atom}
    (h : atom ∈ derive program fuel) : Holds program atom :=
  derive_sound program fuel atom h

theorem holds_of_deriveProgram_mem {program : Program} {fuel : Nat} {atom : Atom}
    (h : atom ∈ deriveProgram program fuel) : Holds program atom := by
  unfold deriveProgram at h
  split at h
  · exact deriveStratified_sound program fuel atom h
  · exact derive_sound program fuel atom h

end Zil.Datalog
