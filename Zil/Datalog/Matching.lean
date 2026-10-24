module

public import Zil.Datalog.LeastModel

@[expose] public section

/-!
# `unify` against a declarative notion of matching

`unify` and `instantiate` decide what a rule means in the evaluator: they build a substitution one literal at a time. The paper (section
3.1) separates the two questions. A rule has a meaning that does not mention a procedure: take every **grounding**, a total assignment
of values to the variables, and a rule fires under a grounding when each positive literal, with the grounding applied, is satisfied by
a fact, and no negative literal is. This file defines that meaning and proves that the procedure computes it.

* `Matches g p a` is the declarative reading: the pattern `p`, with the grounding `g` applied, is satisfied by the atom `a`. The atom has
  the same relation, the same object and subject, and every attribute of the pattern is on the atom, with the value `g` gives.
* `unify_sound`: if `unify p a σ` succeeds with `σ'`, then `σ'` extends `σ`, and every grounding that agrees with `σ'` matches.
* `unify_complete`: if a grounding that agrees with `σ` matches, `unify p a σ` succeeds, and the result extends `σ` and still agrees with
  the grounding.
* `mem_applyRuleUnder_iff_ground`: for a safe rule, the atoms that `applyRuleUnder` produces are exactly the heads of the groundings under
  which the rule fires. So the models, derivations and stable models of `Zil.Datalog.LeastModel` mean what the declarative reading says,
  and nothing in them depends on how `unify` is written.

A rule is safe when its head and its negative literals use only variables that a positive literal binds (`Rule.isSafe`, which the
parser and the `zil_rule` command require).
-/

namespace Zil.Datalog

/-- A total assignment of values to variable names. -/
abbrev Grounding := String → Value

def Grounding.term (g : Grounding) : Term → Value
  | .value v => v
  | .variable x => g x

/-- The atom a pattern becomes under a grounding. -/
def Pattern.ground (g : Grounding) (p : Pattern) : Atom :=
  { object := g.term p.object, relation := p.relation, subject := g.term p.subject,
    attrs := p.attrs.map fun (k, t) => (k, g.term t) }

/-- The pattern, with the grounding applied, is satisfied by the atom: same relation, object and subject, and every attribute of the
pattern is on the atom with the value the grounding gives. -/
def Matches (g : Grounding) (p : Pattern) (a : Atom) : Prop :=
  a.relation = p.relation ∧ a.object = g.term p.object ∧ a.subject = g.term p.subject ∧
    ∀ k t, (k, t) ∈ p.attrs → a.attrs.lookup k = some (g.term t)

/-! ## Substitutions and groundings -/

theorem lookup_cons (x y : String) (v : Value) (σ : Substitution) :
    ((x, v) :: σ).lookup y = if (y == x) = true then some v else σ.lookup y := by
  simp [List.lookup]
  split <;> simp_all

/-- `σ'` keeps every binding of `σ`. -/
def Ext (σ σ' : Substitution) : Prop := ∀ x v, σ.lookup x = some v → σ'.lookup x = some v

/-- The grounding gives every bound variable its value. -/
def Compat (g : Grounding) (σ : Substitution) : Prop := ∀ x v, σ.lookup x = some v → g x = v

theorem Ext.refl (σ : Substitution) : Ext σ σ := fun _ _ h => h

theorem Ext.trans {σ₁ σ₂ σ₃ : Substitution} (h₁ : Ext σ₁ σ₂) (h₂ : Ext σ₂ σ₃) : Ext σ₁ σ₃ :=
  fun x v h => h₂ x v (h₁ x v h)

theorem Compat.mono {g : Grounding} {σ σ' : Substitution} (hext : Ext σ σ') (h : Compat g σ') : Compat g σ :=
  fun x v hx => h x v (hext x v hx)

theorem Compat.empty (g : Grounding) : Compat g [] := by
  intro x v h
  simp [List.lookup] at h

/-! ### One variable -/

theorem bind_sound {x : String} {v : Value} {σ σ' : Substitution} (h : bind x v σ = some σ') :
    Ext σ σ' ∧ σ'.lookup x = some v := by
  unfold bind lookup at h
  cases hl : σ.lookup x with
  | none =>
      simp only [hl] at h
      have hσ : σ' = (x, v) :: σ := (Option.some.inj h).symm
      subst hσ
      refine ⟨?_, by simp⟩
      intro y w hy
      rw [lookup_cons]
      by_cases hyx : (y == x) = true
      · have : y = x := by simpa using hyx
        subst this
        rw [hl] at hy
        cases hy
      · simp [hyx, hy]
  | some existing =>
      simp only [hl] at h
      by_cases heq : (existing == v) = true
      · simp only [heq, if_true] at h
        have hσ : σ' = σ := (Option.some.inj h).symm
        subst hσ
        have : existing = v := by simpa using heq
        subst this
        exact ⟨Ext.refl _, hl⟩
      · simp [heq] at h

theorem bind_complete {g : Grounding} {σ : Substitution} (hg : Compat g σ) (x : String) (v : Value) (hx : g x = v) :
    ∃ σ', bind x v σ = some σ' ∧ Ext σ σ' ∧ Compat g σ' := by
  unfold bind lookup
  cases hl : σ.lookup x with
  | none =>
      refine ⟨(x, v) :: σ, rfl, ?_, ?_⟩
      · intro y w hy
        rw [lookup_cons]
        by_cases hyx : (y == x) = true
        · have : y = x := by simpa using hyx
          subst this
          rw [hl] at hy
          cases hy
        · simp [hyx, hy]
      · intro y w hy
        rw [lookup_cons] at hy
        by_cases hyx : (y == x) = true
        · have : y = x := by simpa using hyx
          subst this
          simp only [hyx, if_true] at hy
          have : v = w := Option.some.inj hy
          rw [← this]; exact hx
        · simp only [hyx] at hy
          exact hg y w hy
  | some existing =>
      have hge : g x = existing := hg x existing hl
      have : existing = v := by rw [← hge, hx]
      subst this
      exact ⟨σ, by simp, Ext.refl _, hg⟩

/-! ### One term -/

theorem unifyTerm_sound {t : Term} {v : Value} {σ σ' : Substitution} (h : unifyTerm t v σ = some σ') :
    Ext σ σ' ∧ ∀ g, Compat g σ' → g.term t = v := by
  rcases t with name | expected
  · simp only [unifyTerm] at h
    obtain ⟨hext, hlook⟩ := bind_sound h
    exact ⟨hext, fun g hg => hg name v hlook⟩
  · simp only [unifyTerm] at h
    by_cases heq : (expected == v) = true
    · simp only [heq, if_true] at h
      have hσ : σ' = σ := (Option.some.inj h).symm
      subst hσ
      have : expected = v := by simpa using heq
      subst this
      exact ⟨Ext.refl _, fun _ _ => rfl⟩
    · simp [heq] at h

theorem unifyTerm_complete {g : Grounding} {σ : Substitution} (hg : Compat g σ) (t : Term) (v : Value) (ht : g.term t = v) :
    ∃ σ', unifyTerm t v σ = some σ' ∧ Ext σ σ' ∧ Compat g σ' := by
  rcases t with name | expected
  · obtain ⟨σ', hb, hext, hc⟩ := bind_complete hg name v ht
    exact ⟨σ', by simp [unifyTerm, hb], hext, hc⟩
  · have : expected = v := ht
    subst this
    exact ⟨σ, by simp [unifyTerm], Ext.refl _, hg⟩

/-! ### The attributes of a pattern -/

theorem unifyAttrs_sound :
    ∀ (pas : PatternAttrs) (attrs : AtomAttrs) (σ σ' : Substitution), unifyAttrs pas attrs σ = some σ' →
      Ext σ σ' ∧ ∀ g, Compat g σ' → ∀ k t, (k, t) ∈ pas → attrs.lookup k = some (g.term t) := by
  intro pas
  induction pas with
  | nil =>
      intro attrs σ σ' h
      simp only [unifyAttrs] at h
      have hσ : σ = σ' := Option.some.inj h
      subst hσ
      exact ⟨Ext.refl _, fun _ _ k t hkt => by simp at hkt⟩
  | cons entry rest ih =>
      obtain ⟨key, term⟩ := entry
      intro attrs σ σ' h
      simp only [unifyAttrs] at h
      cases hv : attrs.lookup key with
      | none => simp [hv] at h
      | some value =>
          simp only [hv, Option.bind_eq_bind, Option.bind_some] at h
          cases hu : unifyTerm term value σ with
          | none => simp [hu] at h
          | some σ1 =>
              simp only [hu, Option.bind_some] at h
              obtain ⟨hext1, hterm⟩ := unifyTerm_sound hu
              obtain ⟨hext2, hrest⟩ := ih attrs σ1 σ' h
              refine ⟨hext1.trans hext2, fun g hg k t hkt => ?_⟩
              rcases List.mem_cons.mp hkt with heq | hmem
              · obtain ⟨rfl, rfl⟩ := Prod.mk.inj heq
                rw [hv, hterm g (hg.mono hext2)]
              · exact hrest g hg k t hmem

theorem unifyAttrs_complete {g : Grounding} :
    ∀ (pas : PatternAttrs) (attrs : AtomAttrs) (σ : Substitution), Compat g σ →
      (∀ k t, (k, t) ∈ pas → attrs.lookup k = some (g.term t)) →
      ∃ σ', unifyAttrs pas attrs σ = some σ' ∧ Ext σ σ' ∧ Compat g σ' := by
  intro pas
  induction pas with
  | nil => intro attrs σ hg _; exact ⟨σ, by simp [unifyAttrs], Ext.refl _, hg⟩
  | cons entry rest ih =>
      obtain ⟨key, term⟩ := entry
      intro attrs σ hg hmatch
      have hlook := hmatch key term (List.mem_cons_self ..)
      obtain ⟨σ1, hu, hext1, hc1⟩ := unifyTerm_complete hg term (g.term term) rfl
      obtain ⟨σ2, hrest, hext2, hc2⟩ := ih attrs σ1 hc1 (fun k t hkt => hmatch k t (List.mem_cons_of_mem _ hkt))
      -- `hu` unified against `g.term term`, which is what the atom has for `key`
      refine ⟨σ2, ?_, hext1.trans hext2, hc2⟩
      simp only [unifyAttrs, hlook, Option.bind_eq_bind, Option.bind_some]
      rw [hu]
      simpa using hrest

/-! ### A pattern and an atom -/

theorem unify_sound {p : Pattern} {a : Atom} {σ σ' : Substitution} (h : unify p a σ = some σ') :
    Ext σ σ' ∧ ∀ g, Compat g σ' → Matches g p a := by
  unfold unify at h
  by_cases hrel : (p.relation != a.relation) = true
  · simp [hrel] at h
  · simp only [Bool.not_eq_true, bne_eq_false_iff_eq] at hrel
    simp only [hrel, bne_self_eq_false, Bool.false_eq_true, if_false] at h
    cases ho : unifyTerm p.object a.object σ with
    | none => simp [ho] at h
    | some σ1 =>
        simp only [ho, Option.bind_eq_bind, Option.bind_some] at h
        cases hs : unifyTerm p.subject a.subject σ1 with
        | none => simp [hs] at h
        | some σ2 =>
            simp only [hs, Option.bind_some] at h
            obtain ⟨hext1, hobj⟩ := unifyTerm_sound ho
            obtain ⟨hext2, hsub⟩ := unifyTerm_sound hs
            obtain ⟨hext3, hattrs⟩ := unifyAttrs_sound _ _ _ _ h
            refine ⟨hext1.trans (hext2.trans hext3), fun g hg => ?_⟩
            have hg2 : Compat g σ2 := hg.mono hext3
            have hg1 : Compat g σ1 := hg2.mono hext2
            exact ⟨hrel.symm, (hobj g hg1).symm, (hsub g hg2).symm, hattrs g hg⟩

theorem unify_complete {g : Grounding} {σ : Substitution} (hg : Compat g σ) {p : Pattern} {a : Atom} (hm : Matches g p a) :
    ∃ σ', unify p a σ = some σ' ∧ Ext σ σ' ∧ Compat g σ' := by
  obtain ⟨hrel, hobj, hsub, hattrs⟩ := hm
  obtain ⟨σ1, ho, hext1, hc1⟩ := unifyTerm_complete hg p.object a.object hobj.symm
  obtain ⟨σ2, hs, hext2, hc2⟩ := unifyTerm_complete hc1 p.subject a.subject hsub.symm
  obtain ⟨σ3, hat, hext3, hc3⟩ := unifyAttrs_complete p.attrs a.attrs σ2 hc2 hattrs
  refine ⟨σ3, ?_, hext1.trans (hext2.trans hext3), hc3⟩
  unfold unify
  have : (p.relation != a.relation) = false := by simp [hrel]
  simp [this, ho, hs, hat]

/-! ## Which variables a successful `unify` binds -/

theorem unifyTerm_binds {t : Term} {v : Value} {σ σ' : Substitution} (h : unifyTerm t v σ = some σ') :
    ∀ x, x ∈ t.variables → ∃ w, σ'.lookup x = some w := by
  rcases t with name | expected
  · simp only [unifyTerm] at h
    obtain ⟨_, hlook⟩ := bind_sound h
    intro x hx
    simp only [Term.variables, List.mem_singleton] at hx
    subst hx
    exact ⟨v, hlook⟩
  · intro x hx; simp [Term.variables] at hx

theorem unifyAttrs_binds :
    ∀ (pas : PatternAttrs) (attrs : AtomAttrs) (σ σ' : Substitution), unifyAttrs pas attrs σ = some σ' →
      ∀ k t, (k, t) ∈ pas → ∀ x, x ∈ t.variables → ∃ w, σ'.lookup x = some w := by
  intro pas
  induction pas with
  | nil => intro attrs σ σ' h k t hkt; simp at hkt
  | cons entry rest ih =>
      obtain ⟨key, term⟩ := entry
      intro attrs σ σ' h k t hkt x hx
      simp only [unifyAttrs] at h
      cases hv : attrs.lookup key with
      | none => simp [hv] at h
      | some value =>
          simp only [hv, Option.bind_eq_bind, Option.bind_some] at h
          cases hu : unifyTerm term value σ with
          | none => simp [hu] at h
          | some σ1 =>
              simp only [hu, Option.bind_some] at h
              obtain ⟨hext, _⟩ := unifyAttrs_sound _ _ _ _ h
              rcases List.mem_cons.mp hkt with heq | hmem
              · obtain ⟨rfl, rfl⟩ := Prod.mk.inj heq
                obtain ⟨w, hw⟩ := unifyTerm_binds hu x hx
                exact ⟨w, hext x w hw⟩
              · exact ih attrs σ1 σ' h k t hmem x hx

theorem mem_variables {p : Pattern} {x : String} :
    x ∈ p.variables ↔ x ∈ p.object.variables ∨ x ∈ p.subject.variables ∨ ∃ k t, (k, t) ∈ p.attrs ∧ x ∈ t.variables := by
  unfold Pattern.variables
  simp only [List.mem_eraseDups, List.mem_append, List.mem_flatMap]
  constructor
  · rintro ((ho | hs) | ⟨⟨k, t⟩, hkt, hx⟩)
    · exact Or.inl ho
    · exact Or.inr (Or.inl hs)
    · exact Or.inr (Or.inr ⟨k, t, hkt, hx⟩)
  · rintro (ho | hs | ⟨k, t, hkt, hx⟩)
    · exact Or.inl (Or.inl ho)
    · exact Or.inl (Or.inr hs)
    · exact Or.inr ⟨(k, t), hkt, hx⟩

theorem unify_binds {p : Pattern} {a : Atom} {σ σ' : Substitution} (h : unify p a σ = some σ') :
    ∀ x, x ∈ p.variables → ∃ w, σ'.lookup x = some w := by
  unfold unify at h
  by_cases hrel : (p.relation != a.relation) = true
  · simp [hrel] at h
  · simp only [Bool.not_eq_true, bne_eq_false_iff_eq] at hrel
    simp only [hrel, bne_self_eq_false, Bool.false_eq_true, if_false] at h
    cases ho : unifyTerm p.object a.object σ with
    | none => simp [ho] at h
    | some σ1 =>
        simp only [ho, Option.bind_eq_bind, Option.bind_some] at h
        cases hs : unifyTerm p.subject a.subject σ1 with
        | none => simp [hs] at h
        | some σ2 =>
            simp only [hs, Option.bind_some] at h
            obtain ⟨hext1, _⟩ := unifyTerm_sound ho
            obtain ⟨hext2, _⟩ := unifyTerm_sound hs
            obtain ⟨hext3, _⟩ := unifyAttrs_sound _ _ _ _ h
            intro x hx
            rcases mem_variables.mp hx with hxo | hxs | ⟨k, t, hkt, hxt⟩
            · obtain ⟨w, hw⟩ := unifyTerm_binds ho x hxo
              exact ⟨w, hext3 x w (hext2 x w hw)⟩
            · obtain ⟨w, hw⟩ := unifyTerm_binds hs x hxs
              exact ⟨w, hext3 x w hw⟩
            · exact unifyAttrs_binds _ _ _ _ h k t hkt x hxt

/-! ## A body, matched step by step, against groundings -/

theorem bodyMatches_sound {facts : List Atom} {ps : List Pattern} {σ σ' : Substitution} (h : BodyMatches facts ps σ σ') :
    Ext σ σ' ∧ (∀ g, Compat g σ' → ∀ p, p ∈ ps → ∃ b, b ∈ facts ∧ Matches g p b) ∧
      ∀ p, p ∈ ps → ∀ x, x ∈ p.variables → ∃ w, σ'.lookup x = some w := by
  induction h with
  | nil => exact ⟨Ext.refl _, fun _ _ p hp => by simp at hp, fun p hp => by simp at hp⟩
  | @cons p ps σ σ1 σ2 a ha hu rest ih =>
      obtain ⟨hext1, hmatch1⟩ := unify_sound hu
      obtain ⟨hext2, hmatch2, hbind2⟩ := ih
      refine ⟨hext1.trans hext2, fun g hg q hq => ?_, fun q hq x hx => ?_⟩
      · rcases List.mem_cons.mp hq with rfl | hmem
        · exact ⟨a, ha, hmatch1 g (hg.mono hext2)⟩
        · exact hmatch2 g hg q hmem
      · rcases List.mem_cons.mp hq with rfl | hmem
        · obtain ⟨w, hw⟩ := unify_binds hu x hx
          exact ⟨w, hext2 x w hw⟩
        · exact hbind2 q hmem x hx

theorem bodyMatches_complete {g : Grounding} {facts : List Atom} :
    ∀ (ps : List Pattern) (σ : Substitution), Compat g σ → (∀ p, p ∈ ps → ∃ b, b ∈ facts ∧ Matches g p b) →
      ∃ σ', BodyMatches facts ps σ σ' ∧ Ext σ σ' ∧ Compat g σ' := by
  intro ps
  induction ps with
  | nil => intro σ hg _; exact ⟨σ, .nil, Ext.refl _, hg⟩
  | cons p ps ih =>
      intro σ hg hm
      obtain ⟨b, hb, hmatch⟩ := hm p (List.mem_cons_self ..)
      obtain ⟨σ1, hu, hext1, hc1⟩ := unify_complete hg hmatch
      obtain ⟨σ2, hbody, hext2, hc2⟩ := ih σ1 hc1 (fun q hq => hm q (List.mem_cons_of_mem _ hq))
      exact ⟨σ2, .cons hb hu hbody, hext1.trans hext2, hc2⟩

/-! ## Instantiating a pattern -/

theorem instantiateTerm_ground {g : Grounding} {σ : Substitution} (hg : Compat g σ) {t : Term} {v : Value}
    (h : instantiateTerm σ t = some v) : g.term t = v := by
  rcases t with name | value
  · simp only [instantiateTerm, lookup] at h
    exact hg name v h
  · simp only [instantiateTerm] at h
    exact Option.some.inj h

theorem instantiateTerm_of_bound {g : Grounding} {σ : Substitution} (hg : Compat g σ) {t : Term}
    (hb : ∀ x, x ∈ t.variables → ∃ w, σ.lookup x = some w) : instantiateTerm σ t = some (g.term t) := by
  rcases t with name | value
  · obtain ⟨w, hw⟩ := hb name (by simp [Term.variables])
    have : g name = w := hg name w hw
    simp [instantiateTerm, lookup, hw, Grounding.term, this]
  · simp [instantiateTerm, Grounding.term]

theorem instantiateAttrs_ground {g : Grounding} {σ : Substitution} (hg : Compat g σ) :
    ∀ {pas : PatternAttrs} {attrs : AtomAttrs}, instantiateAttrs σ pas = some attrs →
      attrs = pas.map fun (k, t) => (k, g.term t) := by
  intro pas
  induction pas with
  | nil => intro attrs h; simp [instantiateAttrs] at h; subst h; rfl
  | cons entry rest ih =>
      obtain ⟨key, term⟩ := entry
      intro attrs h
      simp only [instantiateAttrs, Option.bind_eq_bind] at h
      cases hv : instantiateTerm σ term with
      | none => simp [hv] at h
      | some value =>
          cases hr : instantiateAttrs σ rest with
          | none => simp [hv, hr] at h
          | some values =>
              simp only [hv, hr, Option.bind_some, Option.pure_def] at h
              have : attrs = (key, value) :: values := (Option.some.inj h).symm
              subst this
              simp only [List.map_cons]
              rw [instantiateTerm_ground hg hv, ih hr]

theorem instantiateAttrs_of_bound {g : Grounding} {σ : Substitution} (hg : Compat g σ) :
    ∀ (pas : PatternAttrs), (∀ k t, (k, t) ∈ pas → ∀ x, x ∈ t.variables → ∃ w, σ.lookup x = some w) →
      instantiateAttrs σ pas = some (pas.map fun (k, t) => (k, g.term t)) := by
  intro pas
  induction pas with
  | nil => intro _; rfl
  | cons entry rest ih =>
      obtain ⟨key, term⟩ := entry
      intro hb
      have ht := instantiateTerm_of_bound hg (hb key term (List.mem_cons_self ..))
      have hr := ih (fun k t hkt => hb k t (List.mem_cons_of_mem _ hkt))
      simp [instantiateAttrs, ht, hr]

theorem instantiate_ground {g : Grounding} {σ : Substitution} (hg : Compat g σ) {p : Pattern} {a : Atom}
    (h : instantiate p σ = some a) : p.ground g = a := by
  unfold instantiate at h
  cases ho : instantiateTerm σ p.object with
  | none => simp [ho] at h
  | some object =>
      cases hs : instantiateTerm σ p.subject with
      | none => simp [ho, hs] at h
      | some subject =>
          cases ha : instantiateAttrs σ p.attrs with
          | none => simp [ho, hs, ha] at h
          | some attrs =>
              simp only [ho, hs, ha, Option.bind_eq_bind, Option.bind_some, Option.pure_def] at h
              have := (Option.some.inj h).symm
              subst this
              simp [Pattern.ground, instantiateTerm_ground hg ho, instantiateTerm_ground hg hs, instantiateAttrs_ground hg ha]

theorem instantiate_of_bound {g : Grounding} {σ : Substitution} (hg : Compat g σ) {p : Pattern}
    (hb : ∀ x, x ∈ p.variables → ∃ w, σ.lookup x = some w) : instantiate p σ = some (p.ground g) := by
  unfold instantiate
  have ho := instantiateTerm_of_bound hg (t := p.object) (fun x hx => hb x (mem_variables.mpr (Or.inl hx)))
  have hs := instantiateTerm_of_bound hg (t := p.subject) (fun x hx => hb x (mem_variables.mpr (Or.inr (Or.inl hx))))
  have ha := instantiateAttrs_of_bound hg p.attrs
    (fun k t hkt x hx => hb x (mem_variables.mpr (Or.inr (Or.inr ⟨k, t, hkt, hx⟩))))
  simp [ho, hs, ha, Pattern.ground]

/-! ## A rule, read declaratively -/

/-- `Matches` depends on a grounding only through the variables of the pattern. -/
theorem term_congr {g g' : Grounding} {t : Term} (h : ∀ x, x ∈ t.variables → g x = g' x) : g.term t = g'.term t := by
  rcases t with name | value
  · exact h name (by simp [Term.variables])
  · rfl

theorem matches_congr {g g' : Grounding} {p : Pattern} {a : Atom} (h : ∀ x, x ∈ p.variables → g x = g' x)
    (hm : Matches g' p a) : Matches g p a := by
  obtain ⟨hrel, hobj, hsub, hattrs⟩ := hm
  have ho : g.term p.object = g'.term p.object := term_congr fun x hx => h x (mem_variables.mpr (Or.inl hx))
  have hs : g.term p.subject = g'.term p.subject :=
    term_congr fun x hx => h x (mem_variables.mpr (Or.inr (Or.inl hx)))
  refine ⟨hrel, by rw [ho]; exact hobj, by rw [hs]; exact hsub, fun k t hkt => ?_⟩
  have ht : g.term t = g'.term t := term_congr fun x hx => h x (mem_variables.mpr (Or.inr (Or.inr ⟨k, t, hkt, hx⟩)))
  rw [ht]
  exact hattrs k t hkt

/-- The grounding makes the rule fire: each positive literal is satisfied by a fact, and no negative literal is satisfied by an atom
of the reference set. -/
def RuleFires (reference facts : List Atom) (rule : Rule) (g : Grounding) : Prop :=
  (∀ p, p ∈ rule.positiveBody → ∃ b, b ∈ facts ∧ Matches g p b) ∧
    ∀ n, n ∈ rule.negativePatterns → ∀ b, b ∈ reference → ¬ Matches g n b

/-- What a safe rule's variable lists say: the head and the negative literals use only variables that a positive literal has. -/
theorem Rule.safe_spec {rule : Rule} (h : rule.isSafe = true) :
    (∀ x, x ∈ rule.head.variables → ∃ p, p ∈ rule.positiveBody ∧ x ∈ p.variables) ∧
    ∀ n, n ∈ rule.negativePatterns → ∀ x, x ∈ n.variables → ∃ p, p ∈ rule.positiveBody ∧ x ∈ p.variables := by
  unfold Rule.isSafe Rule.unboundHeadVariables Rule.unboundNegativeVariables at h
  simp only [Bool.and_eq_true, List.isEmpty_iff, List.filter_eq_nil_iff, Bool.not_eq_true'] at h
  obtain ⟨hhead, hneg⟩ := h
  constructor
  · intro x hx
    have := hhead x hx
    simpa [List.contains_eq_mem, List.mem_eraseDups, List.mem_flatMap] using this
  · intro n hn x hx
    have hmem : x ∈ (rule.negativePatterns.flatMap Pattern.variables).eraseDups := by
      simp only [List.mem_eraseDups, List.mem_flatMap]
      exact ⟨n, hn, hx⟩
    have := hneg x hmem
    simpa [List.contains_eq_mem, List.mem_eraseDups, List.mem_flatMap] using this

/-- **`unify` computes the declarative reading.** For a safe rule, the atoms that `applyRuleUnder` produces are exactly the heads of
the groundings under which the rule fires. -/
theorem mem_applyRuleUnder_iff_ground {reference facts : List Atom} {rule : Rule} (hsafe : rule.isSafe = true) {atom : Atom} :
    atom ∈ applyRuleUnder reference facts rule ↔ ∃ g, RuleFires reference facts rule g ∧ rule.head.ground g = atom := by
  obtain ⟨hheadSafe, hnegSafe⟩ := Rule.safe_spec hsafe
  rw [mem_applyRuleUnder]
  constructor
  · rintro ⟨σ, hbody, habsent, hinst⟩
    let g : Grounding := fun x => (σ.lookup x).getD default
    have hg : Compat g σ := by
      intro x v hx
      simp [g, hx]
    obtain ⟨_, hpos, _⟩ := bodyMatches_sound hbody
    refine ⟨g, ⟨hpos g hg, fun n hn b hb hmatch => ?_⟩, instantiate_ground hg hinst⟩
    obtain ⟨σ', hu, _⟩ := unify_complete hg hmatch
    have := habsent n hn b hb
    rw [hu] at this
    cases this
  · rintro ⟨g, ⟨hpos, hneg⟩, hground⟩
    obtain ⟨σ, hbody, _, hg⟩ := bodyMatches_complete (facts := facts) rule.positiveBody [] (Compat.empty g) hpos
    obtain ⟨_, _, hbound⟩ := bodyMatches_sound hbody
    have hboundOf : ∀ p : Pattern, (∀ x, x ∈ p.variables → ∃ q, q ∈ rule.positiveBody ∧ x ∈ q.variables) →
        ∀ x, x ∈ p.variables → ∃ w, σ.lookup x = some w := by
      intro p hp x hx
      obtain ⟨q, hq, hxq⟩ := hp x hx
      exact hbound q hq x hxq
    refine ⟨σ, hbody, fun n hn b hb => ?_, ?_⟩
    · -- no atom of the reference unifies with the negative literal under `σ`
      cases hu : unify n b σ with
      | none => rfl
      | some σ'' =>
          exfalso
          obtain ⟨hext, hmatch⟩ := unify_sound hu
          let g' : Grounding := fun x => (σ''.lookup x).getD (g x)
          have hg' : Compat g' σ'' := by
            intro x v hx
            simp [g', hx]
          have hbn := hboundOf n (hnegSafe n hn)
          have hagree : ∀ x, x ∈ n.variables → g x = g' x := by
            intro x hx
            obtain ⟨w, hw⟩ := hbn x hx
            have h1 : g x = w := hg x w hw
            have h2 : σ''.lookup x = some w := hext x w hw
            simp [g', h2, h1]
          exact hneg n hn b hb (matches_congr (fun x hx => hagree x hx) (hmatch g' hg'))
    · have hbh := hboundOf rule.head hheadSafe
      rw [instantiate_of_bound hg hbh, hground]

/-! ## Models, derivations and stable models, read declaratively -/

/-- Every rule of the program is safe. -/
def Program.IsSafe (program : Program) : Prop := ∀ rule, rule ∈ program.rules → rule.isSafe = true

/-- Every rule of the program is safe, as a check. -/
def Program.safe (program : Program) : Bool := program.rules.all (·.isSafe)

theorem Program.safe_isSafe {program : Program} (h : program.safe = true) : program.IsSafe :=
  fun rule hrule => List.all_eq_true.mp h rule hrule

/-- The paper's model: the facts are in the set, and for every grounding under which a rule fires on the set, its head is in the set. -/
structure IsModelGround (program : Program) (model : Interpretation) : Prop where
  facts : ∀ atom, atom ∈ program.facts → atom ∈ model
  closed : ∀ rule, rule ∈ program.rules → ∀ g, RuleFires model model rule g → rule.head.ground g ∈ model

theorem isModel_iff_ground {program : Program} (hsafe : program.IsSafe) {model : Interpretation} :
    IsModel program model ↔ IsModelGround program model := by
  constructor
  · intro h
    refine ⟨h.facts, fun rule hrule g hfires => h.closed rule hrule _ ?_⟩
    exact (mem_applyRuleUnder_iff_ground (hsafe rule hrule)).mpr ⟨g, hfires, rfl⟩
  · intro h
    refine ⟨h.facts, fun rule hrule atom hmem => ?_⟩
    obtain ⟨g, hfires, hg⟩ := (mem_applyRuleUnder_iff_ground (hsafe rule hrule)).mp hmem
    rw [← hg]
    exact h.closed rule hrule g hfires

/-- A finite derivation, with the rules read as groundings, and the negative literals read against `reference`. -/
inductive DerivesGround (program : Program) (reference : Interpretation) : Atom → Prop where
  | fact {atom : Atom} : atom ∈ program.facts → DerivesGround program reference atom
  | rule (rule : Rule) (support : List Atom) (g : Grounding) :
      rule ∈ program.rules → (∀ c, c ∈ support → DerivesGround program reference c) →
      RuleFires reference support rule g → DerivesGround program reference (rule.head.ground g)

theorem derivesUnder_iff_ground {program : Program} (hsafe : program.IsSafe) {reference : Interpretation} {atom : Atom} :
    DerivesUnder program reference atom ↔ DerivesGround program reference atom := by
  constructor
  · intro h
    induction h with
    | fact hf => exact .fact hf
    | rule r support hr _ happ ih =>
        obtain ⟨g, hfires, hg⟩ := (mem_applyRuleUnder_iff_ground (hsafe r hr)).mp happ
        rw [← hg]
        exact .rule r support g hr ih hfires
  · intro h
    induction h with
    | fact hf => exact .fact hf
    | rule r support g hr _ hfires ih =>
        exact .rule r support hr ih ((mem_applyRuleUnder_iff_ground (hsafe r hr)).mpr ⟨g, hfires, rfl⟩)

/-- **Stable models, without `unify`.** For a safe program, being a stable model is the same as the paper's reading: a model in which every
atom has a derivation whose rule steps are groundings. -/
theorem isStableModel_iff_ground {program : Program} (hsafe : program.IsSafe) {model : Interpretation} :
    IsStableModel program model ↔
      IsModelGround program model ∧ ∀ atom, atom ∈ model → DerivesGround program model atom := by
  constructor
  · intro h
    exact ⟨(isModel_iff_ground hsafe).mp h.isModel, fun a ha => (derivesUnder_iff_ground hsafe).mp (h.derivable a ha)⟩
  · rintro ⟨hm, hd⟩
    exact ⟨(isModel_iff_ground hsafe).mpr hm, fun a ha => (derivesUnder_iff_ground hsafe).mpr (hd a ha)⟩

end Zil.Datalog
