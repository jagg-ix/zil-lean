module

public import Zil.Horn.Unify

@[expose] public section

namespace Zil.Horn

/-- One auditable SLD transition. The clause has already been standardized
apart, and `substitution` is the complete substitution after unification. -/
structure ResolutionStep where
  depth : Nat
  selected : Atom
  clauseIndex : Nat
  clause : Clause
  substitution : Substitution
  remainingGoals : List Atom
  deriving Repr, Inhabited

structure Solution where
  substitution : Substitution
  depth : Nat
  trace : List ResolutionStep := []
  derivations : List Derivation := []
  deriving Repr, Inhabited

/-- `cutoff` records that at least one branch could continue below the supplied
depth bound. This is the same useful distinction HORC makes between finite
failure and `depth_limit_exceeded`. -/
structure SearchResult where
  solutions : List Solution := []
  cutoff : Bool := false
  deriving Repr, Inhabited

namespace SearchResult

def append (left right : SearchResult) : SearchResult :=
  { solutions := left.solutions ++ right.solutions,
    cutoff := left.cutoff || right.cutoff }

def prependStep (step : ResolutionStep) (result : SearchResult) : SearchResult :=
  { result with solutions := result.solutions.map fun solution =>
      { solution with trace := step :: solution.trace } }

def clauseInstanceSubstitution
    (source : Clause) (stem : String) (substitution : Substitution) : Substitution :=
  source.variables.map fun name =>
    (name, (Term.variable (stem ++ name)).substitute substitution)

/-- Fold one successful SLD transition into the returned proof forest. The
first `bodyLength` recursive derivations discharge this clause's premises; the
remaining derivations still discharge the other goals in the caller's list. -/
def prependDerivation
    (source : Clause) (stem : String) (bodyLength : Nat)
    (result : SearchResult) : SearchResult :=
  { result with solutions := result.solutions.map fun solution =>
      let parts := solution.derivations.splitAt bodyLength
      let clauseSubstitution := clauseInstanceSubstitution source stem solution.substitution
      { solution with
        derivations := .clause source clauseSubstitution parts.1 :: parts.2 } }

end SearchResult

def freshStem (depth clauseIndex : Nat) : String :=
  s!"$sld.{depth}.{clauseIndex}."

mutual
  /-- Leftmost, depth-first SLD resolution with clause-order backtracking and a
  sound occurs check. The bound counts clause applications, so a fact is found at
  depth one. Every recursive call either succeeds or consumes one unit of depth. -/
  partial def search
      (program : Program) (goals : List Atom) (substitution : Substitution)
      (limit depth : Nat) : SearchResult :=
    match goals with
    | [] => { solutions := [{ substitution := normalizeSubstitution substitution, depth }] }
    | selected :: rest =>
        if depth >= limit then { cutoff := true }
        else searchClauses program program selected rest substitution limit depth 0

  partial def searchClauses
      (program clauses : Program) (selected : Atom) (rest : List Atom)
      (substitution : Substitution) (limit depth clauseIndex : Nat) : SearchResult :=
    match clauses with
    | [] => {}
    | sourceClause :: remainingClauses =>
        let stem := freshStem depth clauseIndex
        let clause := sourceClause.rename stem
        let branch : SearchResult :=
          match unifyAtom selected clause.head substitution with
          | none => {}
          | some nextSubstitution =>
              let nextGoals := clause.body ++ rest
              let normalized := normalizeSubstitution nextSubstitution
              let step : ResolutionStep := {
                depth
                selected := selected.substitute substitution
                clauseIndex
                clause
                substitution := normalized
                remainingGoals := nextGoals.map (Atom.substitute normalized)
              }
              ((search program nextGoals nextSubstitution limit (depth + 1)).prependDerivation
                sourceClause stem sourceClause.body.length).prependStep step
        branch.append
          (searchClauses program remainingClauses selected rest substitution limit depth (clauseIndex + 1))
end

/-- Enumerate every solution reachable within `limit` clause applications.
Only variables occurring in the original query are reported. -/
def solveDepth (program : Program) (goals : List Atom) (limit : Nat) : SearchResult :=
  let queryVariables := (goals.flatMap Atom.variables).eraseDups
  let result := search program goals [] limit 0
  { result with solutions := result.solutions.map fun solution =>
      { solution with substitution := projectSubstitution queryVariables solution.substitution } }

def solveAtom (program : Program) (goal : Atom) (limit : Nat := 32) : SearchResult :=
  solveDepth program [goal] limit

def hasSolution (program : Program) (goals : List Atom) (limit : Nat := 32) : Bool :=
  !(solveDepth program goals limit).solutions.isEmpty

/-- Iterative deepening for the first answer. It is finite because callers
provide `maximumDepth`; increasing that bound approaches complete SLD search
without making a total Lean function pretend that arbitrary Horn programs halt. -/
def firstSolutionUpTo
    (program : Program) (goals : List Atom) (maximumDepth : Nat) : Option Solution :=
  (List.range (maximumDepth + 1)).findSome? fun limit =>
    (solveDepth program goals limit).solutions.head?

/-- Declarative least-closure reading of definite clauses. This proposition is
the proof-facing semantics; the executable resolver remains explicitly bounded
and exposes its trace rather than claiming termination for arbitrary programs. -/
inductive Entails (program : Program) : Atom → Prop where
  | clause (source : Clause) (member : source ∈ program) (substitution : Substitution)
      (premises : ∀ goal, goal ∈ source.body →
        Entails program (goal.substitute substitution)) :
      Entails program (source.head.substitute substitution)

/-- The proposition discharged by `horn_solve`: bounded operational solvability.
It is intentionally distinct from unbounded declarative entailment. -/
def HasSolution (program : Program) (goals : List Atom) (limit : Nat := 32) : Prop :=
  hasSolution program goals limit = true

end Zil.Horn
