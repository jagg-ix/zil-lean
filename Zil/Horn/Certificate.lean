module

public import Zil.Horn.Resolution

@[expose] public section

namespace Zil.Horn

/-- Lean core does not provide proposition-level decidability for `List.Mem`;
the certificate checker needs it to reflect clause membership into a proof. -/
def decidableListMem [DecidableEq α] (value : α) :
    (values : List α) → Decidable (value ∈ values)
  | [] => .isFalse (by simp)
  | head :: tail =>
      if equal : value = head then
        .isTrue (by simp [equal])
      else
        match decidableListMem value tail with
        | .isTrue member => .isTrue (by simp [member])
        | .isFalse absent => .isFalse (by simp [equal, absent])

mutual
  /-- A proof tree is valid when it names a program clause, instantiates its
  head to the claimed atom, and supplies a valid child for every instantiated
  body atom. This relation contains no dependency on the search procedure. -/
  inductive ValidDerivation (program : Program) : Atom → Derivation → Prop where
    | clause (goal : Atom) (source : Clause) (substitution : Substitution)
        (premises : List Derivation)
        (member : source ∈ program)
        (headMatches : goal = source.head.substitute substitution)
        (premisesValid : ValidDerivations program
          (source.body.map (Atom.substitute substitution)) premises) :
        ValidDerivation program goal (.clause source substitution premises)

  /-- Pointwise validity for the proof forest associated with a conjunction. -/
  inductive ValidDerivations (program : Program) :
      List Atom → List Derivation → Prop where
    | nil : ValidDerivations program [] []
    | cons (goal : Atom) (derivation : Derivation)
        (goals : List Atom) (derivations : List Derivation)
        (head : ValidDerivation program goal derivation)
        (tail : ValidDerivations program goals derivations) :
        ValidDerivations program (goal :: goals) (derivation :: derivations)
end

mutual
  /-- Certificate soundness: a valid proof tree denotes a declarative Horn
  consequence. The theorem is independent of unification and search code. -/
  theorem ValidDerivation.sound
      (valid : ValidDerivation program goal derivation) : Entails program goal := by
    cases valid with
    | clause goal source substitution premises member headMatches premisesValid =>
        rw [headMatches]
        apply Entails.clause source member substitution
        intro bodyGoal bodyMember
        exact ValidDerivations.soundMember premisesValid
          (bodyGoal.substitute substitution)
          (List.mem_map_of_mem bodyMember)

  theorem ValidDerivations.soundMember
      (valid : ValidDerivations program goals derivations) :
      ∀ goal, goal ∈ goals → Entails program goal := by
    intro requested member
    cases valid with
    | nil => simp at member
    | cons goal derivation goals derivations head tail =>
        simp only [List.mem_cons] at member
        rcases member with equal | member
        · cases equal
          exact ValidDerivation.sound head
        · exact ValidDerivations.soundMember tail requested member
end

/-- Check two proof-forest lists pointwise with a supplied node checker. -/
def checkDerivations
    (checkOne : Atom → Derivation → Bool) :
    List Atom → List Derivation → Bool
  | [], [] => true
  | goal :: goals, derivation :: derivations =>
      checkOne goal derivation && checkDerivations checkOne goals derivations
  | _, _ => false

/-- Fuel-bounded independent replay of a proof-tree certificate. Search traces,
unifier return values, and resolver control flow are not consulted. -/
def checkDerivation : Nat → Program → Atom → Derivation → Bool
  | 0, _, _, _ => false
  | fuel + 1, program, goal, .clause source substitution premises =>
      @decide (source ∈ program) (decidableListMem source program) &&
      decide (goal = source.head.substitute substitution) &&
      checkDerivations (checkDerivation fuel program)
        (source.body.map (Atom.substitute substitution)) premises

theorem checkDerivations_sound
    {checkOne : Atom → Derivation → Bool}
    (sound : ∀ goal derivation, checkOne goal derivation = true →
      ValidDerivation program goal derivation) :
    ∀ goals derivations,
      checkDerivations checkOne goals derivations = true →
      ValidDerivations program goals derivations := by
  intro goals derivations checked
  induction goals generalizing derivations with
  | nil =>
      cases derivations with
      | nil => exact .nil
      | cons _ _ => simp [checkDerivations] at checked
  | cons goal goals induction =>
      cases derivations with
      | nil => simp [checkDerivations] at checked
      | cons derivation derivations =>
          simp only [checkDerivations, Bool.and_eq_true] at checked
          exact .cons goal derivation goals derivations
            (sound goal derivation checked.1)
            (induction derivations checked.2)

/-- Independent certificate replay is sound with respect to the structural
validity relation. -/
theorem checkDerivation_sound :
    ∀ fuel program goal derivation,
      checkDerivation fuel program goal derivation = true →
      ValidDerivation program goal derivation := by
  intro fuel
  induction fuel with
  | zero =>
      intro program goal derivation checked
      simp [checkDerivation] at checked
  | succ fuel induction =>
      intro program goal derivation checked
      cases derivation with
      | clause source substitution premises =>
          simp only [checkDerivation, Bool.and_eq_true] at checked
          letI : Decidable (source ∈ program) := decidableListMem source program
          have member : source ∈ program := of_decide_eq_true checked.1.1
          have headMatches : goal = source.head.substitute substitution :=
            of_decide_eq_true checked.1.2
          exact .clause goal source substitution premises member headMatches
            (checkDerivations_sound
              (fun premise child accepted => induction program premise child accepted)
              _ _ checked.2)

/-- The independently checkable proposition attached to one solver answer. -/
def Solution.Certified
    (program : Program) (goals : List Atom) (solution : Solution) : Prop :=
  ValidDerivations program
    (goals.map (Atom.substitute solution.substitution)) solution.derivations

/-- Runtime certificate replay. A `true` result can be converted into
`Solution.Certified` by `of_decide_eq_true`. -/
def Solution.certificateValid
    (program : Program) (goals : List Atom) (solution : Solution) : Bool :=
  checkDerivations (checkDerivation solution.depth program)
    (goals.map (Atom.substitute solution.substitution)) solution.derivations

theorem Solution.certificateValid_sound
    {program : Program} {goals : List Atom} {solution : Solution}
    (accepted : solution.certificateValid program goals = true) :
    solution.Certified program goals :=
  checkDerivations_sound
    (fun goal derivation checked =>
      checkDerivation_sound solution.depth program goal derivation checked)
    _ _ accepted

/-- A certified solution entails every instantiated query goal. -/
theorem Solution.entails
    {program : Program} {goals : List Atom} {solution : Solution}
    (certified : solution.Certified program goals) :
    ∀ goal, goal ∈ goals → Entails program (goal.substitute solution.substitution) := by
  intro goal member
  exact ValidDerivations.soundMember certified
    (goal.substitute solution.substitution)
    (List.mem_map_of_mem member)

/-- End-to-end soundness for an independently accepted solver answer. -/
theorem Solution.certificateValid_entails
    {program : Program} {goals : List Atom} {solution : Solution}
    (accepted : solution.certificateValid program goals = true) :
    ∀ goal, goal ∈ goals → Entails program (goal.substitute solution.substitution) :=
  Solution.entails (solution := solution) (solution.certificateValid_sound accepted)

/-- Retain only answers whose proof trees pass independent replay. Cutoff state
and answer order are preserved. -/
def SearchResult.onlyCertified
    (program : Program) (goals : List Atom) (result : SearchResult) : SearchResult :=
  { result with solutions := result.solutions.filter fun solution =>
      solution.certificateValid program goals }

/-- The sound-by-construction entry point for clients that consume solver
answers programmatically. -/
def solveCertifiedDepth
    (program : Program) (goals : List Atom) (limit : Nat) : SearchResult :=
  (solveDepth program goals limit).onlyCertified program goals

/-- The bounded, semantically certified solvability proposition discharged by
`horn_certify`. -/
def HasCertifiedSolution
    (program : Program) (goals : List Atom) (limit : Nat := 32) : Prop :=
  !(solveCertifiedDepth program goals limit).solutions.isEmpty = true

theorem SearchResult.mem_onlyCertified
    {program : Program} {goals : List Atom} {result : SearchResult}
    (member : solution ∈ (result.onlyCertified program goals).solutions) :
    solution.certificateValid program goals = true := by
  exact (List.mem_filter.mp member).2

/-- Generic solver soundness: every answer exposed by `solveCertifiedDepth`
entails every instantiated atom in the original query conjunction. -/
theorem solveCertifiedDepth_entails
    {program : Program} {goals : List Atom} {limit : Nat} {solution : Solution}
    (member : solution ∈ (solveCertifiedDepth program goals limit).solutions) :
    ∀ goal, goal ∈ goals → Entails program (goal.substitute solution.substitution) :=
  solution.certificateValid_entails
    (SearchResult.mem_onlyCertified (result := solveDepth program goals limit) member)

end Zil.Horn
