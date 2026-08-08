import Zil.Horn

open Zil.Horn

namespace Zil.Test.Horn

private def parseProgram! (source : String) : Program :=
  match Parser.parseText source with
  | .ok program => program
  | .error _ => []

private def parseGoals! (source : String) : List Atom :=
  match Parser.parseGoalsText source with
  | .ok goals => goals
  | .error _ => []

def listProgram : Program := parseProgram! "
  % constructors and recursive clauses from HORC's list.hn
  element(0).
  element(1).
  list(nil).
  list(cons(L,E)) :- list(L), element(E).
  concat(L, nil, L) :- list(L).
  concat(L1, cons(L2,E2), cons(Lc,E2)) :- element(E2), concat(L1,L2,Lc).
  member(E, cons(L,E)) :- list(L).
  member(E2, cons(L,E1)) :- element(E1), member(E2,L).
"

def choiceProgram : Program := parseProgram! "
  color(red).
  color(blue).
"

def loopingProgram : Program := parseProgram! "loop(X) :- loop(X)."

example : (Parser.parseText "parent(alice,bob). ancestor(X,Y) :- parent(X,Y).").isOk = true := by
  native_decide

example : (unifyTerm (.variable "X") (.app "f" [.variable "X"]) []).isNone = true := by
  native_decide

example : HasCertifiedSolution listProgram (parseGoals! "list(cons(cons(nil,0),1))") 8 := by
  horn_certify

example : HasSolution listProgram
    (parseGoals! "concat(cons(nil,0), cons(nil,1), cons(cons(nil,0),1))") 12 := by
  horn_solve

example : (solveDepth choiceProgram (parseGoals! "color(X)") 2).solutions.length = 2 := by
  native_decide

example :
    let goals := parseGoals! "color(X)"
    (solveCertifiedDepth choiceProgram goals 2).solutions.all
      (fun solution => solution.certificateValid choiceProgram goals) = true := by
  native_decide

example :
    let goals := parseGoals! "concat(cons(nil,0), cons(nil,1), Result)"
    (solveDepth listProgram goals 12).solutions.all
      (fun solution => solution.certificateValid listProgram goals) = true := by
  native_decide

def forgedRedProof : Derivation :=
  .clause { head := { predicate := "color", arguments := [.constant "red"] } } [] []

def redAtom : Atom :=
  { predicate := "red" }

def redFact : Clause := { head := redAtom }

theorem redEntails : Entails [redFact] redAtom := by
  have premises : ∀ goal, goal ∈ redFact.body →
      Entails [redFact] (goal.substitute []) := by
    intro goal member
    simp [redFact] at member
  simpa [redFact, redAtom, Atom.substitute, Term.substitute] using
    Entails.clause redFact (by simp) [] premises

example : ∃ derivation, ValidDerivation [redFact] redAtom derivation :=
  redEntails.hasDerivation

example :
    ∃ derivation fuel,
      checkDerivation fuel [redFact] redAtom derivation = true :=
  entails_iff_exists_checkedDerivation.mp redEntails

example :
    checkDerivation 1 choiceProgram
      { predicate := "color", arguments := [.constant "blue"] }
      forgedRedProof = false := by
  native_decide

example :
    let result := solveDepth loopingProgram (parseGoals! "loop(a)") 4
    result.solutions.isEmpty && result.cutoff = true := by
  native_decide

example : (firstSolutionUpTo listProgram (parseGoals! "member(1, cons(nil,1))") 8).isSome = true := by
  native_decide

end Zil.Test.Horn
