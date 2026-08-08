module

@[expose] public section

namespace Zil.Horn

/-- Variables are named so parsed HORC programs retain their source vocabulary. -/
abbrev Variable := String

/-- First-order Horn terms. Unlike `Zil.Datalog.Term`, applications may nest and
therefore represent constructor trees such as `cons(nil, successor(zero))`. -/
inductive Term where
  | variable (name : Variable)
  | app (symbol : String) (arguments : List Term)
  deriving Repr, Inhabited

namespace Term

partial def beq : Term → Term → Bool
  | .variable left, .variable right => left == right
  | .app leftSymbol leftArgs, .app rightSymbol rightArgs =>
      leftSymbol == rightSymbol && beqList leftArgs rightArgs
  | _, _ => false
where
  beqList : List Term → List Term → Bool
    | [], [] => true
    | left :: leftRest, right :: rightRest => beq left right && beqList leftRest rightRest
    | _, _ => false

instance : BEq Term := ⟨beq⟩

mutual
  /-- A computable equality decision for nested first-order terms. Lean's
  stock deriving handler does not traverse this nested recursive occurrence. -/
  def decEq : (left right : Term) → Decidable (left = right)
    | .variable left, .variable right =>
        if equal : left = right then
          .isTrue (by cases equal; rfl)
        else .isFalse (by intro same; cases same; exact equal rfl)
    | .app leftSymbol leftArgs, .app rightSymbol rightArgs =>
        if symbolsEqual : leftSymbol = rightSymbol then
            match decEqList leftArgs rightArgs with
            | .isTrue argumentsEqual => .isTrue (by cases symbolsEqual; cases argumentsEqual; rfl)
            | .isFalse different => .isFalse (by intro equal; cases equal; exact different rfl)
        else .isFalse (by intro same; cases same; exact symbolsEqual rfl)
    | .variable _, .app _ _ => .isFalse (by intro equal; cases equal)
    | .app _ _, .variable _ => .isFalse (by intro equal; cases equal)

  def decEqList : (left right : List Term) → Decidable (left = right)
    | [], [] => .isTrue rfl
    | left :: leftRest, right :: rightRest =>
        match decEq left right with
        | .isFalse different => .isFalse (by intro equal; cases equal; exact different rfl)
        | .isTrue headsEqual =>
            match decEqList leftRest rightRest with
            | .isTrue tailsEqual => .isTrue (by cases headsEqual; cases tailsEqual; rfl)
            | .isFalse different => .isFalse (by intro equal; cases equal; exact different rfl)
    | [], _ :: _ => .isFalse (by intro equal; cases equal)
    | _ :: _, [] => .isFalse (by intro equal; cases equal)
end

instance : DecidableEq Term := decEq

def constant (symbol : String) : Term := .app symbol []

def variables : Term → List Variable
  | .variable name => [name]
  | .app _ arguments => (arguments.flatMap variables).eraseDups

partial def isGround : Term → Bool
  | .variable _ => false
  | .app _ arguments => arguments.all isGround

partial def rename (stem : String) : Term → Term
  | .variable name => .variable (stem ++ name)
  | .app symbol arguments => .app symbol (arguments.map (rename stem))

partial def render : Term → String
  | .variable name => name
  | .app symbol [] => symbol
  | .app symbol arguments =>
      symbol ++ "(" ++ String.intercalate ", " (arguments.map render) ++ ")"

end Term

/-- A predicate application. Function symbols live in `arguments`; predicate
symbols remain separate so predicate and constructor namespaces cannot be
confused by the resolver. -/
structure Atom where
  predicate : String
  arguments : List Term := []
  deriving Repr, BEq, DecidableEq, Inhabited

namespace Atom

def variables (atom : Atom) : List Variable :=
  (atom.arguments.flatMap Term.variables).eraseDups

def isGround (atom : Atom) : Bool := atom.arguments.all Term.isGround

def rename (stem : String) (atom : Atom) : Atom :=
  { atom with arguments := atom.arguments.map (Term.rename stem) }

def render (atom : Atom) : String :=
  if atom.arguments.isEmpty then atom.predicate
  else atom.predicate ++ "(" ++ String.intercalate ", " (atom.arguments.map Term.render) ++ ")"

end Atom

/-- A definite Horn clause `head :- body`. An empty body is a fact. -/
structure Clause where
  head : Atom
  body : List Atom := []
  deriving Repr, BEq, DecidableEq, Inhabited

namespace Clause

def variables (clause : Clause) : List Variable :=
  (clause.head.variables ++ clause.body.flatMap Atom.variables).eraseDups

/-- Standardize a clause apart before one SLD step. -/
def rename (stem : String) (clause : Clause) : Clause :=
  { head := clause.head.rename stem, body := clause.body.map (Atom.rename stem) }

def render (clause : Clause) : String :=
  if clause.body.isEmpty then clause.head.render ++ "."
  else clause.head.render ++ " :- " ++ String.intercalate ", " (clause.body.map Atom.render) ++ "."

end Clause

/-- An ordered Horn program. Clause order is operationally significant for
depth-first SLD resolution, matching HORC and Prolog. -/
abbrev Program := List Clause

/-- A finite first-order substitution. Cyclic bindings are rejected by the
occurs check in `Zil.Horn.Unify`. -/
abbrev Substitution := List (Variable × Term)

/-- A proof-tree certificate. Each node records the original source clause, an
instance substitution for that clause, and one child certificate per body atom.
Unlike an operational trace, this tree can be checked directly against the
declarative `Entails` semantics. -/
inductive Derivation where
  | clause (source : Clause) (substitution : Substitution)
      (premises : List Derivation)
  deriving Repr, Inhabited

end Zil.Horn
