module

public import Zil.Horn.Certificate

@[expose] public section

namespace Zil.Horn

/-- Assemble a proof forest when every instantiated atom in a finite clause
body has a valid proof tree. -/
theorem validDerivations_of_eachInstance
    {program : Program} {body : List Atom} {substitution : Substitution}
    (available : ∀ goal, goal ∈ body →
      ∃ derivation, ValidDerivation program
        (goal.substitute substitution) derivation) :
    ∃ derivations, ValidDerivations program
      (body.map (Atom.substitute substitution)) derivations := by
  induction body with
  | nil => exact ⟨[], .nil⟩
  | cons bodyGoal bodyGoals induction =>
      obtain ⟨headDerivation, headValid⟩ := available bodyGoal (by simp)
      obtain ⟨tailDerivations, tailValid⟩ := induction
        (fun requested requestedMember =>
          available requested (by simp [requestedMember]))
      exact ⟨headDerivation :: tailDerivations,
        .cons _ _ _ _ headValid tailValid⟩

/-- Declarative completeness of proof-tree certificates: every finite
`Entails` proof has a corresponding valid `Derivation`. -/
theorem Entails.hasDerivation
    {program : Program} {goal : Atom} (entails : Entails program goal) :
    ∃ derivation, ValidDerivation program goal derivation := by
  induction entails with
  | clause source member substitution premises hypotheses =>
      obtain ⟨derivations, valid⟩ := validDerivations_of_eachInstance hypotheses
      exact ⟨.clause source substitution derivations,
        .clause _ source substitution derivations member rfl valid⟩

/-- Pointwise strengthening of a proof-forest checker preserves acceptance. -/
theorem checkDerivations_mono
    {left right : Atom → Derivation → Bool}
    (pointwise : ∀ goal derivation,
      left goal derivation = true → right goal derivation = true) :
    ∀ goals derivations,
      checkDerivations left goals derivations = true →
      checkDerivations right goals derivations = true := by
  intro goals derivations checked
  induction goals generalizing derivations with
  | nil =>
      cases derivations <;> simp_all [checkDerivations]
  | cons goal goals induction =>
      cases derivations with
      | nil => simp [checkDerivations] at checked
      | cons derivation derivations =>
          simp only [checkDerivations, Bool.and_eq_true] at checked ⊢
          exact ⟨pointwise goal derivation checked.1,
            induction derivations checked.2⟩

/-- Adding replay fuel cannot invalidate an accepted certificate. -/
theorem checkDerivation_mono
    {small large : Nat} (bound : small ≤ large)
    (checked : checkDerivation small program goal derivation = true) :
    checkDerivation large program goal derivation = true := by
  induction small generalizing large goal derivation with
  | zero => simp [checkDerivation] at checked
  | succ small induction =>
      cases large with
      | zero => simp at bound
      | succ large =>
          cases derivation with
          | clause source substitution premises =>
              have lower : small ≤ large := Nat.le_of_succ_le_succ bound
              simp only [checkDerivation, Bool.and_eq_true] at checked ⊢
              constructor
              · exact checked.1
              · exact checkDerivations_mono
                  (fun premise child accepted => induction lower accepted)
                  _ _ checked.2

mutual
  /-- Replay completeness for one valid proof tree. -/
  theorem ValidDerivation.check_complete
      (valid : ValidDerivation program goal derivation) :
      ∃ fuel, checkDerivation fuel program goal derivation = true := by
    cases valid with
    | clause goal source substitution premises member headMatches premisesValid =>
        obtain ⟨fuel, checked⟩ := ValidDerivations.check_complete premisesValid
        refine ⟨fuel + 1, ?_⟩
        simp only [checkDerivation, Bool.and_eq_true]
        letI : Decidable (source ∈ program) := decidableListMem source program
        exact ⟨⟨decide_eq_true member, decide_eq_true headMatches⟩, checked⟩

  /-- Replay completeness for a valid proof forest. -/
  theorem ValidDerivations.check_complete
      (valid : ValidDerivations program goals derivations) :
      ∃ fuel,
        checkDerivations (checkDerivation fuel program) goals derivations = true := by
    cases valid with
    | nil => exact ⟨0, rfl⟩
    | cons goal derivation goals derivations head tail =>
        obtain ⟨headFuel, headChecked⟩ := ValidDerivation.check_complete head
        obtain ⟨tailFuel, tailChecked⟩ := ValidDerivations.check_complete tail
        let fuel := headFuel + tailFuel
        refine ⟨fuel, ?_⟩
        simp only [checkDerivations, Bool.and_eq_true]
        exact ⟨
          checkDerivation_mono (Nat.le_add_right headFuel tailFuel) headChecked,
          checkDerivations_mono
            (fun requested child accepted =>
              checkDerivation_mono (Nat.le_add_left tailFuel headFuel) accepted)
            _ _ tailChecked⟩
end

/-- The proof-tree calculus is sound and complete for declarative `Entails`. -/
theorem entails_iff_exists_validDerivation :
    Entails program goal ↔
      ∃ derivation, ValidDerivation program goal derivation := by
  constructor
  · exact Entails.hasDerivation
  · rintro ⟨derivation, valid⟩
    exact valid.sound

/-- Executable replay is complete for finite declarative derivations when the
caller may supply enough fuel. Together with `checkDerivation_sound`, this is a
reflection theorem for the certificate checker. -/
theorem entails_iff_exists_checkedDerivation :
    Entails program goal ↔
      ∃ derivation fuel, checkDerivation fuel program goal derivation = true := by
  constructor
  · intro entails
    obtain ⟨derivation, valid⟩ := entails.hasDerivation
    obtain ⟨fuel, checked⟩ := valid.check_complete
    exact ⟨derivation, fuel, checked⟩
  · rintro ⟨derivation, fuel, checked⟩
    exact (checkDerivation_sound fuel program goal derivation checked).sound

end Zil.Horn
