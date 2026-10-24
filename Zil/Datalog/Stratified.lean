module

public import Zil.Datalog.LeastModel

@[expose] public section

/-!
# A stratified program has one stable model

The semantics of a program with negation (`Zil.Datalog.LeastModel`) is the stable model: a set that is closed under the rules and whose
atoms all have a derivation in which the negative literals are read against the set itself. That alone does not make the answer
unique; a program that negates itself has none or several. A program whose relations can be ordered into strata, so that a rule's
positive literals are in the same stratum as its head or below it and its negative literals strictly below, has exactly one: whatever
the evaluation order, two stable models contain the same atoms (`stable_unique`).

`Program.strataValid` is the check that the strata the evaluator uses (`Program.stratumOf`) respect the dependencies. It is a check of the
result, not a proof about how the strata are computed, so the theorem holds for whatever `stratumOf` returns.
-/

namespace Zil.Datalog

/-- The numbering `stratum` of the relations respects the rules. -/
def Program.StrataValid (program : Program) (stratum : String → Nat) : Prop :=
  ∀ rule, rule ∈ program.rules → ∀ literal, literal ∈ rule.literals →
    match literal with
    | .positive pattern => stratum pattern.relation ≤ stratum rule.head.relation
    | .negative pattern => stratum pattern.relation < stratum rule.head.relation

/-- The strata that the evaluator computes respect the rules. -/
def Program.strataValid (program : Program) : Bool :=
  program.rules.all fun rule => rule.literals.all fun literal =>
    match literal with
    | .positive pattern => program.stratumOf pattern.relation ≤ program.stratumOf rule.head.relation
    | .negative pattern => program.stratumOf pattern.relation < program.stratumOf rule.head.relation

theorem Program.strataValid_spec {program : Program} (h : program.strataValid = true) :
    program.StrataValid program.stratumOf := by
  intro rule hrule literal hliteral
  unfold Program.strataValid at h
  have hr := List.all_eq_true.mp h rule hrule
  have hl := List.all_eq_true.mp hr literal hliteral
  cases literal with
  | positive pattern => simpa using hl
  | negative pattern => simpa using hl

theorem unify_relation {pattern : Pattern} {atom : Atom} {σ σ' : Substitution}
    (h : unify pattern atom σ = some σ') : atom.relation = pattern.relation := by
  unfold unify at h
  by_cases hrel : (pattern.relation != atom.relation) = true
  · simp [hrel] at h
  · simp only [Bool.not_eq_true, bne_eq_false_iff_eq] at hrel
    exact hrel.symm

theorem unify_none_of_relation {pattern : Pattern} {atom : Atom} (σ : Substitution)
    (h : atom.relation ≠ pattern.relation) : unify pattern atom σ = none := by
  unfold unify
  have : (pattern.relation != atom.relation) = true := by
    simpa [bne_iff_ne, ne_eq] using Ne.symm h
  simp [this]

theorem instantiate_relation {pattern : Pattern} {σ : Substitution} {atom : Atom}
    (h : instantiate pattern σ = some atom) : atom.relation = pattern.relation := by
  unfold instantiate at h
  cases ho : instantiateTerm σ pattern.object with
  | none => simp [ho] at h
  | some object =>
      cases hs : instantiateTerm σ pattern.subject with
      | none => simp [ho, hs] at h
      | some subject =>
          cases ha : instantiateAttrs σ pattern.attrs with
          | none => simp [ho, hs, ha] at h
          | some attrs =>
              simp only [ho, hs, ha, Option.pure_def] at h
              have := Option.some.inj h
              subst this
              rfl

/-- Matching against the atoms of `facts` can be done against `other` instead, if `other` has every atom of `facts` that a pattern of
the body could match. -/
theorem BodyMatches.transfer {facts other : List Atom} :
    ∀ {ps : List Pattern} {σ σ' : Substitution}, BodyMatches facts ps σ σ' →
      (∀ p, p ∈ ps → ∀ a, a ∈ facts → a.relation = p.relation → a ∈ other) → BodyMatches other ps σ σ'
  | _, _, _, .nil, _ => .nil
  | _, _, _, .cons ha hu rest, h =>
      .cons (h _ (List.mem_cons_self ..) _ ha (unify_relation hu)) hu
        (rest.transfer fun p hp => h p (List.mem_cons_of_mem _ hp))

/-- Two sets that agree on the atoms of a relation read a negative literal over that relation alike. -/
theorem absent_of_agree {s₁ s₂ : List Atom} {pattern : Pattern} {σ : Substitution}
    (hagree : ∀ a, a.relation = pattern.relation → (a ∈ s₂ → a ∈ s₁))
    (h : Absent s₁ pattern σ) : Absent s₂ pattern σ := by
  intro a ha
  by_cases hrel : a.relation = pattern.relation
  · exact h a (hagree a hrel ha)
  · exact unify_none_of_relation σ hrel

theorem mem_positiveBody {rule : Rule} {pattern : Pattern} (h : pattern ∈ rule.positiveBody) :
    Literal.positive pattern ∈ rule.literals := by
  unfold Rule.positiveBody Rule.effectiveLiterals at h
  obtain ⟨literal, hl, hmap⟩ := List.mem_filterMap.mp h
  cases literal with
  | positive q => cases hmap; exact hl
  | negative q => simp at hmap

theorem mem_negativePatterns {rule : Rule} {pattern : Pattern} (h : pattern ∈ rule.negativePatterns) :
    Literal.negative pattern ∈ rule.literals := by
  unfold Rule.negativePatterns Rule.effectiveLiterals at h
  obtain ⟨literal, hl, hmap⟩ := List.mem_filterMap.mp h
  cases literal with
  | positive q => simp at hmap
  | negative q => cases hmap; exact hl

/-- Up to stratum `k`: whatever has a derivation under `s₁` is in `s₂`, given that `s₂` is a model and that the two agree on every
relation of a lower stratum. -/
theorem derivesUnder_mem_of_agree {program : Program} {stratum : String → Nat} (hvalid : program.StrataValid stratum)
    {s₁ s₂ : Interpretation} (hmodel : IsModel program s₂) (k : Nat)
    (hlow : ∀ a : Atom, stratum a.relation < k → (a ∈ s₁ ↔ a ∈ s₂)) :
    ∀ {b : Atom}, DerivesUnder program s₁ b → stratum b.relation ≤ k → b ∈ s₂ := by
  intro b h
  induction h with
  | fact hf => intro _; exact hmodel.facts _ hf
  | rule r support hr _ happ ih =>
      intro hk
      rw [mem_applyRuleUnder] at happ
      obtain ⟨σ, hbody, hneg, hinst⟩ := happ
      have hhead := instantiate_relation hinst
      have hheadk : stratum r.head.relation ≤ k := by rw [← hhead]; exact hk
      -- the positive literals match atoms of `s₂` too: the atoms they could match are derived from lower or equal strata
      have hbody2 : BodyMatches s₂ r.positiveBody [] σ := by
        refine hbody.transfer fun p hp a ha hrel => ?_
        have hv : stratum p.relation ≤ stratum r.head.relation := hvalid r hr _ (mem_positiveBody hp)
        exact ih a ha (by rw [hrel]; omega)
      -- and the negative literals are absent from `s₂`, because they are over lower strata, where the two sets agree
      have hneg2 : ∀ p, p ∈ r.negativePatterns → Absent s₂ p σ := by
        intro p hp
        have hv : stratum p.relation < stratum r.head.relation := hvalid r hr _ (mem_negativePatterns hp)
        refine absent_of_agree (fun a hrel ha => ?_) (hneg p hp)
        exact (hlow a (by rw [hrel]; omega)).mpr ha
      exact hmodel.closed r hr _ (mem_applyRuleUnder.mpr ⟨σ, hbody2, hneg2, hinst⟩)

/-- **A stratified program has one stable model.** If the relations are numbered so that no positive literal is above its rule's head
and no negative literal is at or above it, two stable models contain the same atoms. -/
theorem stable_unique {program : Program} {stratum : String → Nat} (hvalid : program.StrataValid stratum)
    {s₁ s₂ : Interpretation} (h₁ : IsStableModel program s₁) (h₂ : IsStableModel program s₂) :
    ∀ a, a ∈ s₁ ↔ a ∈ s₂ := by
  have key : ∀ k, ∀ a : Atom, stratum a.relation = k → (a ∈ s₁ ↔ a ∈ s₂) := by
    intro k
    induction k using Nat.strongRecOn with
    | _ k ih =>
        intro a hk
        have hlow : ∀ c : Atom, stratum c.relation < k → (c ∈ s₁ ↔ c ∈ s₂) := fun c hc => ih _ hc c rfl
        constructor
        · intro ha
          exact derivesUnder_mem_of_agree hvalid h₂.isModel k hlow (h₁.derivable a ha) (Nat.le_of_eq hk)
        · intro ha
          exact derivesUnder_mem_of_agree hvalid h₁.isModel k (fun c hc => (hlow c hc).symm) (h₂.derivable a ha)
            (Nat.le_of_eq hk)
  exact fun a => key _ a rfl

end Zil.Datalog
