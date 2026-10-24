module

public import Zil.Datalog.Model

@[expose] public section

/-!
# Models, derivations and the least model

After Tantow, Gerlach, Mennicke and Krötzsch, "Verifying Datalog Reasoning with Lean" (ITP 2025, LIPIcs 36), section 2. A program
has two semantics, and they are the same set:

* **model-theoretic**: the facts that belong to every model (`IsModel`), where a model contains the facts and is closed under the
  rules;
* **proof-theoretic**: the facts with a finite derivation (`Derives`, `DerivesUnder`).

For a program without negation this file proves that a set which is a model and consists of derivable facts is the least model
(`leastModel_of_sound_model`), and that every derivable fact belongs to every model (`derives_mem_model`). This is the paper's Lemmas 1
and 2.

For a program with negation, a model-theoretic semantics has to say how a negative literal is read. `IsStableModel` reads it against the
set itself, as the stable-model semantics of Gelfond and Lifschitz does: `S` is stable when `S` is closed under the rules and every
fact of `S` has a finite derivation in which the negative literals are checked against `S`. A stratified program has exactly one stable
model; that is `stable_unique` in `Zil.Datalog.Stratified`.

The matching of patterns is the evaluator's own (`unify`, `instantiate`), so these theorems say what the evaluator's rules mean, not
that `unify` implements a particular notion of matching.
-/

namespace Zil.Datalog

/-! ## Bodies, matched step by step -/

/-- The positive patterns `ps` are matched against `facts` one after the other, extending the substitution `σ` to `σ'`. -/
inductive BodyMatches (facts : List Atom) : List Pattern → Substitution → Substitution → Prop where
  | nil {σ : Substitution} : BodyMatches facts [] σ σ
  | cons {p : Pattern} {ps : List Pattern} {σ σ' σ'' : Substitution} {a : Atom} :
      a ∈ facts → unify p a σ = some σ' → BodyMatches facts ps σ' σ'' → BodyMatches facts (p :: ps) σ σ''

theorem BodyMatches.mono {facts facts' : List Atom} (h : ∀ a, a ∈ facts → a ∈ facts') :
    ∀ {ps σ σ'}, BodyMatches facts ps σ σ' → BodyMatches facts' ps σ σ'
  | _, _, _, .nil => .nil
  | _, _, _, .cons ha hu rest => .cons (h _ ha) hu (rest.mono h)

theorem mem_matchPattern {facts : List Atom} {pattern : Pattern} {σ σ' : Substitution} :
    σ' ∈ matchPattern facts pattern σ ↔ ∃ a, a ∈ facts ∧ unify pattern a σ = some σ' := by
  simp [matchPattern, List.mem_filterMap]

theorem mem_foldl_matchPattern (facts : List Atom) :
    ∀ (body : List Pattern) (subs : List Substitution) (σ : Substitution),
      σ ∈ body.foldl (fun substitutions pattern => substitutions.flatMap (matchPattern facts pattern)) subs ↔
        ∃ σ0, σ0 ∈ subs ∧ BodyMatches facts body σ0 σ := by
  intro body
  induction body with
  | nil =>
      intro subs σ
      constructor
      · intro h
        exact ⟨σ, h, .nil⟩
      · rintro ⟨σ0, h0, hm⟩
        cases hm
        exact h0
  | cons p ps ih =>
      intro subs σ
      simp only [List.foldl_cons]
      rw [ih]
      constructor
      · rintro ⟨σ1, h1, hm⟩
        rw [List.mem_flatMap] at h1
        obtain ⟨σ0, h0, h1⟩ := h1
        obtain ⟨a, ha, hu⟩ := mem_matchPattern.mp h1
        exact ⟨σ0, h0, .cons ha hu hm⟩
      · rintro ⟨σ0, h0, hm⟩
        cases hm with
        | cons ha hu rest =>
            exact ⟨_, List.mem_flatMap.mpr ⟨σ0, h0, mem_matchPattern.mpr ⟨_, ha, hu⟩⟩, rest⟩

theorem mem_satisfyBody {facts : List Atom} {body : List Pattern} {σ : Substitution} :
    σ ∈ satisfyBody facts body ↔ BodyMatches facts body [] σ := by
  unfold satisfyBody
  rw [mem_foldl_matchPattern]
  constructor
  · rintro ⟨σ0, h0, hm⟩
    have : σ0 = [] := by simpa using h0
    subst this
    exact hm
  · intro hm
    exact ⟨[], by simp, hm⟩

/-! ## Negative literals, read against a reference set -/

/-- No atom of `reference` unifies with `pattern` under `σ`. -/
def Absent (reference : List Atom) (pattern : Pattern) (σ : Substitution) : Prop :=
  ∀ a, a ∈ reference → unify pattern a σ = none

theorem excludesPattern_iff {reference : List Atom} {pattern : Pattern} {σ : Substitution} :
    excludesPattern reference pattern σ = true ↔ Absent reference pattern σ := by
  unfold excludesPattern Absent
  simp only [Bool.not_eq_true', List.any_eq_false, Option.isSome_iff_ne_none, ne_eq, Decidable.not_not]

theorem mem_satisfyNegativeBody (reference : List Atom) :
    ∀ (negatives : List Pattern) (subs : List Substitution) (σ : Substitution),
      σ ∈ satisfyNegativeBody reference negatives subs ↔
        σ ∈ subs ∧ ∀ p, p ∈ negatives → Absent reference p σ := by
  intro negatives
  induction negatives with
  | nil => intro subs σ; simp [satisfyNegativeBody]
  | cons p ps ih =>
      intro subs σ
      have step : satisfyNegativeBody reference (p :: ps) subs =
          satisfyNegativeBody reference ps (subs.filter (excludesPattern reference p)) := rfl
      rw [step, ih, List.mem_filter, excludesPattern_iff]
      constructor
      · rintro ⟨⟨hs, hp⟩, hr⟩
        exact ⟨hs, fun q hq => by
          rcases List.mem_cons.mp hq with rfl | hq
          · exact hp
          · exact hr q hq⟩
      · rintro ⟨hs, hall⟩
        exact ⟨⟨hs, hall p (List.mem_cons_self ..)⟩, fun q hq => hall q (List.mem_cons_of_mem _ hq)⟩

/-! ## One rule, applied to `facts` with its negative literals read against `reference` -/

def applyRuleUnder (reference facts : List Atom) (rule : Rule) : List Atom :=
  (satisfyNegativeBody reference rule.negativePatterns (satisfyBody facts rule.positiveBody)).filterMap
    (instantiate rule.head)

theorem applyRule_eq_applyRuleUnder (facts : List Atom) (rule : Rule) :
    applyRule facts rule = applyRuleUnder facts facts rule := rfl

theorem mem_applyRuleUnder {reference facts : List Atom} {rule : Rule} {atom : Atom} :
    atom ∈ applyRuleUnder reference facts rule ↔
      ∃ σ, BodyMatches facts rule.positiveBody [] σ ∧ (∀ p, p ∈ rule.negativePatterns → Absent reference p σ) ∧
        instantiate rule.head σ = some atom := by
  unfold applyRuleUnder
  rw [List.mem_filterMap]
  constructor
  · rintro ⟨σ, hσ, hi⟩
    rw [mem_satisfyNegativeBody, mem_satisfyBody] at hσ
    exact ⟨σ, hσ.1, hσ.2, hi⟩
  · rintro ⟨σ, hm, hn, hi⟩
    exact ⟨σ, by rw [mem_satisfyNegativeBody, mem_satisfyBody]; exact ⟨hm, hn⟩, hi⟩

/-- A rule fires on more facts when it is given more facts; its negative literals stay read against the same reference. -/
theorem applyRuleUnder_mono {reference facts facts' : List Atom} (h : ∀ a, a ∈ facts → a ∈ facts') (rule : Rule)
    {atom : Atom} (hmem : atom ∈ applyRuleUnder reference facts rule) : atom ∈ applyRuleUnder reference facts' rule := by
  rw [mem_applyRuleUnder] at hmem ⊢
  obtain ⟨σ, hm, hn, hi⟩ := hmem
  exact ⟨σ, hm.mono h, hn, hi⟩

/-- A rule without negative literals does not look at the reference. -/
theorem applyRuleUnder_positive {reference reference' facts : List Atom} {rule : Rule}
    (hpos : rule.negativePatterns = []) {atom : Atom} (hmem : atom ∈ applyRuleUnder reference facts rule) :
    atom ∈ applyRuleUnder reference' facts rule := by
  rw [mem_applyRuleUnder] at hmem ⊢
  obtain ⟨σ, hm, _, hi⟩ := hmem
  exact ⟨σ, hm, by simp [hpos], hi⟩

/-! ## Models and derivations -/

/-- A model contains the facts of the program and is closed under its rules, negative literals being read against the model. -/
structure IsModel (program : Program) (model : Interpretation) : Prop where
  facts : ∀ atom, atom ∈ program.facts → atom ∈ model
  closed : ∀ rule, rule ∈ program.rules → ∀ atom, atom ∈ applyRule model rule → atom ∈ model

theorem IsStratifiedModel.isModel {program : Program} {model : Interpretation}
    (h : IsStratifiedModel program model) : IsModel program model where
  facts := h.facts
  closed rule hrule atom happ := h.closed rule hrule atom (ruleConsequence_iff_applyRule_mem.mpr happ)

/-- A finite derivation whose negative literals are read against `reference`. -/
inductive DerivesUnder (program : Program) (reference : Interpretation) : Atom → Prop where
  | fact {atom : Atom} : atom ∈ program.facts → DerivesUnder program reference atom
  | rule {atom : Atom} (rule : Rule) (support : List Atom) :
      rule ∈ program.rules → (∀ c, c ∈ support → DerivesUnder program reference c) →
      atom ∈ applyRuleUnder reference support rule → DerivesUnder program reference atom

/-- A program without negation. -/
def Program.IsPositive (program : Program) : Prop :=
  ∀ rule, rule ∈ program.rules → rule.negativePatterns = []

/-- For a program without negation the two readings of a derivation are the same. -/
theorem derives_iff_derivesUnder {program : Program} (hpos : program.IsPositive) (reference : Interpretation)
    (atom : Atom) : Derives program atom ↔ DerivesUnder program reference atom := by
  constructor
  · intro h
    induction h with
    | fact hf => exact .fact hf
    | rule r support hr _ happ ih =>
        exact .rule r support hr ih (applyRuleUnder_positive (hpos r hr) happ)
  · intro h
    induction h with
    | fact hf => exact .fact hf
    | rule r support hr _ happ ih =>
        exact .rule r support hr ih (applyRuleUnder_positive (hpos r hr) happ)

/-- Paper, Lemma 2: a derivable fact belongs to every model. -/
theorem derives_mem_model {program : Program} (hpos : program.IsPositive) {model : Interpretation}
    (hmodel : IsModel program model) {atom : Atom} (h : Derives program atom) : atom ∈ model := by
  induction h with
  | fact hf => exact hmodel.facts _ hf
  | rule r support hr _ happ ih =>
      have hmodelRef : _ ∈ applyRuleUnder model support r := applyRuleUnder_positive (hpos r hr) happ
      exact hmodel.closed r hr _ (applyRuleUnder_mono (fun c hc => ih c hc) r hmodelRef)

/-- Paper, Lemma 1 and the theorem that follows from the two: a set that is a model and consists of derivable facts is the
model-theoretic semantics (it is inside every model, and it is one), and is the proof-theoretic one. -/
theorem leastModel_of_sound_model {program : Program} (hpos : program.IsPositive) {model : Interpretation}
    (hmodel : IsModel program model) (hsound : ∀ atom, atom ∈ model → Derives program atom) :
    (∀ other, IsModel program other → ∀ atom, atom ∈ model → atom ∈ other) ∧
      ∀ atom, atom ∈ model ↔ Derives program atom :=
  ⟨fun _ hother atom hatom => derives_mem_model hpos hother (hsound atom hatom),
   fun atom => ⟨hsound atom, fun h => derives_mem_model hpos hmodel h⟩⟩

/-! ## Stable models, for programs with negation -/

/-- The set is a model and every fact of it has a finite derivation in which the negative literals are checked against the set. -/
structure IsStableModel (program : Program) (model : Interpretation) : Prop where
  isModel : IsModel program model
  derivable : ∀ atom, atom ∈ model → DerivesUnder program model atom

theorem isStableModel_iff {program : Program} {model : Interpretation} :
    IsStableModel program model ↔ IsModel program model ∧ ∀ atom, atom ∈ model ↔ DerivesUnder program model atom := by
  constructor
  · intro h
    refine ⟨h.isModel, fun atom => ⟨h.derivable atom, fun hd => ?_⟩⟩
    induction hd with
    | fact hf => exact h.isModel.facts _ hf
    | rule r support hr _ happ ih =>
        exact h.isModel.closed r hr _ (applyRuleUnder_mono (fun c hc => ih c hc) r happ)
  · rintro ⟨hm, hiff⟩
    exact ⟨hm, fun atom hatom => (hiff atom).mp hatom⟩

/-- For a program without negation, the stable model is the least model: the two notions of semantics agree. -/
theorem isStableModel_iff_sound {program : Program} (hpos : program.IsPositive) {model : Interpretation} :
    IsStableModel program model ↔ IsModel program model ∧ ∀ atom, atom ∈ model → Derives program atom := by
  constructor
  · intro h
    exact ⟨h.isModel, fun atom hatom => (derives_iff_derivesUnder hpos model atom).mpr (h.derivable atom hatom)⟩
  · rintro ⟨hm, hsound⟩
    exact ⟨hm, fun atom hatom => (derives_iff_derivesUnder hpos model atom).mp (hsound atom hatom)⟩

end Zil.Datalog
