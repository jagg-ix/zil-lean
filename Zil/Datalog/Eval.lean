module

public import Zil.Datalog.Unify

@[expose] public section

namespace Zil.Datalog

def matchPattern (facts : List Atom) (pattern : Pattern)
    (substitution : Substitution) : List Substitution :=
  facts.filterMap fun atom => unify pattern atom substitution

def satisfyBody (facts : List Atom) (body : List Pattern) : List Substitution :=
  body.foldl
    (fun substitutions pattern =>
      substitutions.flatMap (matchPattern facts pattern))
    [[]]

def excludesPattern (facts : List Atom) (pattern : Pattern)
    (substitution : Substitution) : Bool :=
  !(facts.any fun atom => (unify pattern atom substitution).isSome)

def satisfyNegativeBody (facts : List Atom) (body : List Pattern)
    (substitutions : List Substitution) : List Substitution :=
  body.foldl
    (fun remaining pattern => remaining.filter (excludesPattern facts pattern))
    substitutions

def applyRule (facts : List Atom) (rule : Rule) : List Atom :=
  (satisfyNegativeBody facts rule.negativePatterns
    (satisfyBody facts rule.positiveBody)).filterMap
    (instantiate rule.head)

def deriveStep (program : Program) (facts : List Atom) : List Atom :=
  (facts ++ program.rules.flatMap (applyRule facts)).eraseDups

def derive (program : Program) : Nat → List Atom
  | 0 => program.facts.eraseDups
  | fuel + 1 => deriveStep program (derive program fuel)

def deriveRuleSet (rules : List Rule) : Nat → List Atom → List Atom
  | 0, facts => facts.eraseDups
  | fuel + 1, facts =>
      deriveRuleSet rules fuel ((facts ++ rules.flatMap (applyRule facts)).eraseDups)

/-- Evaluate strata from low to high, saturating each stratum before any rule
that may depend negatively on it is considered. -/
def deriveStratified (program : Program) (fuel : Nat := 32) : List Atom :=
  (List.range (program.maxStratum + 1)).foldl (fun facts stratum =>
    let rules := program.rules.filter fun rule => program.stratumOf rule.head.relation == stratum
    deriveRuleSet rules fuel facts) program.facts

def Program.hasNegation (program : Program) : Bool :=
  program.rules.any fun rule => !rule.negativePatterns.isEmpty

def deriveProgram (program : Program) (fuel : Nat := 32) : List Atom :=
  if program.hasNegation then deriveStratified program fuel else derive program fuel

def query (program : Program) (pattern : Pattern) (fuel : Nat := 32) : List Substitution :=
  matchPattern (deriveProgram program fuel) pattern []

def holds (program : Program) (atom : Atom) (fuel : Nat := 32) : Bool :=
  (deriveProgram program fuel).contains atom

end Zil.Datalog
