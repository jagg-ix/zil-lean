module

public import Zil.Datalog.LeastModel

@[expose] public section

/-!
# Evaluation that says when it is incomplete

`derive`, `deriveStratified`, `query` and `holds` apply the rules a fixed number of times (`fuel`, 32 by default) and return what they have.
When the rules need more rounds, which a rule that extends a path by one step per round does for any path longer than the bound, the
answer is missing facts and nothing says so: `holds` is `false` for a fact that follows, and a query returns too few rows.

The functions here stop as soon as a round adds nothing, and fail when the bound is reached first. A successful result is a model of
the program, every fact of it has a derivation (`deriveProgramChecked_ok`), and for a program without negation it is the least model, so
the answers are exactly the facts that follow (`deriveProgramChecked_leastModel`, `holdsChecked_iff`).
-/

namespace Zil.Datalog

/-- The bound, in rounds, of the checked evaluation. A round that adds nothing ends the loop, so a large bound costs nothing. -/
def defaultFuel : Nat := 1000000

/-- Apply `rules` to `facts` until a round adds nothing: the closure, or `none` when `fuel` rounds were not enough (the round that
finds nothing new counts). -/
def saturate (rules : List Rule) : Nat → List Atom → Option (List Atom)
  | 0, _ => none
  | fuel + 1, facts =>
      let generated := rules.flatMap (applyRule facts)
      if generated.all (facts.contains ·) then some facts
      else saturate rules fuel (facts ++ generated).eraseDups

theorem saturate_spec (program : Program) (rules : List Rule) (hrules : ∀ rule, rule ∈ rules → rule ∈ program.rules) :
    ∀ (fuel : Nat) (facts closed : List Atom), saturate rules fuel facts = some closed →
      (∀ a, a ∈ facts → a ∈ closed) ∧
      (∀ rule, rule ∈ rules → ∀ a, a ∈ applyRule closed rule → a ∈ closed) ∧
      ((∀ a, a ∈ facts → Derives program a) → ∀ a, a ∈ closed → Derives program a) := by
  intro fuel
  induction fuel with
  | zero => intro facts closed h; simp [saturate] at h
  | succ fuel ih =>
      intro facts closed h
      unfold saturate at h
      by_cases hall : (rules.flatMap (applyRule facts)).all (facts.contains ·) = true
      · rw [if_pos hall] at h
        have hc : facts = closed := Option.some.inj h
        subst hc
        refine ⟨fun a ha => ha, ?_, fun hd => hd⟩
        intro rule hrule a ha
        have hmem : a ∈ rules.flatMap (applyRule facts) := List.mem_flatMap.mpr ⟨rule, hrule, ha⟩
        simpa using List.all_eq_true.mp hall a hmem
      · rw [if_neg hall] at h
        obtain ⟨hsub, hclosed, hsound⟩ := ih _ _ h
        refine ⟨fun a ha => hsub a (by simp [List.mem_eraseDups, ha]), hclosed, ?_⟩
        intro hfacts
        apply hsound
        intro a ha
        simp only [List.mem_eraseDups, List.mem_append, List.mem_flatMap] at ha
        rcases ha with ha | ⟨rule, hrule, hgen⟩
        · exact hfacts a ha
        · exact Derives.rule rule facts (hrules rule hrule) hfacts hgen

/-- Saturate the strata in order, each over what the strata before it produced. -/
def saturateStrata (program : Program) (fuel : Nat) : List Nat → List Atom → Except String (List Atom)
  | [], facts => .ok facts
  | stratum :: rest, facts =>
      match saturate (program.rules.filter fun rule => program.stratumOf rule.head.relation == stratum) fuel facts with
      | some closed => saturateStrata program fuel rest closed
      | none => .error s!"the closure of stratum {stratum} did not reach its fixpoint within {fuel} rounds"

theorem saturateStrata_spec (program : Program) (fuel : Nat) :
    ∀ (levels : List Nat) (facts closed : List Atom), saturateStrata program fuel levels facts = .ok closed →
      (∀ a, a ∈ facts → a ∈ closed) ∧
      ((∀ a, a ∈ facts → Derives program a) → ∀ a, a ∈ closed → Derives program a) := by
  intro levels
  induction levels with
  | nil =>
      intro facts closed h
      have hc : facts = closed := Except.ok.inj h
      subst hc
      exact ⟨fun a ha => ha, fun hd => hd⟩
  | cons stratum rest ih =>
      intro facts closed h
      unfold saturateStrata at h
      split at h
      · rename_i stratumClosed hsat
        obtain ⟨hsub1, _, hsound1⟩ := saturate_spec program _
          (fun rule hr => (List.mem_filter.mp hr).1) fuel facts stratumClosed hsat
        obtain ⟨hsub2, hsound2⟩ := ih _ _ h
        exact ⟨fun a ha => hsub2 a (hsub1 a ha), fun hd => hsound2 (hsound1 hd)⟩
      · simp at h

/-- The facts that follow from the program, or the reason there is no answer: the program is not stratified, a stratum did not reach
its fixpoint within `fuel` rounds, or the result is not closed under the rules (which a correct stratification does not allow). -/
def deriveProgramChecked (program : Program) (fuel : Nat := defaultFuel) : Except String (List Atom) :=
  if program.isStratified then
    match saturateStrata program fuel (List.range (program.maxStratum + 1)) program.facts.eraseDups with
    | .error reason => .error reason
    | .ok facts =>
        if (program.rules.flatMap (applyRule facts)).all (facts.contains ·) then .ok facts
        else .error "the strata do not close the program: a rule still derives a new fact"
  else .error "the program is not stratified: a negative dependency lies on a cycle"

/-- A successful result is a stratified model of the program, and every fact of it has a derivation. -/
theorem deriveProgramChecked_ok {program : Program} {fuel : Nat} {facts : List Atom}
    (h : deriveProgramChecked program fuel = .ok facts) :
    IsStratifiedModel program facts ∧ ∀ a, a ∈ facts → Derives program a := by
  unfold deriveProgramChecked at h
  by_cases hs : program.isStratified = true
  · rw [if_pos hs] at h
    split at h
    · simp at h
    · rename_i result hres
      by_cases hall : (program.rules.flatMap (applyRule result)).all (result.contains ·) = true
      · rw [if_pos hall] at h
        have hr : result = facts := Except.ok.inj h
        subst hr
        obtain ⟨hsub, hsound⟩ := saturateStrata_spec program fuel _ _ _ hres
        have hder : ∀ a, a ∈ result → Derives program a :=
          hsound (fun a ha => .fact (List.mem_eraseDups.mp ha))
        refine ⟨⟨hs, fun a ha => hsub a (List.mem_eraseDups.mpr ha), ?_⟩, hder⟩
        intro rule hrule a hcons
        have happ : a ∈ applyRule result rule := ruleConsequence_iff_applyRule_mem.mp hcons
        have hmem : a ∈ program.rules.flatMap (applyRule result) := List.mem_flatMap.mpr ⟨rule, hrule, happ⟩
        simpa using List.all_eq_true.mp hall a hmem
      · rw [if_neg hall] at h
        simp at h
  · rw [if_neg hs] at h
    simp at h

/-- For a program without negation the result is the least model: it is a model, it is inside every model, and a fact is in it
exactly when it has a derivation. This is the model-theoretic semantics of the paper. -/
theorem deriveProgramChecked_leastModel {program : Program} (hpos : program.IsPositive) {fuel : Nat} {facts : List Atom}
    (h : deriveProgramChecked program fuel = .ok facts) :
    IsModel program facts ∧ (∀ other, IsModel program other → ∀ a, a ∈ facts → a ∈ other) ∧
      ∀ a, a ∈ facts ↔ Derives program a := by
  obtain ⟨hmodel, hsound⟩ := deriveProgramChecked_ok h
  have hm := hmodel.isModel
  obtain ⟨hleast, hiff⟩ := leastModel_of_sound_model hpos hm hsound
  exact ⟨hm, hleast, hiff⟩

/-- The substitutions that satisfy `pattern` among the facts that follow, or why there is no answer. -/
def queryChecked (program : Program) (pattern : Pattern) (fuel : Nat := defaultFuel) :
    Except String (List Substitution) :=
  (fun facts => matchPattern facts pattern []) <$> deriveProgramChecked program fuel

/-- Does `atom` follow from the program? An error is not `false`. -/
def holdsChecked (program : Program) (atom : Atom) (fuel : Nat := defaultFuel) : Except String Bool :=
  (·.contains atom) <$> deriveProgramChecked program fuel

/-- For a program without negation, `holdsChecked` answers exactly whether the atom has a derivation. -/
theorem holdsChecked_iff {program : Program} (hpos : program.IsPositive) {fuel : Nat} {atom : Atom} {answer : Bool}
    (h : holdsChecked program atom fuel = .ok answer) : answer = true ↔ Derives program atom := by
  unfold holdsChecked at h
  cases hd : deriveProgramChecked program fuel with
  | error reason =>
      simp only [hd, Functor.map, Except.map] at h
      cases h
  | ok facts =>
      simp only [hd, Functor.map, Except.map] at h
      have hans : answer = facts.contains atom := (Except.ok.inj h).symm
      obtain ⟨_, _, hiff⟩ := deriveProgramChecked_leastModel hpos hd
      rw [hans]
      simpa using hiff atom

end Zil.Datalog
