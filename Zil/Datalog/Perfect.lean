module

public import Zil.Datalog.Certify

@[expose] public section

/-!
# The result of the stratum-by-stratum evaluation is the stable model

`deriveProgramChecked` saturates the strata in order: the rules whose head is in stratum `k` are applied until nothing is new, with
the negative literals read against what the strata below `k` produced, and then the next stratum is saturated. Its result is a
model of the program (`deriveProgramChecked_ok`). This file proves that it is also the stable model of the program
(`deriveProgramChecked_isStableModel`): every fact of the result has a finite derivation in which the negative literals are read against
the *final* result, not only against the facts that were there when the rule fired.

The argument is that a stratum only adds facts of its own relations. A negative literal of a rule in stratum `k` is over a relation of a
stratum below `k` (the check `Program.strataValid`), so every fact of the final result that the literal could match was already there
when the rule fired. With `stable_unique` (`Zil.Datalog.Stratified`) this makes the evaluator's answer the only stable model, and it
agrees with every certificate the checker accepts (`evaluator_eq_certificate`).
-/

namespace Zil.Datalog

/-- A stratum adds only facts of the relations that its rules derive. -/
theorem saturate_adds_heads (rules : List Rule) :
    ∀ (fuel : Nat) (facts closed : List Atom), saturate rules fuel facts = some closed →
      ∀ b, b ∈ closed → b ∈ facts ∨ ∃ r, r ∈ rules ∧ b.relation = r.head.relation := by
  intro fuel
  induction fuel with
  | zero => intro facts closed h; simp [saturate] at h
  | succ fuel ih =>
      intro facts closed h b hb
      unfold saturate at h
      by_cases hall : (rules.flatMap (applyRule facts)).all (facts.contains ·) = true
      · rw [if_pos hall] at h
        have hc : facts = closed := Option.some.inj h
        subst hc
        exact Or.inl hb
      · rw [if_neg hall] at h
        rcases ih _ _ h b hb with hb' | hb'
        · simp only [List.mem_eraseDups, List.mem_append, List.mem_flatMap] at hb'
          rcases hb' with hb' | ⟨r, hr, hgen⟩
          · exact Or.inl hb'
          · obtain ⟨σ, _, _, hinst⟩ := mem_applyRuleUnder.mp hgen
            exact Or.inr ⟨r, hr, instantiate_relation hinst⟩
        · exact Or.inr hb'

/-- A stratum is saturated against a reference set `ref` that holds, for the relations its rules negate, only facts that were there before.
Then every fact it produces has a derivation in which the negative literals are read against `ref`. -/
theorem saturate_derivesUnder {program : Program} {rules : List Rule} (hrules : ∀ r, r ∈ rules → r ∈ program.rules)
    (ref : Interpretation) :
    ∀ (fuel : Nat) (facts closed : List Atom), saturate rules fuel facts = some closed →
      (∀ a, a ∈ facts → DerivesUnder program ref a) →
      (∀ r, r ∈ rules → ∀ n, n ∈ r.negativePatterns → ∀ b, b ∈ ref → b.relation = n.relation → b ∈ facts) →
      ∀ a, a ∈ closed → DerivesUnder program ref a := by
  intro fuel
  induction fuel with
  | zero => intro facts closed h; simp [saturate] at h
  | succ fuel ih =>
      intro facts closed h hfacts hfrozen
      unfold saturate at h
      by_cases hall : (rules.flatMap (applyRule facts)).all (facts.contains ·) = true
      · rw [if_pos hall] at h
        have hc : facts = closed := Option.some.inj h
        subst hc
        exact hfacts
      · rw [if_neg hall] at h
        refine ih _ _ h ?_ ?_
        · intro a ha
          simp only [List.mem_eraseDups, List.mem_append, List.mem_flatMap] at ha
          rcases ha with ha | ⟨r, hr, hgen⟩
          · exact hfacts a ha
          · -- the rule fired against `facts`; its negative literals are absent from `ref` too
            obtain ⟨σ, hbody, habsent, hinst⟩ := mem_applyRuleUnder.mp hgen
            have hrefAbsent : ∀ n, n ∈ r.negativePatterns → Absent ref n σ := by
              intro n hn b hb
              by_cases hrel : b.relation = n.relation
              · exact habsent n hn b (hfrozen r hr n hn b hb hrel)
              · exact unify_none_of_relation σ hrel
            exact .rule r facts (hrules r hr) hfacts (mem_applyRuleUnder.mpr ⟨σ, hbody, hrefAbsent, hinst⟩)
        · intro r hr n hn b hb hrel
          have := hfrozen r hr n hn b hb hrel
          simp [List.mem_eraseDups, this]

/-- The strata between them add only facts of the relations of those strata. -/
theorem saturateStrata_adds (program : Program) (fuel : Nat) :
    ∀ (levels : List Nat) (facts closed : List Atom), saturateStrata program fuel levels facts = .ok closed →
      ∀ b, b ∈ closed → b ∈ facts ∨ program.stratumOf b.relation ∈ levels := by
  intro levels
  induction levels with
  | nil =>
      intro facts closed h b hb
      have hc : facts = closed := Except.ok.inj h
      subst hc
      exact Or.inl hb
  | cons stratum rest ih =>
      intro facts closed h b hb
      unfold saturateStrata at h
      split at h
      · rename_i stratumClosed hsat
        rcases ih _ _ h b hb with hb' | hb'
        · rcases saturate_adds_heads _ fuel _ _ hsat b hb' with hb'' | ⟨r, hr, hrel⟩
          · exact Or.inl hb''
          · right
            have hr' := (List.mem_filter.mp hr).2
            have : program.stratumOf r.head.relation = stratum := by simpa using hr'
            rw [hrel, this]
            exact List.mem_cons_self ..
        · exact Or.inr (List.mem_cons_of_mem _ hb')
      · simp at h

/-- Along the strata, every fact has a derivation under the final result. -/
theorem saturateStrata_derivesUnder {program : Program} (fuel : Nat) (hvalid : program.StrataValid program.stratumOf)
    (ref : Interpretation) :
    ∀ (levels : List Nat), levels.Pairwise (· < ·) → ∀ (facts : List Atom),
      saturateStrata program fuel levels facts = .ok ref →
      (∀ a, a ∈ facts → DerivesUnder program ref a) →
      -- what the result has below every remaining stratum was there already
      (∀ b, b ∈ ref → (∀ l, l ∈ levels → program.stratumOf b.relation < l) → b ∈ facts) →
      ∀ a, a ∈ ref → DerivesUnder program ref a := by
  intro levels
  induction levels with
  | nil =>
      intro _ facts h hfacts _
      have hc : facts = ref := Except.ok.inj h
      subst hc
      exact hfacts
  | cons stratum rest ih =>
      intro hsorted facts h hfacts hbelow
      have hrest : rest.Pairwise (· < ·) := (List.pairwise_cons.mp hsorted).2
      have hgt : ∀ l, l ∈ rest → stratum < l := (List.pairwise_cons.mp hsorted).1
      unfold saturateStrata at h
      split at h
      · rename_i closed hsat
        have hderives : ∀ a, a ∈ closed → DerivesUnder program ref a := by
          refine saturate_derivesUnder (fun r hr => (List.mem_filter.mp hr).1) ref fuel facts closed hsat hfacts ?_
          intro r hr n hn b hb hrel
          obtain ⟨hrmem, hrstratum⟩ := List.mem_filter.mp hr
          have hhead : program.stratumOf r.head.relation = stratum := by simpa using hrstratum
          have hlt : program.stratumOf n.relation < program.stratumOf r.head.relation :=
            hvalid r hrmem _ (mem_negativePatterns hn)
          refine hbelow b hb ?_
          intro l hl
          have hbstratum : program.stratumOf b.relation < stratum := by rw [hrel, ← hhead]; exact hlt
          rcases List.mem_cons.mp hl with rfl | hl'
          · exact hbstratum
          · exact Nat.lt_trans hbstratum (hgt l hl')
        refine ih hrest closed h hderives ?_
        intro b hb hlow
        rcases saturateStrata_adds program fuel rest closed ref h b hb with hbc | hbs
        · exact hbc
        · exact absurd (hlow _ hbs) (Nat.lt_irrefl _)
      · simp at h

/-- **The evaluator's result is the stable model.** If `deriveProgramChecked` returns a set, that set is a stable model of the program:
it is a model, and every fact of it has a finite derivation whose negative literals are read against the whole result. -/
theorem deriveProgramChecked_isStableModel {program : Program} {fuel : Nat} {facts : List Atom}
    (h : deriveProgramChecked program fuel = .ok facts) : IsStableModel program facts := by
  obtain ⟨_, hvalid, hres, _⟩ := deriveProgramChecked_unfold h
  have hmodel := (deriveProgramChecked_ok h).1.isModel
  refine ⟨hmodel, ?_⟩
  have key := saturateStrata_derivesUnder (program := program) fuel (Program.strataValid_spec hvalid) facts
    (List.range (program.maxStratum + 1)) List.pairwise_lt_range program.facts.eraseDups hres
    (fun a ha => .fact (List.mem_eraseDups.mp ha))
    (fun b _ hlow => absurd (hlow 0 (List.mem_range.mpr (Nat.succ_pos _))) (Nat.not_lt_zero _))
  exact key

/-- If the evaluator answers, the program has a stable model (this is how to use the theorem on a concrete program). -/
theorem exists_stableModel_of_ok {program : Program} {fuel : Nat}
    (h : (deriveProgramChecked program fuel).toOption.isSome = true) : ∃ model, IsStableModel program model := by
  cases hd : deriveProgramChecked program fuel with
  | error reason => simp [hd, Except.toOption] at h
  | ok facts => exact ⟨facts, deriveProgramChecked_isStableModel hd⟩

/-- Any stable model of the program contains exactly the facts the evaluator returns. -/
theorem deriveProgramChecked_unique {program : Program} {fuel : Nat} {facts : List Atom}
    (h : deriveProgramChecked program fuel = .ok facts) {other : Interpretation} (hother : IsStableModel program other) :
    ∀ a, a ∈ other ↔ a ∈ facts := by
  obtain ⟨_, hvalid, _, _⟩ := deriveProgramChecked_unfold h
  exact stable_unique (Program.strataValid_spec hvalid) hother (deriveProgramChecked_isStableModel h)

/-- **The evaluator and the checker agree.** If the evaluator returns a set and the checker accepts a certificate, they contain the
same atoms. -/
theorem evaluator_eq_certificate {program : Program} {fuel : Nat} {facts : List Atom} {cert : Certificate}
    (h : deriveProgramChecked program fuel = .ok facts) (hcert : checkCertificate program cert = true) :
    ∀ a, a ∈ facts ↔ a ∈ cert.map (·.atom) :=
  fun a => (deriveProgramChecked_unique h (checkCertificate_sound hcert) a).symm

end Zil.Datalog
