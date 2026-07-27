module

public import Zil.Datalog.Semantics

@[expose] public section

namespace Zil.Datalog

/-- A finite interpretation of ground ZIL atoms. List representation preserves
snapshot order while membership supplies the declarative set view. -/
abbrev Interpretation := List Atom

def Interpretation.SatisfiesAtom (model : Interpretation) (atom : Atom) : Prop :=
  atom ∈ model

/-- Ordered solutions of a rule body. Positive literals extend substitutions;
negative literals require absence under the substitution accumulated so far. -/
def Rule.bodySolutions (model : Interpretation) (rule : Rule) : List Substitution :=
  satisfyNegativeBody model rule.negativePatterns
    (satisfyBody model rule.positiveBody)

/-- One declarative ground consequence of a rule in an interpretation. -/
def RuleConsequence (model : Interpretation) (rule : Rule) (atom : Atom) : Prop :=
  ∃ substitution, substitution ∈ rule.bodySolutions model ∧
    instantiate rule.head substitution = some atom

/-- Facts are included and every satisfied ground rule instance has its head in
the interpretation. Stratification is recorded separately so negation has a
well-founded relation order. -/
structure IsStratifiedModel (program : Program) (model : Interpretation) : Prop where
  stratified : program.isStratified = true
  facts : ∀ atom, atom ∈ program.facts → atom ∈ model
  closed : ∀ rule, rule ∈ program.rules → ∀ atom,
    RuleConsequence model rule atom → atom ∈ model

/-- The executable rule application and declarative ground-consequence view
coincide; this is the principal boundary between evaluation and model theory. -/
theorem ruleConsequence_iff_applyRule_mem {model : Interpretation} {rule : Rule}
    {atom : Atom} : RuleConsequence model rule atom ↔ atom ∈ applyRule model rule := by
  simp [RuleConsequence, Rule.bodySolutions, applyRule, List.mem_filterMap]

theorem deriveRuleSet_contains_input (rules : List Rule) (fuel : Nat)
    (facts : List Atom) {atom : Atom} (h : atom ∈ facts) :
    atom ∈ deriveRuleSet rules fuel facts := by
  induction fuel generalizing facts with
  | zero => simpa [deriveRuleSet] using h
  | succ fuel ih =>
      apply ih ((facts ++ rules.flatMap (applyRule facts)).eraseDups)
      simp [h]

theorem deriveStratified_contains_fact (program : Program) (fuel : Nat)
    {atom : Atom} (h : atom ∈ program.facts) : atom ∈ deriveStratified program fuel := by
  have foldContains : ∀ (levels : List Nat) (facts : List Atom), atom ∈ facts →
      atom ∈ levels.foldl (fun accumulated stratum =>
        let rules := program.rules.filter fun rule =>
          program.stratumOf rule.head.relation == stratum
        deriveRuleSet rules fuel accumulated) facts := by
    intro levels
    induction levels with
    | nil => intro facts factMem; exact factMem
    | cons stratum rest ih =>
        intro facts factMem
        simp only [List.foldl_cons]
        apply ih
        exact deriveRuleSet_contains_input _ _ _ factMem
  exact foldContains (List.range (program.maxStratum + 1)) program.facts h

/-- A one-step fixed point is declaratively closed under every program rule. -/
theorem closed_of_deriveStep_fixed {program : Program} {model : Interpretation}
    (hfixed : deriveStep program model = model) :
    ∀ rule, rule ∈ program.rules → ∀ atom,
      RuleConsequence model rule atom → atom ∈ model := by
  intro rule ruleMem atom consequence
  have applied : atom ∈ applyRule model rule :=
    ruleConsequence_iff_applyRule_mem.mp consequence
  have generated : atom ∈ program.rules.flatMap (applyRule model) := by
    rw [List.mem_flatMap]
    exact ⟨rule, ruleMem, applied⟩
  have stepped : atom ∈ deriveStep program model := by
    simp [deriveStep, generated]
  simpa [hfixed] using stepped

/-- Once bounded stratum evaluation is witnessed stable, its finite output is
a declarative stratified model. The stability premise is executable and can be
discharged with `native_decide` for frozen programs. -/
theorem deriveStratified_is_model_of_fixed (program : Program) (fuel : Nat)
    (hstratified : program.isStratified = true)
    (hfixed : deriveStep program (deriveStratified program fuel) =
      deriveStratified program fuel) :
    IsStratifiedModel program (deriveStratified program fuel) := {
  stratified := hstratified
  facts := fun _ h => deriveStratified_contains_fact program fuel h
  closed := closed_of_deriveStep_fixed hfixed
}

/-- Every operationally emitted atom both belongs to the finite interpretation
and retains its kernel-checked `Derives` explanation. -/
theorem deriveStratified_sound_in_interpretation (program : Program) (fuel : Nat)
    (atom : Atom) (h : atom ∈ deriveStratified program fuel) :
    Interpretation.SatisfiesAtom (deriveStratified program fuel) atom ∧
      Derives program atom :=
  ⟨h, deriveStratified_sound program fuel atom h⟩

end Zil.Datalog
